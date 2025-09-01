#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <curl/curl.h>

#include "keactrl_internal.h"

// The default endpoint for the Kea Control Agent if not specified by the user.
#define KEA_API_ENDPOINT "http://127.0.0.1:8000"

/**
 * @brief libcurl callback to capture the HTTP response body into a buffer.
 */
static size_t write_callback (void *contents, size_t size, size_t nmemb, void *userp)
{
    size_t real_size = size * nmemb;
    http_response_buffer_t *mem = (http_response_buffer_t *) userp;
    char *ptr = realloc (mem->memory, mem->size + real_size + 1);
    if (!ptr) {
        fprintf (stderr, "ERROR: Not enough memory (realloc returned NULL)\n");
        return 0;
    }
    mem->memory = ptr;
    memcpy (& (mem->memory[mem->size]), contents, real_size);
    mem->size += real_size;
    mem->memory[mem->size] = 0;
    return real_size;
}

// See header keactrl_internal.h for documentation.
cJSON *execute_transaction_internal (kea_ctrl_context_t ctx,
                const char *command,
                const char **services,
                cJSON *args)
{
    CURLcode res;
    long http_code = 0;
    cJSON *request_root = NULL;
    cJSON *response_json = NULL;
    char *request_str = NULL;

    if (!ctx) {
        return NULL;
    }

    // Reset response buffer and error state for this new transaction
    if (ctx->response_buffer.memory) {
        free (ctx->response_buffer.memory);
    }
    ctx->response_buffer.memory = malloc (1);
    ctx->response_buffer.size = 0;
    snprintf (ctx->last_error, MAX_ERROR_SIZE, "No error");

    // --- Build the JSON-RPC request payload ---
    request_root = cJSON_CreateObject();
    if (!request_root) {
        snprintf (ctx->last_error, MAX_ERROR_SIZE, "Failed to create JSON request object.");
        goto cleanup;
    }

    cJSON_AddStringToObject (request_root, "command", command);

    // Add "service" array if provided
    if (services && *services) {
        int count = 0;
        const char **s = services;
        while (*s++) {
            count++;
        }
        if (count > 0) {
            cJSON *service_array = cJSON_CreateStringArray (services, count);
            cJSON_AddItemToObject (request_root, "service", service_array);
        }
    }

    // Add "arguments" object if provided
    if (args) {
        cJSON_AddItemToObject (request_root, "arguments", args);
        args = NULL; // The request_root now owns the args object
    }

    request_str = cJSON_PrintUnformatted (request_root);
    curl_easy_setopt (ctx->curl_handle, CURLOPT_POSTFIELDS, request_str);

    // --- Perform the HTTP request ---
    res = curl_easy_perform (ctx->curl_handle);
    if (res != CURLE_OK) {
        snprintf (ctx->last_error, MAX_ERROR_SIZE, "curl_easy_perform() failed: %s", curl_easy_strerror (res));
        goto cleanup;
    }

    curl_easy_getinfo (ctx->curl_handle, CURLINFO_RESPONSE_CODE, &http_code);
    if (http_code != 200) {
        snprintf (ctx->last_error, MAX_ERROR_SIZE, "HTTP request failed with code %ld.", http_code);
        goto cleanup;
    }

    // --- Parse and validate the response ---
    response_json = cJSON_Parse (ctx->response_buffer.memory);
    if (!response_json || !cJSON_IsArray (response_json)) {
        snprintf (ctx->last_error, MAX_ERROR_SIZE, "Failed to parse Kea response as a JSON array.");
        goto cleanup;
    }

    // Check the result code of the first (or only) response object
    cJSON *result_obj = cJSON_GetArrayItem (response_json, 0);
    if (!cJSON_IsObject (result_obj)) {
        snprintf (ctx->last_error, MAX_ERROR_SIZE, "Kea response array item is not an object.");
        goto cleanup;
    }

    cJSON *kea_result_code = cJSON_GetObjectItem (result_obj, "result");
    if (!cJSON_IsNumber (kea_result_code) || kea_result_code->valueint != 0) {
        // If multiple services were queried, a failure in one is not a total failure.
        // The caller must inspect the individual result objects. We only fail here
        // for single-service calls.
        if (!services || !services[1]) {
            cJSON *kea_error_text = cJSON_GetObjectItem (result_obj, "text");
            snprintf (ctx->last_error, MAX_ERROR_SIZE, "Kea API Error (%d): %s",
                            (int) kea_result_code->valuedouble,
                            cJSON_IsString (kea_error_text) ? kea_error_text->valuestring : "Unknown error");
            goto cleanup;
        }
    }

    goto success;

cleanup:
    cJSON_Delete (response_json); // Will be NULL if we never got here
    response_json = NULL;
    // Fall-through to free other resources

success:
    cJSON_Delete (request_root);
    free (request_str);
    return response_json;
}

// See header keactrl.h for documentation.
kea_ctrl_context_t kea_ctrl_create (const char *api_endpoint)
{
    kea_ctrl_context_t ctx = calloc (1, sizeof (struct kea_ctrl_context_s));
    if (!ctx) {
        return NULL;
    }

    curl_global_init (CURL_GLOBAL_ALL);
    ctx->curl_handle = curl_easy_init();
    if (!ctx->curl_handle) {
        free (ctx);
        curl_global_cleanup();
        return NULL;
    }

    // --- Configure cURL handle ---
    ctx->headers = curl_slist_append (NULL, "Content-Type: application/json");
    curl_easy_setopt (ctx->curl_handle, CURLOPT_HTTPHEADER, ctx->headers);
    curl_easy_setopt (ctx->curl_handle, CURLOPT_URL, api_endpoint ? api_endpoint : KEA_API_ENDPOINT);
    curl_easy_setopt (ctx->curl_handle, CURLOPT_POST, 1L);
    curl_easy_setopt (ctx->curl_handle, CURLOPT_USERPWD, "root:root"); // Default auth for lab
    curl_easy_setopt (ctx->curl_handle, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt (ctx->curl_handle, CURLOPT_WRITEDATA, &ctx->response_buffer);
    curl_easy_setopt (ctx->curl_handle, CURLOPT_ERRORBUFFER, ctx->last_error);

    snprintf (ctx->last_error, MAX_ERROR_SIZE, "No error");
    return ctx;
}

// See header keactrl.h for documentation.
void kea_ctrl_destroy (kea_ctrl_context_t ctx)
{
    if (!ctx) {
        return;
    }
    curl_slist_free_all (ctx->headers);
    curl_easy_cleanup (ctx->curl_handle);
    curl_global_cleanup();
    if (ctx->response_buffer.memory) {
        free (ctx->response_buffer.memory);
    }
    free (ctx);
}

// See header keactrl.h for documentation.
const char *kea_ctrl_get_last_error (const kea_ctrl_context_t ctx)
{
    if (!ctx) {
        return "Invalid context provided.";
    }
    return ctx->last_error;
}