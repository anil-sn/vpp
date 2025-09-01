#ifndef LIBKEACTRL_INTERNAL_H
#define LIBKEACTRL_INTERNAL_H

#include "libkeactrl.h" // Includes the public typedef
#include <ctype.h>
#include <curl/curl.h>

#define KEA_API

struct kea_ctrl_context_s {
    CURL *curl_handle;
    char last_error[256];
    struct {
        char *memory;
        size_t size;
    } response_buffer;
    struct curl_slist *headers;
};

/**
 * @brief The internal workhorse function that executes all Kea API transactions.
 *
 * Defined in libkeactrl_core.c.
 *
 * @param ctx The library context.
 * @param command The Kea API command string.
 * @param service The target service string.
 * @param args A cJSON object containing the command's arguments. Ownership
 *             is transferred to this function.
 * @return A cJSON object containing the "arguments" from the Kea response,
 *         or NULL on failure.
 */
cJSON* execute_transaction_internal(kea_ctrl_context_t ctx,
                                      const char* command,
                                      const char* service,
                                      cJSON* args);


#endif // LIBKEACTRL_INTERNAL_H