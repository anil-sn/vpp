#include "keactrl_internal.h"

// See keactrl.h for documentation.
cJSON *kea_cmd_reservation_add (kea_ctrl_context_t ctx, const char *service, const cJSON *host_data)
{
    if (!ctx || !service || !host_data) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddItemToObject (args, "reservation", cJSON_Duplicate (host_data, true));
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "reservation-add", services, args);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_reservation_del_by_ip (kea_ctrl_context_t ctx, const char *service, int subnet_id, const char *ip_address)
{
    if (!ctx || !service || !ip_address) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddNumberToObject (args, "subnet-id", subnet_id);
    cJSON_AddStringToObject (args, "identifier-type", "ip-address");
    cJSON_AddStringToObject (args, "identifier", ip_address);
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "reservation-del", services, args);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_reservation_get_by_ip (kea_ctrl_context_t ctx, const char *service, const char *ip_address)
{
    if (!ctx || !service || !ip_address) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddStringToObject (args, "ip-address", ip_address);
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "reservation-get-by-address", services, args);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_reservation_get_all (kea_ctrl_context_t ctx, const char *service, int subnet_id)
{
    if (!ctx || !service) {
        return NULL;
    }
    cJSON *args = cJSON_CreateObject();
    cJSON_AddNumberToObject (args, "subnet-id", subnet_id);
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "reservation-get-all", services, args);
}