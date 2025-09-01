#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <curl/curl.h>

#include "libkeactrl_internal.h" // Includes the full struct definition and public API

#define KEA_API_ENDPOINT "http://127.0.0.1:8000"
#define MAX_ERROR_SIZE 256

// Note: struct kea_ctrl_context_s is now defined in the internal header

static size_t write_callback(void *contents, size_t size, size_t nmemb, void *userp) {
    size_t real_size = size * nmemb;
    struct { char *memory; size_t size; } *mem = userp;
    char *ptr = realloc(mem->memory, mem->size + real_size + 1);
    if (!ptr) {
        fprintf(stderr, "ERROR: Not enough memory (realloc returned NULL)\n");
        return 0;
    }
    mem->memory = ptr;
    memcpy(&(mem->memory[mem->size]), contents, real_size);
    mem->size += real_size;
    mem->memory[mem->size] = 0;
    return real_size;
}

cJSON* execute_transaction_internal(kea_ctrl_context_t ctx,
                                      const char* command,
                                      const char* service,
                                      cJSON* args) {
    // ... function body is unchanged, as `ctx` is already a pointer ...
    // ... all uses of ctx->member are correct ...
    CURLcode res;
    long http_code = 0;
    cJSON *request_root = NULL, *response_json = NULL, *kea_result_obj = NULL, *kea_arguments_obj = NULL;
    char *request_str = NULL;
    bool debug_mode = (getenv("KEACTRL_DEBUG") && strcmp(getenv("KEACTRL_DEBUG"), "1") == 0);

    if (ctx->response_buffer.memory) {
        free(ctx->response_buffer.memory);
        ctx->response_buffer.memory = NULL;
    }
    ctx->response_buffer.memory = malloc(1);
    ctx->response_buffer.size = 0;
    snprintf(ctx->last_error, MAX_ERROR_SIZE, "No error");

    request_root = cJSON_CreateObject();
    if (!request_root) { snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create JSON object for request."); goto cleanup; }
    cJSON_AddStringToObject(request_root, "command", command);
    if (service) { cJSON_AddItemToObject(request_root, "service", cJSON_CreateStringArray(&service, 1)); }
    if (args) { cJSON_AddItemToObject(request_root, "arguments", args); args = NULL; }
    request_str = cJSON_PrintUnformatted(request_root);
    if (!request_str) { snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to convert JSON request to string."); goto cleanup; }

    if (debug_mode) { /* ... logging ... */ }

    curl_easy_setopt(ctx->curl_handle, CURLOPT_POSTFIELDS, request_str);
    curl_easy_setopt(ctx->curl_handle, CURLOPT_POSTFIELDSIZE, (long)strlen(request_str));
    res = curl_easy_perform(ctx->curl_handle);

    if (debug_mode) { /* ... logging ... */ }

    if (res != CURLE_OK) { snprintf(ctx->last_error, MAX_ERROR_SIZE, "curl_easy_perform() failed: %s", curl_easy_strerror(res)); goto cleanup; }
    curl_easy_getinfo(ctx->curl_handle, CURLINFO_RESPONSE_CODE, &http_code);
    if (http_code != 200) { snprintf(ctx->last_error, MAX_ERROR_SIZE, "HTTP request failed with code %ld.", http_code); goto cleanup; }

    response_json = cJSON_Parse(ctx->response_buffer.memory);
    if (!response_json || !cJSON_IsArray(response_json)) { snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to parse Kea response."); goto cleanup; }
    kea_result_obj = cJSON_GetArrayItem(response_json, 0);
    if (!kea_result_obj || !cJSON_IsObject(kea_result_obj)) { snprintf(ctx->last_error, MAX_ERROR_SIZE, "Kea response array is invalid."); goto cleanup; }

    cJSON* kea_result_code = cJSON_GetObjectItem(kea_result_obj, "result");
    if (!cJSON_IsNumber(kea_result_code) || kea_result_code->valueint != 0) {
        cJSON* kea_error_text = cJSON_GetObjectItem(kea_result_obj, "text");
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Kea API Error (%d): %s",
                 kea_result_code ? kea_result_code->valueint : -1,
                 kea_error_text && cJSON_IsString(kea_error_text) ? kea_error_text->valuestring : "Unknown");
        goto cleanup;
    }
    kea_arguments_obj = cJSON_DetachItemFromObject(kea_result_obj, "arguments");

cleanup:
    cJSON_Delete(request_root);
    free(request_str);
    cJSON_Delete(response_json);
    return kea_arguments_obj;
}

// --- Public API Functions ---

kea_ctrl_context_t kea_ctrl_create(const char* socket_path) {
    (void)socket_path;
    // We now allocate the struct directly, not a pointer to it.
    kea_ctrl_context_t ctx = calloc(1, sizeof(struct kea_ctrl_context_s));
    if (!ctx) return NULL;
    
    curl_global_init(CURL_GLOBAL_ALL);
    ctx->curl_handle = curl_easy_init();
    if (!ctx->curl_handle) { free(ctx); return NULL; }

    ctx->headers = curl_slist_append(NULL, "Content-Type: application/json");
    if (!ctx->headers) { curl_easy_cleanup(ctx->curl_handle); free(ctx); return NULL; }
    
    curl_easy_setopt(ctx->curl_handle, CURLOPT_HTTPHEADER, ctx->headers);
    curl_easy_setopt(ctx->curl_handle, CURLOPT_URL, KEA_API_ENDPOINT);
    curl_easy_setopt(ctx->curl_handle, CURLOPT_POST, 1L);
    curl_easy_setopt(ctx->curl_handle, CURLOPT_USERPWD, "root:root");
    curl_easy_setopt(ctx->curl_handle, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(ctx->curl_handle, CURLOPT_WRITEDATA, &ctx->response_buffer);
    curl_easy_setopt(ctx->curl_handle, CURLOPT_ERRORBUFFER, ctx->last_error);

    snprintf(ctx->last_error, MAX_ERROR_SIZE, "No error");
    return ctx; // Return the pointer
}

void kea_ctrl_destroy(kea_ctrl_context_t ctx) {
    if (!ctx) return;
    curl_slist_free_all(ctx->headers);
    curl_easy_cleanup(ctx->curl_handle);
    curl_global_cleanup();
    if (ctx->response_buffer.memory) {
        free(ctx->response_buffer.memory);
    }
    free(ctx);
}

const char* kea_ctrl_get_last_error(const kea_ctrl_context_t ctx) {
    if (!ctx) return "Invalid context provided.";
    return ctx->last_error;
}