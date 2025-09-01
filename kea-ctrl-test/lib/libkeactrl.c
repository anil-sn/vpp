#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <curl/curl.h>

#include "libkeactrl.h"

#define KEA_API_ENDPOINT "http://127.0.0.1:8000"
#define MAX_ERROR_SIZE 256

struct kea_ctrl_context {
    CURL *curl_handle;
    char last_error[MAX_ERROR_SIZE];
    struct {
        char *memory;
        size_t size;
    } response_buffer;
    struct curl_slist *headers;
};

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

static cJSON* execute_transaction_internal(kea_ctrl_context_t* ctx,
                                           const char* command,
                                           const char* service,
                                           cJSON* args) {
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
    if (!request_root) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create JSON object for request.");
        goto cleanup;
    }
    cJSON_AddStringToObject(request_root, "command", command);
    if (service) {
        cJSON_AddItemToObject(request_root, "service", cJSON_CreateStringArray(&service, 1));
    }
    if (args) {
        cJSON_AddItemToObject(request_root, "arguments", args);
        args = NULL;
    }

    request_str = cJSON_PrintUnformatted(request_root);
    if (!request_str) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to convert JSON request to string.");
        goto cleanup;
    }

    if (debug_mode) {
        char* pretty_request = cJSON_Print(request_root);
        fprintf(stderr, "[DEBUG] Request JSON:\n%s\n", pretty_request);
        free(pretty_request);
    }

    curl_easy_setopt(ctx->curl_handle, CURLOPT_POSTFIELDS, request_str);
    curl_easy_setopt(ctx->curl_handle, CURLOPT_POSTFIELDSIZE, (long)strlen(request_str));
    res = curl_easy_perform(ctx->curl_handle);

    if (debug_mode) {
        cJSON* temp_response_json = cJSON_Parse(ctx->response_buffer.memory);
        if (temp_response_json) {
            char* pretty_response = cJSON_Print(temp_response_json);
            fprintf(stderr, "[DEBUG] Response JSON:\n%s\n", pretty_response);
            free(pretty_response);
            cJSON_Delete(temp_response_json);
        } else {
            fprintf(stderr, "[DEBUG] Raw Response (not valid JSON):\n%s\n", ctx->response_buffer.memory);
        }
    }

    if (res != CURLE_OK) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "curl_easy_perform() failed: %s", curl_easy_strerror(res));
        goto cleanup;
    }

    curl_easy_getinfo(ctx->curl_handle, CURLINFO_RESPONSE_CODE, &http_code);
    if (http_code != 200) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "HTTP request failed with code %ld. Response: %.100s",
                 http_code, ctx->response_buffer.memory ? ctx->response_buffer.memory : "(empty)");
        goto cleanup;
    }

    response_json = cJSON_Parse(ctx->response_buffer.memory);
    if (!response_json || !cJSON_IsArray(response_json)) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to parse Kea response as a JSON array.");
        goto cleanup;
    }

    kea_result_obj = cJSON_GetArrayItem(response_json, 0);
    if (!kea_result_obj || !cJSON_IsObject(kea_result_obj)) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Kea response array is empty or invalid.");
        goto cleanup;
    }

    cJSON* kea_result_code = cJSON_GetObjectItem(kea_result_obj, "result");
    if (!cJSON_IsNumber(kea_result_code) || kea_result_code->valueint != 0) {
        cJSON* kea_error_text = cJSON_GetObjectItem(kea_result_obj, "text");
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Kea API Error (%d): %s",
                 kea_result_code ? kea_result_code->valueint : -1,
                 kea_error_text && cJSON_IsString(kea_error_text) ? kea_error_text->valuestring : "Unknown error message");
        goto cleanup;
    }

    kea_arguments_obj = cJSON_DetachItemFromObject(kea_result_obj, "arguments");

cleanup:
    cJSON_Delete(request_root);
    free(request_str);
    cJSON_Delete(response_json);

    return kea_arguments_obj;
}

kea_ctrl_context_t* kea_ctrl_create(const char* socket_path) {
    (void)socket_path;
    kea_ctrl_context_t* ctx = calloc(1, sizeof(kea_ctrl_context_t));
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
    return ctx;
}

void kea_ctrl_destroy(kea_ctrl_context_t* ctx) {
    if (!ctx) return;
    curl_slist_free_all(ctx->headers);
    curl_easy_cleanup(ctx->curl_handle);
    curl_global_cleanup();
    if (ctx->response_buffer.memory) {
        free(ctx->response_buffer.memory);
    }
    free(ctx);
}

const char* kea_ctrl_get_last_error(const kea_ctrl_context_t* ctx) {
    if (!ctx) return "Invalid context provided.";
    return ctx->last_error;
}


cJSON* kea_cmd_list_commands(kea_ctrl_context_t* ctx, const char* service) {
    if (!ctx || !service) { if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Invalid argument."); return NULL; }
    return execute_transaction_internal(ctx, "list-commands", service, NULL);
}

cJSON* kea_cmd_version_get(kea_ctrl_context_t* ctx, const char** services) {
    if (!ctx) return NULL;
    cJSON* args = NULL;
    if (services && services[0]) {
        args = cJSON_CreateObject();
        cJSON_AddItemToObject(args, "service", cJSON_CreateStringArray(services, -1));
    }
    return execute_transaction_internal(ctx, "version-get", NULL, args);
}

cJSON* kea_cmd_status_get(kea_ctrl_context_t* ctx, const char* service) {
    if (!ctx || !service) { if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Invalid argument."); return NULL; }
    return execute_transaction_internal(ctx, "status-get", service, NULL);
}

cJSON* kea_cmd_shutdown(kea_ctrl_context_t* ctx, const char* service) {
    if (!ctx || !service) { if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Invalid argument."); return NULL; }
    return execute_transaction_internal(ctx, "shutdown", service, NULL);
}

cJSON* kea_cmd_config_get(kea_ctrl_context_t* ctx, const char* service) {
    if (!ctx || !service) { if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Invalid argument."); return NULL; }
    return execute_transaction_internal(ctx, "config-get", service, NULL);
}

cJSON* kea_cmd_config_set(kea_ctrl_context_t* ctx, const char* service, const cJSON* config_json) {
    if (!ctx || !service || !config_json) { if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Invalid argument."); return NULL; }
    cJSON* args = cJSON_CreateObject();
    cJSON_AddItemToObject(args, (char*)service, cJSON_Duplicate(config_json, 1));
    return execute_transaction_internal(ctx, "config-set", service, args);
}

cJSON* kea_cmd_config_reload(kea_ctrl_context_t* ctx, const char* service) {
    if (!ctx || !service) { if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Invalid argument."); return NULL; }
    return execute_transaction_internal(ctx, "config-reload", service, NULL);
}

cJSON* kea_cmd_config_test(kea_ctrl_context_t* ctx, const char* service, const cJSON* config_json) {
    if (!ctx || !service || !config_json) { if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Invalid argument."); return NULL; }
    cJSON* args = cJSON_CreateObject();
    cJSON_AddItemToObject(args, (char*)service, cJSON_Duplicate(config_json, 1));
    return execute_transaction_internal(ctx, "config-test", service, args);
}

cJSON* kea_cmd_config_write(kea_ctrl_context_t* ctx, const char* service, const char* filename) {
    if (!ctx || !service || !filename) { if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Invalid argument."); return NULL; }
    cJSON* args = cJSON_CreateObject();
    cJSON_AddStringToObject(args, "filename", filename);
    return execute_transaction_internal(ctx, "config-write", service, args);
}

/* ========================================================================== */
/*                 3. DHCPv4 Lease & Network Management Commands              */
/* ========================================================================== */

cJSON* kea_cmd_lease4_get_by_ip(kea_ctrl_context_t* ctx, const char* ip_address) {
    if (!ctx || !ip_address) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context or IP address cannot be NULL.");
        return NULL;
    }
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create args object.");
        return NULL;
    }
    cJSON_AddStringToObject(args, "ip-address", ip_address);
    return execute_transaction_internal(ctx, "lease4-get-by-ip-address", "dhcp4", args);
}

cJSON* kea_cmd_lease4_get_by_hw_addr(kea_ctrl_context_t* ctx, const char* hw_address) {
    if (!ctx || !hw_address) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context or HW address cannot be NULL.");
        return NULL;
    }
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create args object.");
        return NULL;
    }
    cJSON_AddStringToObject(args, "hw-address", hw_address);
    return execute_transaction_internal(ctx, "lease4-get-by-hw-addr", "dhcp4", args);
}

cJSON* kea_cmd_lease4_get_by_client_id(kea_ctrl_context_t* ctx, const char* client_id) {
    if (!ctx || !client_id) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context or client ID cannot be NULL.");
        return NULL;
    }
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create args object.");
        return NULL;
    }
    cJSON_AddStringToObject(args, "client-id", client_id);
    return execute_transaction_internal(ctx, "lease4-get-by-client-id", "dhcp4", args);
}

cJSON* kea_cmd_lease4_get_all(kea_ctrl_context_t* ctx, int subnet_id) {
    if (!ctx) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context cannot be NULL.");
        return NULL;
    }
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create args object.");
        return NULL;
    }
    cJSON_AddNumberToObject(args, "subnet-id", subnet_id);
    return execute_transaction_internal(ctx, "lease4-get-all", "dhcp4", args);
}

cJSON* kea_cmd_lease4_del(kea_ctrl_context_t* ctx, const char* ip_address) {
    if (!ctx || !ip_address) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context or IP address cannot be NULL.");
        return NULL;
    }
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create args object.");
        return NULL;
    }
    cJSON_AddStringToObject(args, "ip-address", ip_address);
    return execute_transaction_internal(ctx, "lease4-del", "dhcp4", args);
}

cJSON* kea_cmd_lease4_add(kea_ctrl_context_t* ctx, const cJSON* lease_data) {
    if (!ctx || !lease_data) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context or lease data cannot be NULL.");
        return NULL;
    }
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create args object.");
        return NULL;
    }
    cJSON_AddItemToObject(args, "lease", cJSON_Duplicate(lease_data, 1));
    return execute_transaction_internal(ctx, "lease4-add", "dhcp4", args);
}

cJSON* kea_cmd_lease4_wipe(kea_ctrl_context_t* ctx, int subnet_id) {
    if (!ctx) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context cannot be NULL.");
        return NULL;
    }
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create args object.");
        return NULL;
    }
    cJSON_AddNumberToObject(args, "subnet-id", subnet_id);
    return execute_transaction_internal(ctx, "lease4-wipe", "dhcp4", args);
}

cJSON* kea_cmd_subnet4_list(kea_ctrl_context_t* ctx) {
    if (!ctx) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context cannot be NULL.");
        return NULL;
    }
    return execute_transaction_internal(ctx, "subnet4-list", "dhcp4", NULL);
}


/* ========================================================================== */
/*                 4. DHCPv6 Lease & Network Management Commands              */
/* ========================================================================== */

cJSON* kea_cmd_lease6_get_by_ip(kea_ctrl_context_t* ctx, const char* ip_address) {
    if (!ctx || !ip_address) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context or IP address cannot be NULL.");
        return NULL;
    }
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create args object.");
        return NULL;
    }
    cJSON_AddStringToObject(args, "ip-address", ip_address);
    return execute_transaction_internal(ctx, "lease6-get-by-ip-address", "dhcp6", args);
}

cJSON* kea_cmd_lease6_get_by_duid(kea_ctrl_context_t* ctx, const char* duid, int iaid) {
    if (!ctx || !duid) { // IAID can be 0, so only check DUID
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context or DUID cannot be NULL.");
        return NULL;
    }
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create args object.");
        return NULL;
    }
    cJSON_AddStringToObject(args, "duid", duid);
    cJSON_AddNumberToObject(args, "iaid", iaid);
    return execute_transaction_internal(ctx, "lease6-get", "dhcp6", args); // lease6-get takes duid+iaid
}

cJSON* kea_cmd_lease6_get_all(kea_ctrl_context_t* ctx, int subnet_id) {
    if (!ctx) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context cannot be NULL.");
        return NULL;
    }
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create args object.");
        return NULL;
    }
    cJSON_AddNumberToObject(args, "subnet-id", subnet_id);
    return execute_transaction_internal(ctx, "lease6-get-all", "dhcp6", args);
}

cJSON* kea_cmd_lease6_del(kea_ctrl_context_t* ctx, const char* ip_address) {
    if (!ctx || !ip_address) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context or IP address cannot be NULL.");
        return NULL;
    }
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create args object.");
        return NULL;
    }
    cJSON_AddStringToObject(args, "ip-address", ip_address);
    return execute_transaction_internal(ctx, "lease6-del", "dhcp6", args);
}

cJSON* kea_cmd_lease6_add(kea_ctrl_context_t* ctx, const cJSON* lease_data) {
    if (!ctx || !lease_data) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context or lease data cannot be NULL.");
        return NULL;
    }
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create args object.");
        return NULL;
    }
    cJSON_AddItemToObject(args, "lease", cJSON_Duplicate(lease_data, 1));
    return execute_transaction_internal(ctx, "lease6-add", "dhcp6", args);
}

cJSON* kea_cmd_lease6_wipe(kea_ctrl_context_t* ctx, int subnet_id) {
    if (!ctx) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context cannot be NULL.");
        return NULL;
    }
    cJSON* args = cJSON_CreateObject();
    if (!args) {
        snprintf(ctx->last_error, MAX_ERROR_SIZE, "Failed to create args object.");
        return NULL;
    }
    cJSON_AddNumberToObject(args, "subnet-id", subnet_id);
    return execute_transaction_internal(ctx, "lease6-wipe", "dhcp6", args);
}

cJSON* kea_cmd_subnet6_list(kea_ctrl_context_t* ctx) {
    if (!ctx) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context cannot be NULL.");
        return NULL;
    }
    return execute_transaction_internal(ctx, "subnet6-list", "dhcp6", NULL);
}


/* ========================================================================== */
/*                         5. Statistics Commands                             */
/* ========================================================================== */

cJSON* kea_cmd_statistic_get_all(kea_ctrl_context_t* ctx, const char* service) {
    if (!ctx || !service) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context or service cannot be NULL.");
        return NULL;
    }
    return execute_transaction_internal(ctx, "statistic-get-all", service, NULL);
}

cJSON* kea_cmd_statistic_reset_all(kea_ctrl_context_t* ctx, const char* service) {
    if (!ctx || !service) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context or service cannot be NULL.");
        return NULL;
    }
    return execute_transaction_internal(ctx, "statistic-reset-all", service, NULL);
}


/* ========================================================================== */
/*                     6. High Availability (HA) Commands                     */
/* ========================================================================== */

cJSON* kea_cmd_remote_server4_get(kea_ctrl_context_t* ctx) {
    if (!ctx) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context cannot be NULL.");
        return NULL;
    }
    return execute_transaction_internal(ctx, "remote-server4-get", "dhcp4", NULL);
}

cJSON* kea_cmd_remote_server6_get(kea_ctrl_context_t* ctx) {
    if (!ctx) {
        if (ctx) snprintf(ctx->last_error, MAX_ERROR_SIZE, "Context cannot be NULL.");
        return NULL;
    }
    return execute_transaction_internal(ctx, "remote-server6-get", "dhcp6", NULL);
}