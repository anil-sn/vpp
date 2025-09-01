#include "keactrl_internal.h"

// --- DHCPv4 Lease Commands ---

cJSON *kea_cmd_lease4_add (kea_ctrl_context_t ctx, const cJSON *lease_data)
{
    if (!ctx || !lease_data) {
        return NULL;
    }
    const char *services[] = {"dhcp4", NULL};
    return execute_transaction_internal (ctx, "lease4-add", services, cJSON_Duplicate (lease_data, true));
}

cJSON *kea_cmd_lease4_del (kea_ctrl_context_t ctx, const char *ip_address)
{
    if (!ctx || !ip_address) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddStringToObject (args, "ip-address", ip_address);
    const char *services[] = {"dhcp4", NULL};
    return execute_transaction_internal (ctx, "lease4-del", services, args);
}

cJSON *kea_cmd_lease4_get_by_ip (kea_ctrl_context_t ctx, const char *ip_address)
{
    if (!ctx || !ip_address) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddStringToObject (args, "ip-address", ip_address);
    const char *services[] = {"dhcp4", NULL};
    return execute_transaction_internal (ctx, "lease4-get", services, args);
}

cJSON *kea_cmd_lease4_get_by_hw_address (kea_ctrl_context_t ctx, const char *hw_address)
{
    if (!ctx || !hw_address) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddStringToObject (args, "hw-address", hw_address);
    const char *services[] = {"dhcp4", NULL};
    return execute_transaction_internal (ctx, "lease4-get-by-hw-address", services, args);
}

cJSON *kea_cmd_lease4_get_by_client_id (kea_ctrl_context_t ctx, const char *client_id)
{
    if (!ctx || !client_id) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddStringToObject (args, "client-id", client_id);
    const char *services[] = {"dhcp4", NULL};
    return execute_transaction_internal (ctx, "lease4-get-by-client-id", services, args);
}

cJSON *kea_cmd_lease4_get_all (kea_ctrl_context_t ctx, int subnet_id)
{
    if (!ctx) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddItemToObject (args, "subnets", cJSON_CreateIntArray (&subnet_id, 1));
    const char *services[] = {"dhcp4", NULL};
    return execute_transaction_internal (ctx, "lease4-get-all", services, args);
}

cJSON *kea_cmd_lease4_wipe (kea_ctrl_context_t ctx, int subnet_id)
{
    if (!ctx) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddNumberToObject (args, "subnet-id", subnet_id);
    const char *services[] = {"dhcp4", NULL};
    return execute_transaction_internal (ctx, "lease4-wipe", services, args);
}

// --- DHCPv6 Lease Commands ---

cJSON *kea_cmd_lease6_add (kea_ctrl_context_t ctx, const cJSON *lease_data)
{
    if (!ctx || !lease_data) {
        return NULL;
    }
    const char *services[] = {"dhcp6", NULL};
    return execute_transaction_internal (ctx, "lease6-add", services, cJSON_Duplicate (lease_data, true));
}

cJSON *kea_cmd_lease6_del (kea_ctrl_context_t ctx, const char *ip_address)
{
    if (!ctx || !ip_address) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddStringToObject (args, "ip-address", ip_address);
    const char *services[] = {"dhcp6", NULL};
    return execute_transaction_internal (ctx, "lease6-del", services, args);
}

cJSON *kea_cmd_lease6_get_by_ip (kea_ctrl_context_t ctx, const char *ip_address)
{
    if (!ctx || !ip_address) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddStringToObject (args, "ip-address", ip_address);
    const char *services[] = {"dhcp6", NULL};
    return execute_transaction_internal (ctx, "lease6-get", services, args);
}

cJSON *kea_cmd_lease6_get_by_duid (kea_ctrl_context_t ctx, const char *duid, int iaid)
{
    if (!ctx || !duid) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddStringToObject (args, "duid", duid);
    cJSON_AddNumberToObject (args, "iaid", iaid);
    const char *services[] = {"dhcp6", NULL};
    return execute_transaction_internal (ctx, "lease6-get-by-duid", services, args);
}

cJSON *kea_cmd_lease6_get_all (kea_ctrl_context_t ctx, int subnet_id)
{
    if (!ctx) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddItemToObject (args, "subnets", cJSON_CreateIntArray (&subnet_id, 1));
    const char *services[] = {"dhcp6", NULL};
    return execute_transaction_internal (ctx, "lease6-get-all", services, args);
}

cJSON *kea_cmd_lease6_wipe (kea_ctrl_context_t ctx, int subnet_id)
{
    if (!ctx) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddNumberToObject (args, "subnet-id", subnet_id);
    const char *services[] = {"dhcp6", NULL};
    return execute_transaction_internal (ctx, "lease6-wipe", services, args);
}