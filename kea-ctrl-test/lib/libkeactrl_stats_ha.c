#include "libkeactrl_internal.h"
#include <stdio.h>

/* ========================================================================== */
/*                         5. Statistics Commands                             */
/* ========================================================================== */

cJSON* kea_cmd_statistic_get_all(kea_ctrl_context_t ctx, const char* service) {
    if (ctx) snprintf(ctx->last_error, 256, "Command not yet implemented.");
    (void)service; return NULL;
}
cJSON* kea_cmd_statistic_reset_all(kea_ctrl_context_t ctx, const char* service) {
    if (ctx) snprintf(ctx->last_error, 256, "Command not yet implemented.");
    (void)service; return NULL;
}


/* ========================================================================== */
/*                     6. High Availability (HA) Commands                     */
/* ========================================================================== */

cJSON* kea_cmd_remote_server4_get(kea_ctrl_context_t ctx) {
    if (ctx) snprintf(ctx->last_error, 256, "Command not yet implemented.");
    return NULL;
}
cJSON* kea_cmd_remote_server6_get(kea_ctrl_context_t ctx) {
    if (ctx) snprintf(ctx->last_error, 256, "Command not yet implemented.");
    return NULL;
}