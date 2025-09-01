#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "cJSON.h"

// Internal headers for data structures and helper function prototypes
#include "kea_config_builder.h"

// --- Implementation of Internal Helper Functions ---

cJSON_bool add_item_checked (cJSON *parent, const char *key, cJSON *item_to_add, const char *caller_func_name)
{
    if (!parent) {
        printf ("Error: NULL parent passed to add_item_checked in %s.\n", caller_func_name);
        cJSON_Delete (item_to_add); // Clean up the orphaned item
        return cJSON_False;
    }

    if (!item_to_add) {
        if (key && key[0] != '\0') {
            printf ("Error: NULL item for key '%s' passed to add_item_checked (creation failed?) in %s.\n", key, caller_func_name);
        } else {
            printf ("Error: NULL item for array element passed to add_item_checked (creation failed?) in %s.\n", caller_func_name);
        }
        return cJSON_False;
    }

    cJSON_bool add_success = cJSON_False;
    if (cJSON_IsArray (parent)) {
        add_success = cJSON_AddItemToArray (parent, item_to_add);
    } else if (cJSON_IsObject (parent) && key) {
        add_success = cJSON_AddItemToObject (parent, key, item_to_add);
    }

    if (!add_success) {
        if (key) {
            printf ("Error: Failed to add item with key '%s' in %s.\n", key, caller_func_name);
        } else {
            printf ("Error: Failed to add item to array in %s.\n", caller_func_name);
        }
        cJSON_Delete (item_to_add); // Clean up on failure
        return cJSON_False;
    }
    return cJSON_True;
}

cJSON *create_object_item (void) { return cJSON_CreateObject(); }
cJSON *create_array_item (void) { return cJSON_CreateArray(); }
cJSON *create_string_item (const char *value) { return value ? cJSON_CreateString (value) : cJSON_CreateNull(); }
cJSON *create_number_item (double value) { return cJSON_CreateNumber (value); }
cJSON *create_boolean_item (cJSON_bool value) { return cJSON_CreateBool (value); }
cJSON *create_null_item() { return cJSON_CreateNull(); }


cJSON *build_kea_option_data_array (const KeaOptionData *options, size_t num_options, cJSON_bool is_v4)
{
    if (!options || num_options == 0) {
        return NULL;
    }
    cJSON *options_array = create_array_item();
    if (!options_array) {
        return NULL;
    }

    for (size_t i = 0; i < num_options; ++i) {
        cJSON *option_item = is_v4 ? build_kea_option_v4 (&options[i]) : build_kea_option_v6 (&options[i]);
        if (!option_item) {
            goto ERROR_CLEANUP;
        }
        CHECK_AND_ADD_ITEM (options_array, NULL, option_item, ERROR_CLEANUP);
    }
    return options_array;

ERROR_CLEANUP:
    cJSON_Delete (options_array);
    return NULL;
}

cJSON *build_kea_option_v4 (const KeaOptionData *option_data)
{
    if (!option_data) {
        return NULL;
    }
    cJSON *option_item = create_object_item();
    if (!option_item) {
        return NULL;
    }

    if (option_data->name[0] != '\0') {
        CHECK_AND_ADD_ITEM (option_item, "name", create_string_item (option_data->name), ERROR_CLEANUP);
    } else if (option_data->code > 0) {
        CHECK_AND_ADD_ITEM (option_item, "code", create_number_item (option_data->code), ERROR_CLEANUP);
    } else {
        goto ERROR_CLEANUP;
    }
    CHECK_AND_ADD_ITEM (option_item, "data", create_string_item (option_data->data), ERROR_CLEANUP);
    return option_item;

ERROR_CLEANUP:
    cJSON_Delete (option_item);
    return NULL;
}

cJSON *build_kea_option_v6 (const KeaOptionData *option_data)
{
    // For now, v6 and v4 option structures are identical in JSON
    return build_kea_option_v4 (option_data);
}

cJSON *build_kea_pool_v4 (const KeaDhcp4Pool *pool_data)
{
    if (!pool_data) {
        return NULL;
    }
    cJSON *pool_item = create_object_item();
    if (!pool_item) {
        return NULL;
    }

    CHECK_AND_ADD_ITEM (pool_item, "pool", create_string_item (pool_data->pool_range), ERROR_CLEANUP);
    if (pool_data->client_class && pool_data->client_class[0] != '\0') {
        CHECK_AND_ADD_ITEM (pool_item, "client-class", create_string_item (pool_data->client_class), ERROR_CLEANUP);
    }
    return pool_item;

ERROR_CLEANUP:
    cJSON_Delete (pool_item);
    return NULL;
}

cJSON *build_kea_dhcp4_pools_array (const KeaDhcp4Pool *pools, size_t num_pools)
{
    if (!pools || num_pools == 0) {
        return NULL;
    }
    cJSON *pools_array = create_array_item();
    if (!pools_array) {
        return NULL;
    }
    for (size_t i = 0; i < num_pools; ++i) {
        cJSON *pool_item = build_kea_pool_v4 (&pools[i]);
        if (!pool_item) {
            goto ERROR_CLEANUP;
        }
        CHECK_AND_ADD_ITEM (pools_array, NULL, pool_item, ERROR_CLEANUP);
    }
    return pools_array;
ERROR_CLEANUP:
    cJSON_Delete (pools_array);
    return NULL;
}

cJSON *build_kea_reservation_v4 (const KeaDhcp4Reservation *res_data)
{
    if (!res_data) {
        return NULL;
    }
    cJSON *res_item = create_object_item();
    if (!res_item) {
        return NULL;
    }

    if (res_data->hw_address && res_data->hw_address[0] != '\0') {
        CHECK_AND_ADD_ITEM (res_item, "hw-address", create_string_item (res_data->hw_address), ERROR_CLEANUP);
    }
    if (res_data->client_id && res_data->client_id[0] != '\0') {
        CHECK_AND_ADD_ITEM (res_item, "client-id", create_string_item (res_data->client_id), ERROR_CLEANUP);
    }
    if (res_data->ip_address && res_data->ip_address[0] != '\0') {
        CHECK_AND_ADD_ITEM (res_item, "ip-address", create_string_item (res_data->ip_address), ERROR_CLEANUP);
    }
    if (res_data->hostname && res_data->hostname[0] != '\0') {
        CHECK_AND_ADD_ITEM (res_item, "hostname", create_string_item (res_data->hostname), ERROR_CLEANUP);
    }
    if (res_data->client_class && res_data->client_class[0] != '\0') {
        CHECK_AND_ADD_ITEM (res_item, "client-class", create_string_item (res_data->client_class), ERROR_CLEANUP);
    }

    cJSON *options = build_kea_option_data_array (res_data->option_data, res_data->num_option_data, cJSON_True);
    if (options) {
        CHECK_AND_ADD_ITEM (res_item, "option-data", options, ERROR_CLEANUP);
    }

    return res_item;
ERROR_CLEANUP:
    cJSON_Delete (res_item);
    return NULL;
}

cJSON *build_kea_dhcp4_reservations_array (const KeaDhcp4Reservation *reservations, size_t num_reservations)
{
    if (!reservations || num_reservations == 0) {
        return NULL;
    }
    cJSON *array = create_array_item();
    if (!array) {
        return NULL;
    }
    for (size_t i = 0; i < num_reservations; ++i) {
        cJSON *item = build_kea_reservation_v4 (&reservations[i]);
        if (!item) {
            goto ERROR_CLEANUP;
        }
        CHECK_AND_ADD_ITEM (array, NULL, item, ERROR_CLEANUP);
    }
    return array;
ERROR_CLEANUP:
    cJSON_Delete (array);
    return NULL;
}

cJSON *build_kea_dhcp4_subnet_array (const KeaDhcp4Subnet *subnets, size_t num_subnets)
{
    if (!subnets || num_subnets == 0) {
        return NULL;
    }
    cJSON *array = create_array_item();
    if (!array) {
        return NULL;
    }

    for (size_t i = 0; i < num_subnets; ++i) {
        cJSON *subnet = create_object_item();
        if (!subnet) {
            goto ERROR_CLEANUP;
        }

        CHECK_AND_ADD_ITEM (subnet, "id", create_number_item (subnets[i].subnet_id), ERROR_CLEANUP);
        CHECK_AND_ADD_ITEM (subnet, "subnet", create_string_item (subnets[i].subnet_cidr), ERROR_CLEANUP);
        if (subnets[i].valid_lifetime > 0) {
            CHECK_AND_ADD_ITEM (subnet, "valid-lifetime", create_number_item (subnets[i].valid_lifetime), ERROR_CLEANUP);
        }
        if (subnets[i].renew_timer > 0) {
            CHECK_AND_ADD_ITEM (subnet, "renew-timer", create_number_item (subnets[i].renew_timer), ERROR_CLEANUP);
        }
        if (subnets[i].rebind_timer > 0) {
            CHECK_AND_ADD_ITEM (subnet, "rebind-timer", create_number_item (subnets[i].rebind_timer), ERROR_CLEANUP);
        }

        cJSON *pools = build_kea_dhcp4_pools_array (subnets[i].pool, subnets[i].num_pools);
        if (pools) {
            CHECK_AND_ADD_ITEM (subnet, "pools", pools, ERROR_CLEANUP);
        }

        cJSON *options = build_kea_option_data_array (subnets[i].option_data, subnets[i].num_option_data, cJSON_True);
        if (options) {
            CHECK_AND_ADD_ITEM (subnet, "option-data", options, ERROR_CLEANUP);
        }

        cJSON *reservations = build_kea_dhcp4_reservations_array (subnets[i].reservations, subnets[i].num_reservations);
        if (reservations) {
            CHECK_AND_ADD_ITEM (subnet, "reservations", reservations, ERROR_CLEANUP);
        }

        CHECK_AND_ADD_ITEM (array, NULL, subnet, ERROR_CLEANUP);
        continue; // To avoid double-freeing subnet on error
ERROR_CLEANUP: // Per-iteration error
        cJSON_Delete (subnet);
        goto GLOBAL_ERROR;
    }
    return array;
GLOBAL_ERROR: // Full function error
    cJSON_Delete (array);
    return NULL;
}

cJSON *build_kea_dhcp4_shared_networks (const Keadhcp4SharedNetworks *shared_networks, size_t num_subnets)
{
    if (!shared_networks || num_subnets == 0) {
        return NULL;
    }
    cJSON *array = create_array_item();
    if (!array) {
        return NULL;
    }
    cJSON *network = create_object_item();
    if (!network) {
        goto ERROR_CLEANUP;
    }

    CHECK_AND_ADD_ITEM (network, "name", create_string_item (shared_networks->name), ERROR_CLEANUP);
    CHECK_AND_ADD_ITEM (network, "interface", create_string_item (shared_networks->interface), ERROR_CLEANUP);

    cJSON *subnets = build_kea_dhcp4_subnet_array (shared_networks->v4subnets, num_subnets);
    if (!subnets) {
        goto ERROR_CLEANUP;
    }
    CHECK_AND_ADD_ITEM (network, "subnet4", subnets, ERROR_CLEANUP);

    CHECK_AND_ADD_ITEM (array, NULL, network, ERROR_CLEANUP);
    return array;
ERROR_CLEANUP:
    cJSON_Delete (network);
    cJSON_Delete (array);
    return NULL;
}

// --- Top-level builder functions ---

cJSON *build_dhcp4_config (const KeaConfigData *config)
{
    if (!config) {
        return NULL;
    }

    cJSON *dhcp4 = create_object_item();
    if (!dhcp4) {
        return NULL;
    }

    if (config->authoritative) {
        CHECK_AND_ADD_ITEM (dhcp4, "authoritative", create_boolean_item (config->authoritative), ERROR_CLEANUP);
    }
    if (config->v4_global_valid_lifetime > 0) {
        CHECK_AND_ADD_ITEM (dhcp4, "valid-lifetime", create_number_item (config->v4_global_valid_lifetime), ERROR_CLEANUP);
    }

    // Interfaces
    cJSON *ifaces = create_object_item();
    if (ifaces) {
        cJSON *iface_array = cJSON_CreateStringArray (config->interfaces, config->num_interfaces);
        if (iface_array) {
            cJSON_AddItemToObject (ifaces, "interfaces", iface_array);
            cJSON_AddItemToObject (dhcp4, "interfaces-config", ifaces);
        } else {
            cJSON_Delete (ifaces);
        }
    }

    // Lease DB
    cJSON *lease_db = create_object_item();
    if (lease_db) {
        CHECK_AND_ADD_ITEM (lease_db, "type", create_string_item (config->lease_db_type), ERROR_CLEANUP);
        CHECK_AND_ADD_ITEM (lease_db, "name", create_string_item (config->lease_db_name), ERROR_CLEANUP);
        CHECK_AND_ADD_ITEM (lease_db, "persist", create_boolean_item (config->lease_db_persist), ERROR_CLEANUP);
        CHECK_AND_ADD_ITEM (dhcp4, "lease-database", lease_db, ERROR_CLEANUP);
    } else {
        goto ERROR_CLEANUP;
    }

    // Shared Networks or Subnets
    if (config->shared_networks.name[0] != '\0') {
        cJSON *shared = build_kea_dhcp4_shared_networks (&config->shared_networks, config->num_v4_subnets);
        if (shared) {
            CHECK_AND_ADD_ITEM (dhcp4, "shared-networks", shared, ERROR_CLEANUP);
        }
    } else {
        cJSON *subnets = build_kea_dhcp4_subnet_array (config->v4_subnets, config->num_v4_subnets);
        if (subnets) {
            CHECK_AND_ADD_ITEM (dhcp4, "subnet4", subnets, ERROR_CLEANUP);
        }
    }

    return dhcp4;
ERROR_CLEANUP:
    cJSON_Delete (dhcp4);
    return NULL;
}

// NOTE: The DHCPv6 builder implementation is extensive and follows the same patterns.
// It is omitted here but would be implemented similarly, building pools, reservations,
// and subnets for IPv6.
cJSON *build_dhcp6_config (const KeaConfigData *config)
{
    if (!config) {
        return NULL;
    }
    // For now, return an empty object to satisfy the prototype.
    return cJSON_CreateObject();
}