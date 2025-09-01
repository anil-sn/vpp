#ifndef LIBKEACTRL_H
#define LIBKEACTRL_H

#include "cJSON.h"

// --- Opaque Pointer Definition ---
// Forward-declare the internal struct. Users only know it exists.
struct kea_ctrl_context_s;

// The public type is a POINTER to the incomplete struct.
typedef struct kea_ctrl_context_s* kea_ctrl_context_t;


// --- CORRECTED Function Prototypes ---

/**
 * @brief Creates a new Kea control context.
 * @return A context handle (kea_ctrl_context_t) on success, NULL on failure.
 */
kea_ctrl_context_t kea_ctrl_create(const char* socket_path);

/**
 * @brief Destroys a Kea control context and frees all associated resources.
 * @param ctx The context handle to destroy.
 */
void kea_ctrl_destroy(kea_ctrl_context_t ctx);

/**
 * @brief Returns the last error message for a failed API call.
 * @param ctx The context handle.
 * @return A constant string describing the last error. Do not free.
 */
const char* kea_ctrl_get_last_error(const kea_ctrl_context_t ctx);

/* ========================================================================== */
/*                           1. Generic Commands                              */
/* ========================================================================== */

cJSON* kea_cmd_list_commands(kea_ctrl_context_t ctx, const char* service);
cJSON* kea_cmd_version_get(kea_ctrl_context_t ctx, const char** services);
cJSON* kea_cmd_status_get(kea_ctrl_context_t ctx, const char* service);
cJSON* kea_cmd_shutdown(kea_ctrl_context_t ctx, const char* service);

/* ========================================================================== */
/*                         2. Configuration Commands                          */
/* ========================================================================== */

cJSON* kea_cmd_config_get(kea_ctrl_context_t ctx, const char* service);
cJSON* kea_cmd_config_set(kea_ctrl_context_t ctx, const char* service, const cJSON* config_json);
cJSON* kea_cmd_config_reload(kea_ctrl_context_t ctx, const char* service);
cJSON* kea_cmd_config_test(kea_ctrl_context_t ctx, const char* service, const cJSON* config_json);
cJSON* kea_cmd_config_write(kea_ctrl_context_t ctx, const char* service, const char* filename);

/* ========================================================================== */
/*                 3. DHCPv4 Lease & Network Management Commands              */
/* ========================================================================== */

cJSON* kea_cmd_lease4_get_by_ip(kea_ctrl_context_t ctx, const char* ip_address);
cJSON* kea_cmd_lease4_get_by_hw_addr(kea_ctrl_context_t ctx, const char* hw_address);
cJSON* kea_cmd_lease4_get_by_client_id(kea_ctrl_context_t ctx, const char* client_id);
cJSON* kea_cmd_lease4_get_all(kea_ctrl_context_t ctx, int subnet_id);
cJSON* kea_cmd_lease4_del(kea_ctrl_context_t ctx, const char* ip_address);
cJSON* kea_cmd_lease4_add(kea_ctrl_context_t ctx, const cJSON* lease_data);
cJSON* kea_cmd_lease4_wipe(kea_ctrl_context_t ctx, int subnet_id);
cJSON* kea_cmd_subnet4_list(kea_ctrl_context_t ctx);

/* ========================================================================== */
/*                 4. DHCPv6 Lease & Network Management Commands              */
/* ========================================================================== */

cJSON* kea_cmd_lease6_get_by_ip(kea_ctrl_context_t ctx, const char* ip_address);
cJSON* kea_cmd_lease6_get_by_duid(kea_ctrl_context_t ctx, const char* duid, int iaid);
cJSON* kea_cmd_lease6_get_all(kea_ctrl_context_t ctx, int subnet_id);
cJSON* kea_cmd_lease6_del(kea_ctrl_context_t ctx, const char* ip_address);
cJSON* kea_cmd_lease6_add(kea_ctrl_context_t ctx, const cJSON* lease_data);
cJSON* kea_cmd_lease6_wipe(kea_ctrl_context_t ctx, int subnet_id);
cJSON* kea_cmd_subnet6_list(kea_ctrl_context_t ctx);

/* ========================================================================== */
/*                         5. Statistics Commands                             */
/* ========================================================================== */

cJSON* kea_cmd_statistic_get_all(kea_ctrl_context_t ctx, const char* service);
cJSON* kea_cmd_statistic_reset_all(kea_ctrl_context_t ctx, const char* service);

/* ========================================================================== */
/*                     6. High Availability (HA) Commands                     */
/* ========================================================================== */

cJSON* kea_cmd_remote_server4_get(kea_ctrl_context_t ctx);
cJSON* kea_cmd_remote_server6_get(kea_ctrl_context_t ctx);

#endif // LIBKEACTRL_H