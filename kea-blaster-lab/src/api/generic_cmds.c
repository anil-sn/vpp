#include "keactrl_internal.h"

// See keactrl.h for documentation.
cJSON *kea_cmd_list_commands (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "list-commands", services, NULL);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_version_get (kea_ctrl_context_t ctx, const char **services)
{
    if (!ctx) {
        return NULL;
    }
    return execute_transaction_internal (ctx, "version-get", services, NULL);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_status_get (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "status-get", services, NULL);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_shutdown (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "shutdown", services, NULL);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_build_report (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "build-report", services, NULL);
}