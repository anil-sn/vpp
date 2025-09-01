#include "test_main.h"
#include "helpers/bngblaster_api.h"
#include "helpers/config_helper.h"

// Suite-level shared state
static kea_ctrl_context_t g_ctx = NULL;
static bngblaster_ctx_t *g_bng_ctx = NULL;
static const char *g_instance_name = "lease_suite";

static bool lease_suite_setup (void)
{
    cJSON *bng_config = NULL;
    cJSON *bng_start_params = NULL;
    char *response_str = NULL;
    cJSON *session_info = NULL;
    bool setup_ok = false;

    printf ("\n    [Suite Setup] Initializing contexts and starting BNG Blaster instance '%s'...\n", g_instance_name);
    g_ctx = kea_ctrl_create (NULL);
    g_bng_ctx = bngblaster_init ("127.0.0.1", 8001);
    if (!g_ctx || !g_bng_ctx) {
        goto cleanup;
    }

    bng_config =
                    cJSON_Parse ("{\"interfaces\": {\"access\": [{\"interface\": \"cli-eth1\", \"type\": \"ipoe\", \"outer-vlan\": 101}]}, \"dhcp\": {\"enable\": true},\"ipoe\":{\"ipv6\":false}}");
    bng_start_params = cJSON_Parse ("{\"session_count\": 1, \"report\": true}");
    if (!bng_config || !bng_start_params) {
        goto cleanup;
    }

    if (bngblaster_instance_create (g_bng_ctx, g_instance_name, bng_config) != BBERR_OK) {
        goto cleanup;
    }
    if (bngblaster_instance_start (g_bng_ctx, g_instance_name, bng_start_params, NULL) != BBERR_OK) {
        goto cleanup;
    }

    bool session_established = false;
    for (int i = 0; i < 15; i++) {
        sleep (1);
        if (bngblaster_instance_command (g_bng_ctx, g_instance_name, "session-info", cJSON_Parse ("{\"session-id\": 1}"),
                                        &response_str) == BBERR_OK) {
            session_info = cJSON_Parse (response_str);
            free (response_str); response_str = NULL;
            if (session_info) {
                cJSON *state = cJSON_GetObjectItem (cJSON_GetObjectItem (session_info, "session-info"), "session-state");
                if (cJSON_IsString (state) && strcmp (state->valuestring, "Established") == 0) {
                    session_established = true;
                    break;
                }
                cJSON_Delete (session_info);
                session_info = NULL;
            }
        }
    }

    ASSERT_TRUE (session_established, "Timeout waiting for BNG Blaster session to become Established.");
    printf ("    [Suite Setup] Session established.\n");

    printf ("    [Suite Setup] Waiting 2s for Kea lease backend to stabilize...\n");
    sleep (2);

    setup_ok = true;

cleanup:
    if (!setup_ok) {
        printf ("    [Suite Setup] FAILED.\n");
    }
    cJSON_Delete (session_info); cJSON_Delete (bng_config); cJSON_Delete (bng_start_params);
    return setup_ok;
}

static void lease_suite_teardown (void)
{
    printf ("\n    [Suite Teardown] Stopping and deleting instance '%s'...\n", g_instance_name);
    if (g_bng_ctx) {
        bngblaster_instance_stop (g_bng_ctx, g_instance_name);
        bool stopped = false;
        for (int i = 0; i < 10; i++) {
            sleep (1);
            char *status_str = NULL;
            if (bngblaster_instance_get_status (g_bng_ctx, g_instance_name, &status_str) == BBERR_OK) {
                cJSON *status_json = cJSON_Parse (status_str);
                free (status_str);
                if (status_json) {
                    cJSON *status_item = cJSON_GetObjectItem (status_json, "status");
                    if (cJSON_IsString (status_item) && strcmp (status_item->valuestring, "stopped") == 0) {
                        stopped = true;
                        cJSON_Delete (status_json);
                        break;
                    }
                    cJSON_Delete (status_json);
                }
            }
        }
        if (!stopped) {
            printf ("\n       [WARN] Timed out waiting for instance to stop.\n");
        }
        bngblaster_instance_delete (g_bng_ctx, g_instance_name);
        bngblaster_free (g_bng_ctx); g_bng_ctx = NULL;
    }
    if (g_ctx) {
        kea_ctrl_destroy (g_ctx);
        g_ctx = NULL;
    }
}

TEST_CASE (test_lease4_get_del_and_verify)
{
    cJSON *get_response = NULL;
    cJSON *del_response = NULL;
    cJSON *get_response_after_del = NULL;
    const char *mac = "02:00:00:00:00:01"; // The MAC is static for session 1
    char acquired_ip_from_lease[16] = {0};

    // 1. Get the lease by HW address and verify it exists
    printf ("\n       -> Getting lease by HW address (%s)... ", mac);
    get_response = kea_cmd_lease4_get_by_hw_address (g_ctx, mac);
    ASSERT_KEA_API_OK (get_response, g_ctx);

    cJSON *arguments = cJSON_GetObjectItem (cJSON_GetArrayItem (get_response, 0), "arguments");
    cJSON *leases_array = cJSON_GetObjectItem (arguments, "leases");
    ASSERT_NOT_NULL (leases_array, "Response arguments missing 'leases' array.");
    ASSERT_INT_EQ (cJSON_GetArraySize (leases_array), 1);
    printf ("Found.");

    // 2. Extract IP and delete the lease by its IP
    cJSON *lease_item = cJSON_GetArrayItem (leases_array, 0);
    cJSON *ip_item = cJSON_GetObjectItem (lease_item, "ip-address");
    ASSERT_NOT_NULL (ip_item, "Lease object missing 'ip-address'");
    ASSERT_TRUE (cJSON_IsString (ip_item), "Lease 'ip-address' is not a string");
    strncpy (acquired_ip_from_lease, ip_item->valuestring, sizeof (acquired_ip_from_lease) - 1);

    printf ("\n       -> Deleting lease for IP %s... ", acquired_ip_from_lease);
    del_response = kea_cmd_lease4_del (g_ctx, acquired_ip_from_lease);
    ASSERT_KEA_API_OK (del_response, g_ctx);
    printf ("Deleted.");

    // 3. Verify the lease is gone, handling Kea's inconsistent "not found" response
    printf ("\n       -> Verifying lease for HW address (%s) is gone... ", mac);
    get_response_after_del = kea_cmd_lease4_get_by_hw_address (g_ctx, mac);

    // FIX: Kea's lease_cmds hook has inconsistent behavior for "not found".
    // It can either return success (result:0) with an empty 'leases' array,
    // or failure (result:3) with an error message. We must handle both.
    if (get_response_after_del != NULL) {
        // Case 1: Success with empty array
        arguments = cJSON_GetObjectItem (cJSON_GetArrayItem (get_response_after_del, 0), "arguments");
        leases_array = cJSON_GetObjectItem (arguments, "leases");
        ASSERT_NOT_NULL (leases_array, "Response arguments missing 'leases' array after delete.");
        ASSERT_INT_EQ (cJSON_GetArraySize (leases_array), 0);
    } else {
        // Case 2: Failure with a specific "not found" error message
        const char *error_msg = kea_ctrl_get_last_error (g_ctx);
        ASSERT_NOT_NULL (error_msg, "Error message should not be null.");
        ASSERT_TRUE (strstr (error_msg, "lease(s) found") != NULL, "Expected 'not found' error message from Kea.");
    }
    printf ("Verified.");

cleanup:
    cJSON_Delete (get_response);
    cJSON_Delete (del_response);
    cJSON_Delete (get_response_after_del);
}


void run_lease_commands_tests (void)
{
    printf ("--- Starting Lease Commands Tests (REST API) ---\n");
    if (!lease_suite_setup()) {
        printf ("  [%sFAIL%s] Suite setup failed, skipping tests.\n", KRED, KNRM);
        tests_failed++;
        tests_run++;
        lease_suite_teardown();
        return;
    }
    RUN_TEST (test_lease4_get_del_and_verify);
    lease_suite_teardown();
}