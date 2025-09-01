#include "test_main.h"
#include <string.h>

// The global context is now of type kea_ctrl_context_t, which is the pointer type.
static kea_ctrl_context_t g_ctx = NULL;

TEST_CASE(test_list_commands_success) {
    cJSON* result = kea_cmd_list_commands(g_ctx, "dhcp4");
    ASSERT_NOT_NULL(result);
    const cJSON* commands = cJSON_GetObjectItemCaseSensitive(result, "commands");
    ASSERT_NOT_NULL(commands);
    ASSERT_TRUE(cJSON_IsArray(commands));
    ASSERT_TRUE(cJSON_GetArraySize(commands) > 5);
    cJSON* command = NULL;
    int found = 0;
    cJSON_ArrayForEach(command, commands) {
        if (cJSON_IsString(command) && (strcmp(command->valuestring, "version-get") == 0)) {
            found = 1;
            break;
        }
    }
    ASSERT_TRUE(found);
    cJSON_Delete(result);
}

TEST_CASE(test_list_commands_fail_bad_service) {
    cJSON* result = kea_cmd_list_commands(g_ctx, "nonexistent-service");
    ASSERT_NULL(result);
    const char* error = kea_ctrl_get_last_error(g_ctx);
    ASSERT_NOT_NULL(error);
    ASSERT_TRUE(strstr(error, "service not found") != NULL);
}

TEST_CASE(test_version_get_success) {
    cJSON* result = kea_cmd_version_get(g_ctx, NULL);
    ASSERT_NOT_NULL(result);
    if (cJSON_IsObject(result)) { // Handle single object response
        ASSERT_NOT_NULL(cJSON_GetObjectItemCaseSensitive(result, "extended"));
    } else { // Handle array response
        ASSERT_TRUE(cJSON_IsArray(result));
        ASSERT_TRUE(cJSON_GetArraySize(result) >= 3);
        cJSON* first_service = cJSON_GetArrayItem(result, 0);
        ASSERT_NOT_NULL(first_service);
        ASSERT_NOT_NULL(cJSON_GetObjectItemCaseSensitive(first_service, "service"));
        ASSERT_NOT_NULL(cJSON_GetObjectItemCaseSensitive(first_service, "version"));
    }
    cJSON_Delete(result);
}

TEST_CASE(test_status_get_success) {
    cJSON* result = kea_cmd_status_get(g_ctx, "dhcp4");
    ASSERT_NOT_NULL(result);
    ASSERT_TRUE(cJSON_IsArray(result));
    ASSERT_TRUE(cJSON_GetArraySize(result) == 1);
    cJSON* status_obj = cJSON_GetArrayItem(result, 0);
    ASSERT_NOT_NULL(status_obj);
    const cJSON* pid = cJSON_GetObjectItemCaseSensitive(status_obj, "PID");
    const cJSON* uptime = cJSON_GetObjectItemCaseSensitive(status_obj, "uptime");
    ASSERT_NOT_NULL(pid);
    ASSERT_NOT_NULL(uptime);
    ASSERT_TRUE(cJSON_IsNumber(pid));
    ASSERT_TRUE(cJSON_IsNumber(uptime));
    cJSON_Delete(result);
}

void add_generic_commands_tests(void) {
    printf("--- Starting Generic Commands Tests ---\n");
    
    g_ctx = kea_ctrl_create(NULL);
    if (!g_ctx) {
        printf("  [%sFAIL%s] Could not create Kea context. Aborting tests.\n", KRED, KNRM);
        tests_failed++;
        return;
    }

    RUN_TEST(test_list_commands_success);
    RUN_TEST(test_list_commands_fail_bad_service);
    RUN_TEST(test_version_get_success);
    RUN_TEST(test_status_get_success);

    kea_ctrl_destroy(g_ctx);
    g_ctx = NULL;
}