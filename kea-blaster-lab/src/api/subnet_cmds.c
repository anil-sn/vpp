#include "keactrl_internal.h"

// --- DHCPv4 ---

cJSON *kea_cmd_subnet4_list (kea_ctrl_context_t ctx)
{
    if (!ctx) {
        return NULL;
    }
    const char *services[] = {"dhcp4", NULL};
    return execute_transaction_internal (ctx, "subnet4-list", services, NULL);
}

cJSON *kea_cmd_subnet4_get (kea_ctrl_context_t ctx, int subnet_id)
{
    if (!ctx) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddNumberToObject (args, "id", subnet_id);
    const char *services[] = {"dhcp4", NULL};
    return execute_transaction_internal (ctx, "subnet4-get", services, args);
}

cJSON *kea_cmd_subnet4_add (kea_ctrl_context_t ctx, const cJSON *subnet_data)
{
    if (!ctx || !subnet_data) {
        return NULL;
    }
    const char *services[] = {"dhcp4", NULL};
    return execute_transaction_internal (ctx, "subnet4-add", services, cJSON_Duplicate (subnet_data, true));
}

cJSON *kea_cmd_subnet4_del (kea_ctrl_context_t ctx, int subnet_id)
{
    if (!ctx) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddNumberToObject (args, "id", subnet_id);
    const char *services[] = {"dhcp4", NULL};
    return execute_transaction_internal (ctx, "subnet4-del", services, args);
}

cJSON *kea_cmd_subnet4_update (kea_ctrl_context_t ctx, const cJSON *subnet_data)
{
    if (!ctx || !subnet_data) {
        return NULL;
    }
    const char *services[] = {"dhcp4", NULL};
    return execute_transaction_internal (ctx, "subnet4-update", services, cJSON_Duplicate (subnet_data, true));
}

// --- DHCPv6 ---

cJSON *kea_cmd_subnet6_list (kea_ctrl_context_t ctx)
{
    if (!ctx) {
        return NULL;
    }
    const char *services[] = {"dhcp6", NULL};
    return execute_transaction_internal (ctx, "subnet6-list", services, NULL);
}

cJSON *kea_cmd_subnet6_get (kea_ctrl_context_t ctx, int subnet_id)
{
    if (!ctx) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddNumberToObject (args, "id", subnet_id);
    const char *services[] = {"dhcp6", NULL};
    return execute_transaction_internal (ctx, "subnet6-get", services, args);
}

cJSON *kea_cmd_subnet6_add (kea_ctrl_context_t ctx, const cJSON *subnet_data)
{
    if (!ctx || !subnet_data) {
        return NULL;
    }
    const char *services[] = {"dhcp6", NULL};
    return execute_transaction_internal (ctx, "subnet6-add", services, cJSON_Duplicate (subnet_data, true));
}

cJSON *kea_cmd_subnet6_del (kea_ctrl_context_t ctx, int subnet_id)
{
    if (!ctx) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddNumberToObject (args, "id", subnet_id);
    const char *services[] = {"dhcp6", NULL};
    return execute_transaction_internal (ctx, "subnet6-del", services, args);
}

cJSON *kea_cmd_subnet6_update (kea_ctrl_context_t ctx, const cJSON *subnet_data)
{
    if (!ctx || !subnet_data) {
        return NULL;
    }
    const char *services[] = {"dhcp6", NULL};
    return execute_transaction_internal (ctx, "subnet6-update", services, cJSON_Duplicate (subnet_data, true));
}