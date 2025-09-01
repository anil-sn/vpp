#ifndef KEA_CONFIG_BUILDER_INTERNAL_H
#define KEA_CONFIG_BUILDER_INTERNAL_H

#include "keactrl.h" // Includes public data structures and cJSON

// ==========================================================================
//                 Internal Macros and Helper Prototypes
// ==========================================================================

// --- Helper Macro for robust item creation & addition ---
// Use this like: CHECK_AND_ADD_ITEM(parent, key, item_creator_call, error_label)
#define CHECK_AND_ADD_ITEM(parent, key, item_creator_call, error_label) \
    do { \
        cJSON* _item_to_add = (item_creator_call); \
        if (!add_item_checked((parent), (key), _item_to_add, __func__)) { \
            /* add_item_checked printed the error and deleted _item_to_add if needed */ \
            goto error_label; \
        } \
    } while(0)

// --- Core Checked Add Function ---
cJSON_bool add_item_checked (cJSON *parent, const char *key, cJSON *item_to_add, const char *caller_func_name);

// --- Basic cJSON Item Creation Helpers ---
cJSON *create_object_item (void);
cJSON *create_array_item (void);
cJSON *create_string_item (const char *value);
cJSON *create_number_item (double value);
cJSON *create_boolean_item (cJSON_bool value);
cJSON *create_null_item (void);

// --- Individual Item Builders ---
cJSON *build_kea_option_v4 (const KeaOptionData *option_data);
cJSON *build_kea_option_v6 (const KeaOptionData *option_data);
cJSON *build_kea_pool_v4 (const KeaDhcp4Pool *pool_data);
cJSON *build_kea_pool_v6_addr (const KeaDhcp6Pool *pool_data);
cJSON *build_kea_pool_v6_prefix (const KeaDhcp6Pool *pool_data);
cJSON *build_kea_reservation_v4 (const KeaDhcp4Reservation *res_data);
cJSON *build_kea_v6_prefix_reservation_item (const char *prefix, int preferred_lifetime, int valid_lifetime);
cJSON *build_kea_reservation_v6 (const KeaDhcp6Reservation *res_data);
cJSON *build_logger_output_item (const KeaLoggerOutputConfig *output_data);

// --- Array Builders (These call the individual item builders) ---
cJSON *build_kea_option_data_array (const KeaOptionData *options, size_t num_options, cJSON_bool is_v4);
cJSON *build_kea_logger_output_array (const KeaLoggerOutputConfig *outputs, size_t num_outputs);
cJSON *build_kea_logger_array (const KeaLoggerConfig *loggers, size_t num_loggers);
cJSON *build_kea_logger_array_v4_only (const KeaLoggerConfig *loggers, size_t num_loggers);
cJSON *build_kea_logger_array_v6_only (const KeaLoggerConfig *loggers, size_t num_loggers);
cJSON *build_kea_ddns_tsig_keys_array (const KeaDdnsTsigKey *keys, size_t num_keys);
cJSON *build_kea_ddns_domain_array (const KeaDdnsDomain *domains, size_t num_domains);
cJSON *build_kea_dhcp4_pools_array (const KeaDhcp4Pool *pools, size_t num_pools);
cJSON *build_kea_dhcp4_reservations_array (const KeaDhcp4Reservation *reservations, size_t num_reservations);
cJSON *build_kea_dhcp4_subnet_array (const KeaDhcp4Subnet *subnets, size_t num_subnets);
cJSON *build_kea_dhcp4_shared_networks (const Keadhcp4SharedNetworks *shared_networks, size_t num_subnets);
cJSON *build_kea_dhcp4_client_classes_array (const KeaClientClass *classes, size_t num_classes);
cJSON *build_kea_dhcp6_pools_array (const KeaDhcp6Pool *pools, size_t num_pools);
cJSON *build_kea_dhcp6_reservations_array (const KeaDhcp6Reservation *reservations, size_t num_reservations);
cJSON *build_kea_dhcp6_subnet_array (const KeaDhcp6Subnet *subnets, size_t num_subnets);
cJSON *build_kea_dhcp6_shared_networks_array (const Keadhcp6SharedNetworks *shared_networks, size_t num_subnets);
cJSON *build_kea_dhcp6_client_classes_array (const KeaClientClass *classes, size_t num_classes);

// --- Top-Level Kea Configuration Section Builders ---
cJSON *build_interfaces_config (const KeaConfigData *config);
cJSON *build_lease_database_config (const KeaConfigData *config);
cJSON *build_logging_config_v4 (const KeaConfigData *config);
cJSON *build_logging_config_v6 (const KeaConfigData *config);
cJSON *build_control_socket_config (const KeaConfigData *config);
cJSON *build_ddns_config (const KeaConfigData *config);
cJSON *build_config_control (const KeaConfigData *config);
cJSON *build_hooks_libraries_config (const KeaConfigData *config);

#endif // KEA_CONFIG_BUILDER_INTERNAL_H