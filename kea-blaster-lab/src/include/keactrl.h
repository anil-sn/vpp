#ifndef KEACTRL_H
#define KEACTRL_H

#include "cJSON.h"
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ==========================================================================
//                      Core Library Context Management
// ==========================================================================

/**
 * @brief Opaque pointer to the internal library context structure.
 *
 * This handle encapsulates all state for a connection to the Kea Control Agent,
 * including cURL handles, buffers, and error information.
 */
struct kea_ctrl_context_s;
typedef struct kea_ctrl_context_s *kea_ctrl_context_t;

/**
 * @brief Creates a context for communicating with the Kea Control Agent.
 *
 * This is the first function that must be called. It initializes all necessary
 * resources for making API requests.
 *
 * @param api_endpoint The base URL of the agent (e.g., "http://127.0.0.1:8000").
 *                     If NULL, the default "http://127.0.0.1:8000" is used.
 * @return A new context handle, or NULL on failure.
 */
kea_ctrl_context_t kea_ctrl_create (const char *api_endpoint);

/**
 * @brief Destroys a context and frees all associated resources.
 *
 * This function should be called when you are finished interacting with the
 * Kea API to clean up network handles and memory.
 *
 * @param ctx The context handle to destroy.
 */
void kea_ctrl_destroy (kea_ctrl_context_t ctx);

/**
 * @brief Retrieves the last error message recorded in the context.
 *
 * If an API function returns NULL, this function can be used to get a
 * human-readable string describing the failure.
 *
 * @param ctx The context handle.
 * @return A pointer to a string containing the last error message.
 */
const char *kea_ctrl_get_last_error (const kea_ctrl_context_t ctx);

// ==========================================================================
//                      Generic & Daemon Control Commands
// ==========================================================================

cJSON *kea_cmd_list_commands (kea_ctrl_context_t ctx, const char *service);
cJSON *kea_cmd_version_get (kea_ctrl_context_t ctx, const char **services);
cJSON *kea_cmd_status_get (kea_ctrl_context_t ctx, const char *service);
cJSON *kea_cmd_shutdown (kea_ctrl_context_t ctx, const char *service);
cJSON *kea_cmd_build_report (kea_ctrl_context_t ctx, const char *service);

// ==========================================================================
//                        Configuration Commands
// ==========================================================================

cJSON *kea_cmd_config_get (kea_ctrl_context_t ctx, const char *service);
cJSON *kea_cmd_config_set (kea_ctrl_context_t ctx, const char *service, const cJSON *config_json);
cJSON *kea_cmd_config_reload (kea_ctrl_context_t ctx, const char *service);
cJSON *kea_cmd_config_test (kea_ctrl_context_t ctx, const char *service, const cJSON *config_json);
cJSON *kea_cmd_config_write (kea_ctrl_context_t ctx, const char *service, const char *filename);
cJSON *kea_cmd_config_backend_pull (kea_ctrl_context_t ctx, const char *service);
cJSON *kea_cmd_config_hash_get (kea_ctrl_context_t ctx, const char *service);
cJSON *kea_cmd_server_tag_get (kea_ctrl_context_t ctx, const char *service);

// ==========================================================================
//                     Subnet Commands (subnet_cmds hook)
// ==========================================================================

cJSON *kea_cmd_subnet4_list (kea_ctrl_context_t ctx);
cJSON *kea_cmd_subnet4_get (kea_ctrl_context_t ctx, int subnet_id);
cJSON *kea_cmd_subnet4_add (kea_ctrl_context_t ctx, const cJSON *subnet_data);
cJSON *kea_cmd_subnet4_del (kea_ctrl_context_t ctx, int subnet_id);
cJSON *kea_cmd_subnet4_update (kea_ctrl_context_t ctx, const cJSON *subnet_data);

cJSON *kea_cmd_subnet6_list (kea_ctrl_context_t ctx);
cJSON *kea_cmd_subnet6_get (kea_ctrl_context_t ctx, int subnet_id);
cJSON *kea_cmd_subnet6_add (kea_ctrl_context_t ctx, const cJSON *subnet_data);
cJSON *kea_cmd_subnet6_del (kea_ctrl_context_t ctx, int subnet_id);
cJSON *kea_cmd_subnet6_update (kea_ctrl_context_t ctx, const cJSON *subnet_data);

// ==========================================================================
//                    Lease Commands (lease_cmds hook)
// ==========================================================================

cJSON *kea_cmd_lease4_add (kea_ctrl_context_t ctx, const cJSON *lease_data);
cJSON *kea_cmd_lease4_del (kea_ctrl_context_t ctx, const char *ip_address);
cJSON *kea_cmd_lease4_get_by_ip (kea_ctrl_context_t ctx, const char *ip_address);
cJSON *kea_cmd_lease4_get_by_hw_address (kea_ctrl_context_t ctx, const char *hw_address);
cJSON *kea_cmd_lease4_get_by_client_id (kea_ctrl_context_t ctx, const char *client_id);
cJSON *kea_cmd_lease4_get_all (kea_ctrl_context_t ctx, int subnet_id);
cJSON *kea_cmd_lease4_wipe (kea_ctrl_context_t ctx, int subnet_id);

cJSON *kea_cmd_lease6_add (kea_ctrl_context_t ctx, const cJSON *lease_data);
cJSON *kea_cmd_lease6_del (kea_ctrl_context_t ctx, const char *ip_address);
cJSON *kea_cmd_lease6_get_by_ip (kea_ctrl_context_t ctx, const char *ip_address);
cJSON *kea_cmd_lease6_get_by_duid (kea_ctrl_context_t ctx, const char *duid, int iaid);
cJSON *kea_cmd_lease6_get_all (kea_ctrl_context_t ctx, int subnet_id);
cJSON *kea_cmd_lease6_wipe (kea_ctrl_context_t ctx, int subnet_id);

// ==========================================================================
//                   Host/Reservation Commands (host_cmds hook)
// ==========================================================================

cJSON *kea_cmd_reservation_add (kea_ctrl_context_t ctx, const char *service, const cJSON *host_data);
cJSON *kea_cmd_reservation_del_by_ip (kea_ctrl_context_t ctx, const char *service, int subnet_id, const char *ip_address);
cJSON *kea_cmd_reservation_get_by_ip (kea_ctrl_context_t ctx, const char *service, const char *ip_address);
cJSON *kea_cmd_reservation_get_all (kea_ctrl_context_t ctx, const char *service, int subnet_id);

// ==========================================================================
//                   Statistics Commands
// ==========================================================================

cJSON *kea_cmd_statistic_get (kea_ctrl_context_t ctx, const char *service, const char *name);
cJSON *kea_cmd_statistic_get_all (kea_ctrl_context_t ctx, const char *service);
cJSON *kea_cmd_statistic_reset (kea_ctrl_context_t ctx, const char *service, const char *name);
cJSON *kea_cmd_statistic_reset_all (kea_ctrl_context_t ctx, const char *service);
cJSON *kea_cmd_statistic_remove (kea_ctrl_context_t ctx, const char *service, const char *name);
cJSON *kea_cmd_statistic_remove_all (kea_ctrl_context_t ctx, const char *service);

// ==========================================================================
//                   Client Class Commands (class_cmds hook)
// ==========================================================================

cJSON *kea_cmd_class_add (kea_ctrl_context_t ctx, const char *service, const cJSON *class_data);
cJSON *kea_cmd_class_del (kea_ctrl_context_t ctx, const char *service, const char *class_name);
cJSON *kea_cmd_class_list (kea_ctrl_context_t ctx, const char *service);

// ==========================================================================
//                   Host Cache Commands (host_cache hook)
// ==========================================================================

cJSON *kea_cmd_cache_clear (kea_ctrl_context_t ctx, const char *service);
cJSON *kea_cmd_cache_size (kea_ctrl_context_t ctx, const char *service);
cJSON *kea_cmd_cache_get (kea_ctrl_context_t ctx, const char *service);


// ==========================================================================
//             Programmatic Kea Configuration Builder API
//
// These data structures and functions allow you to build a full Kea DHCP
// configuration in C, which can then be converted to a cJSON object and
// sent to the server via kea_cmd_config_set().
// ==========================================================================

// --- Public-Facing Data Structures for Configuration ---

typedef struct {
    char name[255];
    int code;
    char data[255];
} KeaOptionData;

typedef struct {
    const char *output_target;
    int maxsize;
    int maxver;
    cJSON_bool flush;
} KeaLoggerOutputConfig;

typedef struct {
    const char *name;
    const char *severity;
    int debuglevel;
    KeaLoggerOutputConfig *output_options;
    size_t num_output_options;
} KeaLoggerConfig;

typedef struct {
    const char *name;
    const char *algorithm;
    const char *secret;
} KeaDdnsTsigKey;

typedef struct {
    const char *name;
    const char *key_name;
    const char **dns_servers;
    size_t num_dns_servers;
} KeaDdnsDomain;

typedef struct {
    const char *pool_range;
    const char *client_class;
} KeaDhcp4Pool;

typedef struct {
    const char *hw_address;
    const char *client_id;
    const char *ip_address;
    const char *hostname;
    const char *client_class;
    KeaOptionData *option_data;
    size_t num_option_data;
} KeaDhcp4Reservation;

typedef struct {
    uint8_t subnet_id;
    const char *subnet_cidr;
    int valid_lifetime;
    int renew_timer;
    int rebind_timer;
    KeaDhcp4Pool *pool;
    size_t num_pools;
    KeaOptionData *option_data;
    size_t num_option_data;
    KeaDhcp4Reservation *reservations;
    size_t num_reservations;
} KeaDhcp4Subnet;

typedef struct {
    char name[255];
    char interface[255];
    KeaDhcp4Subnet *v4subnets;
} Keadhcp4SharedNetworks;

typedef struct {
    const char *pool_range;
    const char *ia_type;
    int prefix_len;
} KeaDhcp6Pool;

typedef struct {
    const char *duid;
    const char *hw_address;
    const char **ip_addresses;
    size_t num_ip_addresses;
    const char **prefixes;
    size_t num_prefixes;
    int preferred_lifetime;
    int valid_lifetime;
    const char *client_class;
    KeaOptionData *option_data;
    size_t num_option_data;
} KeaDhcp6Reservation;

typedef struct {
    uint8_t subnet_id;
    const char *subnet_cidr;
    int preferred_lifetime;
    int valid_lifetime;
    KeaDhcp6Pool *pool;
    size_t num_pools;
    KeaOptionData *option_data;
    size_t num_option_data;
    KeaDhcp6Reservation *reservations;
    size_t num_reservations;
} KeaDhcp6Subnet;

typedef struct {
    char name[255];
    char interface[255];
    KeaDhcp6Subnet *v6subnets;
} Keadhcp6SharedNetworks;

typedef struct {
    const char *name;
    const char *test_condition;
    KeaOptionData *option_data;
    size_t num_option_data;
} KeaClientClass;

typedef struct {
    const char **interfaces;
    size_t num_interfaces;
    cJSON_bool authoritative;
    const char *lease_db_type;
    const char *lease_db_name;
    cJSON_bool lease_db_persist;
    int lease_db_lfc_interval;
    KeaLoggerConfig *loggers;
    size_t num_loggers;
    const char *ctrl_socket_type;
    const char *ctrl_socket_path;
    cJSON_bool ddns_enable_updates;
    const char *ddns_server_ip;
    int ddns_server_port;
    const char *ddns_generated_hostname_suffix;
    cJSON_bool qualify_with_stealth_bypass;
    KeaDdnsTsigKey *ddns_tsig_keys;
    size_t num_ddns_tsig_keys;
    KeaDdnsDomain *ddns_forward_domains;
    size_t num_ddns_forward_domains;
    KeaDdnsDomain *ddns_reverse_domains;
    size_t num_ddns_reverse_domains;
    cJSON_bool config_control_report_hwaddr_mismatch;
    int config_control_max_lease_time;
    int config_control_min_lease_time;
    const char **hooks_libraries;
    size_t num_hooks_libraries;
    int v4_global_valid_lifetime;
    int v4_global_renew_timer;
    int v4_global_rebind_timer;
    KeaOptionData *v4_global_option_data;
    size_t num_v4_global_option_data;
    KeaDhcp4Subnet *v4_subnets;
    Keadhcp4SharedNetworks shared_networks;
    size_t num_v4_subnets;
    KeaClientClass *v4_client_classes;
    size_t num_v4_client_classes;
    cJSON_bool v4_enable_ddns;
    int v4_ddns_server_timeout;
    int v6_global_preferred_lifetime;
    int v6_global_valid_lifetime;
    int v6_global_renew_timer;
    int v6_global_rebind_timer;
    const char *v6_server_id_type;
    const char *v6_server_duid;
    KeaOptionData *v6_global_option_data;
    size_t num_v6_global_option_data;
    KeaDhcp6Subnet *v6_subnets;
    Keadhcp6SharedNetworks v6_shared_networks;
    size_t num_v6_subnets;
    KeaClientClass *v6_client_classes;
    size_t num_v6_client_classes;
    cJSON_bool v6_enable_ddns;
} KeaConfigData;

/**
 * @brief Builds a cJSON object representing a complete Dhcp4 configuration.
 * @param config A pointer to a user-populated KeaConfigData struct.
 * @return A new cJSON object, or NULL on failure. Caller must free with cJSON_Delete().
 */
cJSON *build_dhcp4_config (const KeaConfigData *config);

/**
 * @brief Builds a cJSON object representing a complete Dhcp6 configuration.
 * @param config A pointer to a user-populated KeaConfigData struct.
 * @return A new cJSON object, or NULL on failure. Caller must free with cJSON_Delete().
 */
cJSON *build_dhcp6_config (const KeaConfigData *config);

#ifdef __cplusplus
}
#endif

#endif // KEACTRL_H
