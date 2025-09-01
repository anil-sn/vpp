#include "keactrl_internal.h"

// See keactrl.h for documentation.
cJSON *kea_cmd_statistic_get (kea_ctrl_context_t ctx, const char *service, const char *name)
{
    if (!ctx || !service || !name) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddStringToObject (args, "name", name);
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "statistic-get", services, args);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_statistic_get_all (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "statistic-get-all", services, NULL);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_statistic_reset (kea_ctrl_context_t ctx, const char *service, const char *name)
{
    if (!ctx || !service || !name) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddStringToObject (args, "name", name);
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "statistic-reset", services, args);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_statistic_reset_all (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "statistic-reset-all", services, NULL);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_statistic_remove (kea_ctrl_context_t ctx, const char *service, const char *name)
{
    if (!ctx || !service || !name) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddStringToObject (args, "name", name);
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "statistic-remove", services, args);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_statistic_remove_all (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "statistic-remove-all", services, NULL);
}