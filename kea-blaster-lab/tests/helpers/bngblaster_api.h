#ifndef BNGBLASTER_API_H
#define BNGBLASTER_API_H

#include <curl/curl.h>
#include <stdbool.h>
#include "cJSON.h"

#ifdef __cplusplus
extern "C" {
#endif

// Opaque pointer to the internal context structure
struct bngblaster_ctx;
typedef struct bngblaster_ctx bngblaster_ctx_t;

// Error codes returned by the API functions
typedef enum {
    BBERR_OK = 0,
    BBERR_MALLOC_FAILED,
    BBERR_INVALID_ARG,
    BBERR_CURL_INIT_FAILED,
    BBERR_REQUEST_FAILED,
    BBERR_API_ERROR,
    BBERR_JSON_ERROR
} bngblaster_error_t;

// Public API Functions that match the Swagger Spec
bngblaster_ctx_t *bngblaster_init (const char *host, int port);
void bngblaster_free (bngblaster_ctx_t *ctx);
const char *bngblaster_get_last_error (bngblaster_ctx_t *ctx);

bngblaster_error_t bngblaster_instance_create (bngblaster_ctx_t *ctx, const char *instance_name, const cJSON *config_json);
bngblaster_error_t bngblaster_instance_start (bngblaster_ctx_t *ctx, const char *instance_name, const cJSON *start_params_json,
                char **response_json);
bngblaster_error_t bngblaster_instance_stop (bngblaster_ctx_t *ctx, const char *instance_name);
bngblaster_error_t bngblaster_instance_delete (bngblaster_ctx_t *ctx, const char *instance_name);
bngblaster_error_t bngblaster_instance_command (bngblaster_ctx_t *ctx, const char *instance_name, const char *command,
                const cJSON *args_json, char **response_json);
bngblaster_error_t bngblaster_instance_get_status (bngblaster_ctx_t *ctx, const char *instance_name, char **response_json);
bngblaster_error_t bngblaster_instance_get_report (bngblaster_ctx_t *ctx, const char *instance_name, char **response_json);

#ifdef __cplusplus
}
#endif

#endif // BNGBLASTER_API_H