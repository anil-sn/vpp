#include "config_helper.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

bool apply_kea_config_from_string (kea_ctrl_context_t ctx, const char *service, const char *config_json_string)
{
    cJSON *config_json = cJSON_Parse (config_json_string);
    if (!config_json) {
        fprintf (stderr, "\n      [HELPER-ERROR] Failed to parse config JSON string.\n");
        return false;
    }
    bool result = apply_kea_config_from_json (ctx, service, config_json);
    cJSON_Delete (config_json);
    return result;
}

bool apply_kea_config_from_json (kea_ctrl_context_t ctx, const char *service, const cJSON *config_json)
{
    cJSON *set_result = kea_cmd_config_set (ctx, service, config_json);
    if (set_result) {
        cJSON *result_obj = cJSON_GetArrayItem (set_result, 0);
        cJSON *result_code = cJSON_GetObjectItem (result_obj, "result");
        if (cJSON_IsNumber (result_code) && result_code->valueint == 0) {
            cJSON_Delete (set_result);
            return true;
        }
    }
    fprintf (stderr, "\n      [HELPER-ERROR] apply_kea_config_from_json failed: %s\n", kea_ctrl_get_last_error (ctx));
    cJSON_Delete (set_result);
    return false;
}