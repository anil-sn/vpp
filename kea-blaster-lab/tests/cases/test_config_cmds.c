#include "test_main.h"
#include "helpers/config_helper.h"

static kea_ctrl_context_t g_ctx = NULL;

static bool setup_config_tests (void)
{
    g_ctx = kea_ctrl_create (NULL);
    return (g_ctx != NULL);
}

static void teardown_config_tests (void)
{
    if (g_ctx) {
        cJSON *reload_response = kea_cmd_config_reload (g_ctx, "dhcp4");
        if (!reload_response) {
            printf ("\n[WARN] Failed to send config-reload command during teardown.\n");
        }
        cJSON_Delete (reload_response);
        sleep (2);
        kea_ctrl_destroy (g_ctx);
        g_ctx = NULL;
    }
}

TEST_CASE (test_config_get_set_and_restore)
{
    cJSON *original_config_response = NULL;
    cJSON *original_config = NULL;
    cJSON *modified_config = NULL;
    cJSON *verify_config_response = NULL;

    original_config_response = kea_cmd_config_get (g_ctx, "dhcp4");
    ASSERT_KEA_API_OK (original_config_response, g_ctx);
    original_config = cJSON_GetObjectItem (cJSON_GetObjectItem (cJSON_GetArrayItem (original_config_response, 0), "arguments"), "Dhcp4");
    ASSERT_NOT_NULL (original_config, "Could not extract original Dhcp4 config.");

    modified_config = cJSON_Duplicate (original_config, true);
    ASSERT_NOT_NULL (modified_config, "Failed to duplicate original config JSON.");

    cJSON *lifetime_item = cJSON_GetObjectItem (modified_config, "valid-lifetime");
    cJSON_SetNumberValue (lifetime_item, 5555);
    printf ("\n       -> Setting valid-lifetime to 5555... ");

    ASSERT_TRUE (apply_kea_config_from_json (g_ctx, "dhcp4", modified_config), "Failed to apply modified config.");
    sleep (2);
    printf ("Set.");

    verify_config_response = kea_cmd_config_get (g_ctx, "dhcp4");
    ASSERT_KEA_API_OK (verify_config_response, g_ctx);

    cJSON *verify_config = cJSON_GetObjectItem (cJSON_GetObjectItem (cJSON_GetArrayItem (verify_config_response, 0), "arguments"), "Dhcp4");
    cJSON *new_lifetime_item = cJSON_GetObjectItem (verify_config, "valid-lifetime");
    ASSERT_INT_EQ (new_lifetime_item->valueint, 5555);
    printf (" Verified.");

cleanup:
    cJSON_Delete (original_config_response);
    cJSON_Delete (modified_config);
    cJSON_Delete (verify_config_response);
}

void run_config_commands_tests (void)
{
    printf ("--- Starting Configuration Commands Tests (REST API) ---\n");
    if (!setup_config_tests()) {
        printf ("  [%sFAIL%s] Suite setup failed.\n", KRED, KNRM);
        tests_failed++; tests_run++;
        teardown_config_tests();
        return;
    }
    RUN_TEST (test_config_get_set_and_restore);
    teardown_config_tests();
}