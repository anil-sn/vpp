#include <ctype.h>
#include <string.h>
#include "keactrl_internal.h"

// See keactrl.h for documentation.
cJSON *kea_cmd_config_get (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "config-get", services, NULL);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_config_set (kea_ctrl_context_t ctx, const char *service, const cJSON *config_json)
{
    if (!ctx || !service || !config_json) {
        return NULL;
    }
    const char *services[] = {service, NULL};

    // The 'config-set' command requires the config to be nested under a key
    // that matches the service name, e.g., {"Dhcp4": {...}}.
    cJSON *args = cJSON_CreateObject();
    char service_key[64];
    strncpy (service_key, service, sizeof (service_key) - 1);
    service_key[sizeof (service_key) - 1] = '\0';

    if (strlen (service_key) > 0) {
        service_key[0] = toupper (service_key[0]);
    }

    cJSON_AddItemToObject (args, service_key, cJSON_Duplicate (config_json, true));
    return execute_transaction_internal (ctx, "config-set", services, args);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_config_reload (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "config-reload", services, NULL);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_config_test (kea_ctrl_context_t ctx, const char *service, const cJSON *config_json)
{
    if (!ctx || !service || !config_json) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    // Replicates the same argument structure as config-set
    cJSON *args = cJSON_CreateObject();
    char service_key[64];
    strncpy (service_key, service, sizeof (service_key) - 1);
    service_key[sizeof (service_key) - 1] = '\0';
    if (strlen (service_key) > 0) {
        service_key[0] = toupper (service_key[0]);
    }
    cJSON_AddItemToObject (args, service_key, cJSON_Duplicate (config_json, true));
    return execute_transaction_internal (ctx, "config-test", services, args);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_config_write (kea_ctrl_context_t ctx, const char *service, const char *filename)
{
    if (!ctx || !service || !filename) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    cJSON *args = cJSON_CreateObject();
    cJSON_AddStringToObject (args, "filename", filename);
    return execute_transaction_internal (ctx, "config-write", services, args);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_config_backend_pull (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "config-backend-pull", services, NULL);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_config_hash_get (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "config-hash-get", services, NULL);
}

// See keactrl.h for documentation.
cJSON *kea_cmd_server_tag_get (kea_ctrl_context_t ctx, const char *service)
{
    if (!ctx || !service) {
        return NULL;
    }
    const char *services[] = {service, NULL};
    return execute_transaction_internal (ctx, "server-tag-get", services, NULL);
}