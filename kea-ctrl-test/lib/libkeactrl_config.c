#include "libkeactrl_internal.h"
#include <stdio.h>
#include <string.h>

/* ========================================================================== */
/*                         2. Configuration Commands                          */
/* ========================================================================== */

cJSON* kea_cmd_config_get(kea_ctrl_context_t ctx, const char* service) {
    if (!ctx || !service) {
        if (ctx) snprintf(ctx->last_error, 256, "Context or service cannot be NULL.");
        return NULL;
    }
    return execute_transaction_internal(ctx, "config-get", service, NULL);
}

cJSON* kea_cmd_config_set(kea_ctrl_context_t ctx, const char* service, const cJSON* config_json) {
    if (!ctx || !service || !config_json) {
        if (ctx) snprintf(ctx->last_error, 256, "Invalid argument for config-set.");
        return NULL;
    }

    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, 256, "Failed to create args object for config-set.");
        return NULL;
    }

    char service_key[32];
    snprintf(service_key, sizeof(service_key), "%s", service);
    if (strlen(service) > 0) {
        service_key[0] = toupper(service_key[0]);
    }
    
    cJSON_AddItemToObject(args, service_key, cJSON_Duplicate(config_json, 1));

    return execute_transaction_internal(ctx, "config-set", service, args);
}

cJSON* kea_cmd_config_reload(kea_ctrl_context_t ctx, const char* service) {
    if (!ctx || !service) {
        if (ctx) snprintf(ctx->last_error, 256, "Context or service cannot be NULL.");
        return NULL;
    }
    return execute_transaction_internal(ctx, "config-reload", service, NULL);
}

cJSON* kea_cmd_config_test(kea_ctrl_context_t ctx, const char* service, const cJSON* config_json) {
    if (!ctx || !service || !config_json) {
        if (ctx) snprintf(ctx->last_error, 256, "Invalid argument for config-test.");
        return NULL;
    }
    
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, 256, "Failed to create args object for config-test.");
        return NULL;
    }
    
    char service_key[32];
    snprintf(service_key, sizeof(service_key), "%s", service);
    if (strlen(service) > 0) {
        service_key[0] = toupper(service_key[0]);
    }

    cJSON_AddItemToObject(args, service_key, cJSON_Duplicate(config_json, 1));

    return execute_transaction_internal(ctx, "config-test", service, args);
}

cJSON* kea_cmd_config_write(kea_ctrl_context_t ctx, const char* service, const char* filename) {
    if (!ctx || !service || !filename) {
        if (ctx) snprintf(ctx->last_error, 256, "Invalid argument for config-write.");
        return NULL;
    }

    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, 256, "Failed to create args object for config-write.");
        return NULL;
    }
    cJSON_AddStringToObject(args, "filename", filename);

    return execute_transaction_internal(ctx, "config-write", service, args);
}