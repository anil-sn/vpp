#include "test_main.h"

static kea_ctrl_context_t g_ctx = NULL;

TEST_CASE (test_subnet4_list_success)
{
    cJSON *response = NULL;
    response = kea_cmd_subnet4_list (g_ctx);
    ASSERT_KEA_API_OK (response, g_ctx);

    cJSON *arguments = cJSON_GetObjectItem (cJSON_GetArrayItem (response, 0), "arguments");
    ASSERT_JSON_TYPE (arguments, cJSON_IsObject);
    const cJSON *subnets_array = cJSON_GetObjectItem (arguments, "subnets");
    ASSERT_NOT_NULL (subnets_array, "Response missing 'subnets' array.");
    ASSERT_JSON_TYPE (subnets_array, cJSON_IsArray);
    ASSERT_INT_EQ (cJSON_GetArraySize (subnets_array), 4);
cleanup:
    cJSON_Delete (response);
}

TEST_CASE (test_subnet6_list_success)
{
    cJSON *response = NULL;
    response = kea_cmd_subnet6_list (g_ctx);
    ASSERT_KEA_API_OK (response, g_ctx);

    cJSON *arguments = cJSON_GetObjectItem (cJSON_GetArrayItem (response, 0), "arguments");
    ASSERT_JSON_TYPE (arguments, cJSON_IsObject);
    const cJSON *subnets_array = cJSON_GetObjectItem (arguments, "subnets");
    ASSERT_NOT_NULL (subnets_array, "Response missing 'subnets' array.");
    ASSERT_JSON_TYPE (subnets_array, cJSON_IsArray);
    ASSERT_INT_EQ (cJSON_GetArraySize (subnets_array), 4);
cleanup:
    cJSON_Delete (response);
}

void run_subnet_commands_tests (void)
{
    printf ("--- Starting Subnet Commands Tests (REST API) ---\n");
    g_ctx = kea_ctrl_create (NULL);
    if (!g_ctx) {
        printf ("  [%sFAIL%s] Could not create Kea context for subnet tests.\n", KRED, KNRM);
        tests_failed++;
        tests_run += 2;
        return;
    }

    RUN_TEST (test_subnet4_list_success);
    RUN_TEST (test_subnet6_list_success);

    kea_ctrl_destroy (g_ctx);
    g_ctx = NULL;
}