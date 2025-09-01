#include "keactrl_internal.h"

// See keactrl.h for documentation.
cJSON *kea_cmd_class_add (kea_ctrl_context_t ctx, const char *service, const cJSON *class_data)
{
    if (!ctx || !service || !class_data) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "class-add", services, cJSON_Duplicate (class_data, true));
}

// See keactrl.h for documentation.
cJSON *kea_cmd_class_del (kea_ctrl_context_t ctx, const char *service, const char *class_name)
{
    if (!ctx || !service || !class_name) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddStringToObject (args, "name", class_name);
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "class-del", services, args);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_class_list (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "class-list", services, NULL);
}