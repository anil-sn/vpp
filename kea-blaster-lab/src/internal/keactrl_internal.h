#ifndef KEACTRL_INTERNAL_H
#define KEACTRL_INTERNAL_H

#include <ctype.h>
#include <string.h>
#include <stdbool.h>
#include <curl/curl.h>
#include "keactrl.h" // Includes the public API

#define MAX_ERROR_SIZE 256

/**
 * @brief Buffer structure for handling libcurl HTTP response bodies.
 */
typedef struct {
    char *memory;
    size_t size;
} http_response_buffer_t;

/**
 * @brief The internal, private definition of the Kea control context struct.
 *
 * This struct holds all state for libcurl-based communication, including the
 * cURL handle, error buffers, and response data. It is intentionally opaque
 * to the users of the public API.
 */
struct kea_ctrl_context_s {
    CURL *curl_handle;
    char last_error[MAX_ERROR_SIZE];
    http_response_buffer_t response_buffer;
    struct curl_slist *headers;
};

/**
 * @brief The internal workhorse function that executes all Kea API transactions.
 *
 * This function handles the construction of the JSON-RPC request, executes the
 * HTTP POST request via libcurl, and performs initial validation on the
 * response (HTTP status code, basic JSON structure, and Kea result code).
 *
 * @param ctx The library context.
 * @param command The Kea API command name (e.g., "config-get").
 * @param services An optional NULL-terminated array of service names to target
 *                 (e.g., {"dhcp4", "dhcp6", NULL}). If NULL, the command is
 *                 sent directly to the control agent.
 * @param args An optional cJSON object containing the "arguments" for the command.
 *             This function takes ownership of the object and will free it.
 * @return A cJSON array representing the successful response from the Kea server,
 *         or NULL on any failure (network, HTTP, API error, or JSON parsing).
 *         The caller is responsible for freeing the returned cJSON object.
 */
cJSON *execute_transaction_internal (kea_ctrl_context_t ctx,
                const char *command,
                const char **services,
                cJSON *args);

#endif // KEACTRL_INTERNAL_H