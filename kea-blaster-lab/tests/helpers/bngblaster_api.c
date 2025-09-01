#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <curl/curl.h>

#include "bngblaster_api.h"

#define API_PREFIX "/api/v1"
#define MAX_URL_LEN 256
#define ERROR_BUFFER_SIZE 256

struct bngblaster_ctx {
    char *host;
    int port;
    CURL *curl_handle;
    char last_error[ERROR_BUFFER_SIZE];
    int debug;
};

typedef struct { char *data; size_t size; } response_buffer;

static size_t write_callback (void *contents, size_t size, size_t nmemb, void *userp)
{
    size_t realsize = size * nmemb;
    response_buffer *mem = (response_buffer *) userp;
    char *ptr = realloc (mem->data, mem->size + realsize + 1);
    if (!ptr) {
        return 0;
    }
    mem->data = ptr;
    memcpy (& (mem->data[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->data[mem->size] = 0;
    return realsize;
}

static void set_error (bngblaster_ctx_t *ctx, const char *fmt, ...)
{
    if (!ctx) {
        return;
    }
    va_list args;
    va_start (args, fmt);
    vsnprintf (ctx->last_error, ERROR_BUFFER_SIZE, fmt, args);
    va_end (args);
}

static bngblaster_error_t _bngblaster_request (bngblaster_ctx_t *ctx, const char *method, const char *endpoint, const char *post_data,
                char **response_str)
{
    if (!ctx || !ctx->curl_handle) {
        return BBERR_INVALID_ARG;
    }

    char url[MAX_URL_LEN];
    snprintf (url, sizeof (url), "http://%s:%d%s%s", ctx->host, ctx->port, API_PREFIX, endpoint);

    response_buffer chunk = { .data = malloc (1), .size = 0 };
    if (!chunk.data) {
        return BBERR_MALLOC_FAILED;
    }

    struct curl_slist *headers = NULL;
    if (post_data) {
        headers = curl_slist_append (headers, "Content-Type: application/json");
    }

    if (ctx->debug) {
        printf ("\n[BNG_DEBUG] > Request: %s %s\n", method, url);
        if (post_data) {
            printf ("[BNG_DEBUG] > Body: %s\n", post_data);
        }
    }

    curl_easy_setopt (ctx->curl_handle, CURLOPT_URL, url);
    curl_easy_setopt (ctx->curl_handle, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt (ctx->curl_handle, CURLOPT_WRITEDATA, (void *) &chunk);
    curl_easy_setopt (ctx->curl_handle, CURLOPT_CUSTOMREQUEST, method);
    curl_easy_setopt (ctx->curl_handle, CURLOPT_POSTFIELDS, post_data);
    curl_easy_setopt (ctx->curl_handle, CURLOPT_HTTPHEADER, headers);

    CURLcode res = curl_easy_perform (ctx->curl_handle);
    curl_slist_free_all (headers);

    long http_code = 0;
    curl_easy_getinfo (ctx->curl_handle, CURLINFO_RESPONSE_CODE, &http_code);

    if (ctx->debug) {
        printf ("[BNG_DEBUG] < Status: %ld\n", http_code);
        if (chunk.data) {
            printf ("[BNG_DEBUG] < Response: %s\n", chunk.data);
        }
    }

    if (res != CURLE_OK) {
        set_error (ctx, "curl_easy_perform() failed: %s", curl_easy_strerror (res));
        free (chunk.data);
        return BBERR_REQUEST_FAILED;
    }

    if (http_code < 200 || http_code >= 300) {
        set_error (ctx, "API returned HTTP status %ld. Response: %s", http_code, chunk.data ? chunk.data : "");
        free (chunk.data);
        return BBERR_API_ERROR;
    }

    if (response_str) {
        *response_str = chunk.data;
    } else {
        free (chunk.data);
    }

    return BBERR_OK;
}

bngblaster_ctx_t *bngblaster_init (const char *host, int port)
{
    bngblaster_ctx_t *ctx = calloc (1, sizeof (bngblaster_ctx_t));
    if (!ctx) {
        return NULL;
    }
    ctx->host = strdup (host);
    ctx->port = port;
    const char *debug_env = getenv ("BNG_HELPER_DEBUG");
    ctx->debug = (debug_env && strcmp (debug_env, "1") == 0);
    curl_global_init (CURL_GLOBAL_DEFAULT);
    ctx->curl_handle = curl_easy_init();
    if (!ctx->curl_handle || !ctx->host) {
        bngblaster_free (ctx);
        return NULL;
    }
    return ctx;
}

void bngblaster_free (bngblaster_ctx_t *ctx)
{
    if (!ctx) {
        return;
    }
    if (ctx->curl_handle) {
        curl_easy_cleanup (ctx->curl_handle);
    }
    curl_global_cleanup();
    free (ctx->host);
    free (ctx);
}

const char *bngblaster_get_last_error (bngblaster_ctx_t *ctx)
{
    return ctx ? ctx->last_error : "Invalid context";
}

bngblaster_error_t bngblaster_instance_create (bngblaster_ctx_t *ctx, const char *instance_name, const cJSON *config_json)
{
    char endpoint[MAX_URL_LEN];
    snprintf (endpoint, sizeof (endpoint), "/instances/%s", instance_name);
    char *config_str = cJSON_PrintUnformatted (config_json);
    if (!config_str) {
        return BBERR_JSON_ERROR;
    }
    bngblaster_error_t err = _bngblaster_request (ctx, "PUT", endpoint, config_str, NULL);
    free (config_str);
    return err;
}

bngblaster_error_t bngblaster_instance_start (bngblaster_ctx_t *ctx, const char *instance_name, const cJSON *start_params_json,
                char **response_json)
{
    char endpoint[MAX_URL_LEN];
    snprintf (endpoint, sizeof (endpoint), "/instances/%s/_start", instance_name);
    char *params_str = cJSON_PrintUnformatted (start_params_json);
    if (!params_str) {
        return BBERR_JSON_ERROR;
    }
    bngblaster_error_t err = _bngblaster_request (ctx, "POST", endpoint, params_str, response_json);
    free (params_str);
    return err;
}

bngblaster_error_t bngblaster_instance_stop (bngblaster_ctx_t *ctx, const char *instance_name)
{
    char endpoint[MAX_URL_LEN];
    snprintf (endpoint, sizeof (endpoint), "/instances/%s/_stop", instance_name);
    return _bngblaster_request (ctx, "POST", endpoint, NULL, NULL);
}

bngblaster_error_t bngblaster_instance_delete (bngblaster_ctx_t *ctx, const char *instance_name)
{
    char endpoint[MAX_URL_LEN];
    snprintf (endpoint, sizeof (endpoint), "/instances/%s", instance_name);
    return _bngblaster_request (ctx, "DELETE", endpoint, NULL, NULL);
}

bngblaster_error_t bngblaster_instance_command (bngblaster_ctx_t *ctx, const char *instance_name, const char *command,
                const cJSON *args_json, char **response_json)
{
    char endpoint[MAX_URL_LEN];
    snprintf (endpoint, sizeof (endpoint), "/instances/%s/_command", instance_name);

    cJSON *payload = cJSON_CreateObject();
    cJSON_AddStringToObject (payload, "command", command);
    if (args_json) {
        cJSON_AddItemToObject (payload, "arguments", cJSON_Duplicate (args_json, true));
    }

    char *payload_str = cJSON_PrintUnformatted (payload);
    cJSON_Delete (payload);
    if (!payload_str) {
        return BBERR_JSON_ERROR;
    }

    bngblaster_error_t err = _bngblaster_request (ctx, "POST", endpoint, payload_str, response_json);
    free (payload_str);
    return err;
}

bngblaster_error_t bngblaster_instance_get_report (bngblaster_ctx_t *ctx, const char *instance_name, char **response_json)
{
    char endpoint[MAX_URL_LEN];
    snprintf (endpoint, sizeof (endpoint), "/instances/%s/run_report.json", instance_name);
    return _bngblaster_request (ctx, "GET", endpoint, NULL, response_json);
}

bngblaster_error_t bngblaster_instance_get_status (bngblaster_ctx_t *ctx, const char *instance_name, char **response_json)
{
    char endpoint[MAX_URL_LEN];
    snprintf (endpoint, sizeof (endpoint), "/instances/%s", instance_name);
    return _bngblaster_request (ctx, "GET", endpoint, NULL, response_json);
}