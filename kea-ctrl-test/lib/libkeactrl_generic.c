#include "libkeactrl_internal.h"
#include <stdio.h>

/* ========================================================================== */
/*                           1. Generic Commands                              */
/* ========================================================================== */

cJSON* kea_cmd_list_commands(kea_ctrl_context_t ctx, const char* service) {
    if (!ctx || !service) {
        if (ctx) snprintf(ctx->last_error, 256, "Context or service cannot be NULL.");
        return NULL;
    }
    return execute_transaction_internal(ctx, "list-commands", service, NULL);
}

cJSON* kea_cmd_version_get(kea_ctrl_context_t ctx, const char** services) {
    if (!ctx) {
        return NULL; // Cannot set last_error if ctx is NULL
    }

    cJSON* args = NULL;
    if (services && services[0] != NULL) {
        cJSON* service_array = cJSON_CreateArray();
        if (!service_array) {
            snprintf(ctx->last_error, 256, "Failed to create service array for version-get.");
            return NULL;
        }
        for (int i = 0; services[i] != NULL; ++i) {
            cJSON_AddItemToArray(service_array, cJSON_CreateString(services[i]));
        }
        args = cJSON_CreateObject();
        if (!args) {
            cJSON_Delete(service_array);
            snprintf(ctx->last_error, 256, "Failed to create args object for version-get.");
            return NULL;
        }
        cJSON_AddItemToObject(args, "service", service_array);
    }

    return execute_transaction_internal(ctx, "version-get", NULL, args);
}

cJSON* kea_cmd_status_get(kea_ctrl_context_t ctx, const char* service) {
    if (!ctx || !service) {
        if (ctx) snprintf(ctx->last_error, 256, "Context or service cannot be NULL.");
        return NULL;
    }
    return execute_transaction_internal(ctx, "status-get", service, NULL);
}

cJSON* kea_cmd_shutdown(kea_ctrl_context_t ctx, const char* service) {
    if (!ctx || !service) {
        if (ctx) snprintf(ctx->last_error, 256, "Context or service cannot be NULL.");
        return NULL;
    }
    return execute_transaction_internal(ctx, "shutdown", service, NULL);
}