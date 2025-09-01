#include "keactrl_internal.h"

// See keactrl.h for documentation.
cJSON *kea_cmd_cache_clear (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "cache-clear", services, NULL);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_cache_size (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "cache-size", services, NULL);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_cache_get (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "cache-get", services, NULL);
}