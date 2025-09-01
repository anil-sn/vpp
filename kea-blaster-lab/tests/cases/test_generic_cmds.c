#include "test_main.h"

static kea_ctrl_context_t g_ctx = NULL;

TEST_CASE (test_list_commands_success)
{
    cJSON *response = kea_cmd_list_commands (g_ctx, "dhcp4");
    ASSERT_KEA_API_OK (response, g_ctx);
cleanup:
    cJSON_Delete (response);
}

TEST_CASE (test_list_commands_fail_bad_service)
{
    cJSON *response = kea_cmd_list_commands (g_ctx, "nonexistent-service");
    ASSERT_NULL (response, "Expected API call to fail for bad service.");
    const char *error = kea_ctrl_get_last_error (g_ctx);
    ASSERT_TRUE (strstr (error, "not configured for the server type") != NULL, "Error message mismatch.");
cleanup:
    return;
}

TEST_CASE (test_version_get_multiple_services_success)
{
    cJSON *response = NULL;
    const char *services[] = {"dhcp4", "dhcp6", NULL};

    response = kea_cmd_version_get (g_ctx, services);
    ASSERT_KEA_API_OK (response, g_ctx);

    // FIX: The server returns one response object PER service in the top-level array.
    ASSERT_INT_EQ (cJSON_GetArraySize (response), 2);

    cJSON *service_info = NULL;
    cJSON_ArrayForEach (service_info, response) {
        cJSON *result_item = cJSON_GetObjectItem (service_info, "result");
        ASSERT_NOT_NULL (result_item, "Per-service response missing 'result' key.");

        cJSON *text_item = cJSON_GetObjectItem (service_info, "text");
        const char *err_text = cJSON_IsString (text_item) ? text_item->valuestring : "Unknown error";
        ASSERT_INT_EQ_MSG (result_item->valueint, 0, "Service reported failure: %s", err_text);
    }
cleanup:
    cJSON_Delete (response);
}

void run_generic_commands_tests (void)
{
    printf ("--- Starting Generic Commands Tests (REST API) ---\n");
    g_ctx = kea_ctrl_create (NULL);
    if (!g_ctx) {
        tests_failed++;
        tests_run += 3;
        return;
    }
    RUN_TEST (test_list_commands_success);
    RUN_TEST (test_list_commands_fail_bad_service);
    RUN_TEST (test_version_get_multiple_services_success);
    kea_ctrl_destroy (g_ctx);
}