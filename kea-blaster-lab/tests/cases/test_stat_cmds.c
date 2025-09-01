#include "test_main.h"
#include "helpers/config_helper.h"
#include "helpers/bngblaster_api.h"

static kea_ctrl_context_t g_ctx = NULL;
static cJSON *g_original_dhcp4_config = NULL;
const char *STATS_ENABLED_CONFIG =
                "{\"interfaces-config\": {\"interfaces\": [\"br101\"]},\"control-socket\": {\"socket-type\": \"unix\", \"socket-name\": \"/var/run/kea/kea-dhcp4-ctrl.sock\"},\"lease-database\": {\"type\": \"memfile\", \"persist\": false},\"hooks-libraries\": [{\"library\": \"/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_subnet_cmds.so\"},{\"library\": \"/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_lease_cmds.so\"},{\"library\": \"/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_stat_cmds.so\"}],\"subnet4\": [{\"id\": 101, \"subnet\": \"192.101.0.0/16\", \"pools\": [{\"pool\": \"192.101.1.2 - 192.101.1.254\"}]}]}";

static bool setup_stat_tests (void)
{
    g_ctx = kea_ctrl_create (NULL);
    if (!g_ctx) {
        return false;
    }
    cJSON *response = kea_cmd_config_get (g_ctx, "dhcp4");
    if (response) {
        g_original_dhcp4_config = cJSON_DetachItemFromObject (cJSON_GetObjectItem (cJSON_GetArrayItem (response, 0), "arguments"), "Dhcp4");
        cJSON_Delete (response);
    }
    return g_original_dhcp4_config != NULL;
}
static void teardown_stat_tests (void)
{
    if (g_ctx && g_original_dhcp4_config) {
        apply_kea_config_from_json (g_ctx, "dhcp4", g_original_dhcp4_config);
        sleep (2);
        cJSON_Delete (g_original_dhcp4_config);
        g_original_dhcp4_config = NULL;
    }
    if (g_ctx) {
        kea_ctrl_destroy (g_ctx);
        g_ctx = NULL;
    }
}

TEST_CASE (test_statistic_get_all_with_hook_loaded)
{
    const char *instance_name = "stat_test";
    bngblaster_ctx_t *bng_ctx = NULL;
    cJSON *bng_config = NULL;
    cJSON *bng_start_params = NULL;
    char *response_str = NULL;
    cJSON *stats_result_response = NULL;

    printf ("\n       -> Applying config with stat_cmds hook... ");
    ASSERT_TRUE (apply_kea_config_from_string (g_ctx, "dhcp4", STATS_ENABLED_CONFIG), "Failed to apply stats-enabled config.");
    sleep (2);
    printf ("Applied.");

    bng_ctx = bngblaster_init ("127.0.0.1", 8001);
    ASSERT_NOT_NULL (bng_ctx, "Failed to init BNG Blaster context.");

    bng_config = cJSON_Parse ("{"
                                    "\"interfaces\": {\"access\": [{\"interface\": \"cli-eth1\", \"type\": \"ipoe\", \"outer-vlan\": 101}]},"
                                    "\"dhcp\": {\"enable\": true},"
                                    "\"ipoe\": {\"ipv6\": false}"
                                    "}");
    bng_start_params = cJSON_Parse ("{\"session_count\": 2, \"report\": true}");

    bngblaster_error_t err = bngblaster_instance_create (bng_ctx, instance_name, bng_config);
    ASSERT_BNG_OK (err, bng_ctx, "bngblaster_instance_create failed");

    err = bngblaster_instance_start (bng_ctx, instance_name, bng_start_params, NULL);
    ASSERT_BNG_OK (err, bng_ctx, "bngblaster_instance_start failed");

    // FIX: Wait for the instance to be fully started before issuing commands to prevent race condition.
    printf ("\n       -> Waiting for BNG Blaster instance to be running... ");
    bool instance_started = false;
    for (int i = 0; i < 10; i++) {
        sleep (1);
        char *status_str = NULL;
        err = bngblaster_instance_get_status (bng_ctx, instance_name, &status_str);
        if (err == BBERR_OK && status_str) {
            cJSON *status_json = cJSON_Parse (status_str);
            free (status_str);
            if (status_json) {
                cJSON *status_item = cJSON_GetObjectItem (status_json, "status");
                if (cJSON_IsString (status_item) && strcmp (status_item->valuestring, "started") == 0) {
                    instance_started = true;
                    cJSON_Delete (status_json);
                    break;
                }
                cJSON_Delete (status_json);
            }
        }
    }
    ASSERT_TRUE (instance_started, "Timeout waiting for BNG Blaster instance to start.");
    printf ("Started.");

    printf ("\n       -> Running 2 DHCPv4 sessions to generate stats... ");
    bool sessions_established = false;
    for (int i = 0; i < 15; i++) {
        sleep (1);
        err = bngblaster_instance_command (bng_ctx, instance_name, "stats", NULL, &response_str);
        if (err != BBERR_OK) {
            continue;
        }
        cJSON *stats = cJSON_Parse (response_str);
        free (response_str); response_str = NULL;
        if (!stats) {
            continue;
        }
        cJSON *established = cJSON_GetObjectItem (stats, "sessions-established");
        if (cJSON_IsNumber (established) && established->valueint >= 2) {
            sessions_established = true;
            cJSON_Delete (stats);
            break;
        }
        cJSON_Delete (stats);
    }
    ASSERT_TRUE (sessions_established, "Timeout waiting for sessions to become established.");
    printf ("Done.");

    printf ("\n       -> Fetching all statistics... ");
    stats_result_response = kea_cmd_statistic_get_all (g_ctx, "dhcp4");
    ASSERT_KEA_API_OK (stats_result_response, g_ctx);

    cJSON *arguments = cJSON_GetObjectItem (cJSON_GetArrayItem (stats_result_response, 0), "arguments");
    cJSON *pkt_received = cJSON_GetObjectItem (arguments, "pkt4-received");
    ASSERT_NOT_NULL (pkt_received, "Stats response missing 'pkt4-received'.");

    cJSON *value_array_wrapper = cJSON_GetArrayItem (pkt_received, 0);
    cJSON *count = cJSON_GetArrayItem (value_array_wrapper, 0);
    ASSERT_TRUE (cJSON_IsNumber (count) && count->valueint >= 4, "Expected pkt4-received to be >= 4 for 2 sessions.");
    printf ("Verified pkt4-received is %d.", (int) count->valuedouble);

cleanup:
    if (bng_ctx) {
        bngblaster_instance_stop (bng_ctx, instance_name);
        bool stopped = false;
        for (int i = 0; i < 10; i++) {
            sleep (1);
            char *status_str = NULL;
            if (bngblaster_instance_get_status (bng_ctx, instance_name, &status_str) == BBERR_OK) {
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
            printf ("\n       [WARN] Timed out waiting for instance '%s' to stop.\n", instance_name);
        }
        bngblaster_instance_delete (bng_ctx, instance_name);
        bngblaster_free (bng_ctx);
    }
    cJSON_Delete (bng_config);
    cJSON_Delete (bng_start_params);
    cJSON_Delete (stats_result_response);
}
void run_stat_commands_tests (void)
{
    printf ("--- Starting Statistics Commands Tests (REST API) ---\n");
    if (!setup_stat_tests()) {
        printf ("  [%sFAIL%s] Suite setup failed.\n", KRED, KNRM);
        tests_failed++; tests_run++;
        teardown_stat_tests(); return;
    }
    RUN_TEST (test_statistic_get_all_with_hook_loaded);
    teardown_stat_tests();
}