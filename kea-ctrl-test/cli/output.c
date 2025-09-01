#include <stdio.h>
#include <stdlib.h>
#include "cJSON.h"
#include "output.h"

void print_raw_json(const cJSON* json) {
    if (!json) return;
    char* raw_str = cJSON_PrintUnformatted(json); // Use unformatted for raw output
    if (raw_str) {
        printf("%s\n", raw_str);
        free(raw_str);
    }
}

/**
 * @brief Pretty-prints the JSON response from a 'version-get' command.
 */
void print_pretty_version(const cJSON* version_json) {
    if (!version_json) {
        fprintf(stderr, "Error: Invalid data (NULL) passed to version printer.\n");
        return;
    }

    printf("=================================================================================================\n");
    printf(" %-15s | %-15s | %s\n", "Service", "Version", "Extended Version");
    printf("-------------------------------------------------------------------------------------------------\n");

    if (cJSON_IsArray(version_json)) {
        const cJSON* service_info = NULL;
        cJSON_ArrayForEach(service_info, version_json) {
            if (cJSON_IsObject(service_info)) {
                const cJSON* service = cJSON_GetObjectItemCaseSensitive(service_info, "service");
                const cJSON* version = cJSON_GetObjectItemCaseSensitive(service_info, "version");
                const cJSON* extended = cJSON_GetObjectItemCaseSensitive(service_info, "extended-version");

                printf(" %-15s | %-15s | %s\n",
                       cJSON_IsString(service) ? service->valuestring : "N/A",
                       cJSON_IsString(version) ? version->valuestring : "N/A",
                       cJSON_IsString(extended) ? extended->valuestring : "N/A");
            }
        }
    } else if (cJSON_IsObject(version_json)) {
        const cJSON* extended = cJSON_GetObjectItemCaseSensitive(version_json, "extended");
        printf(" %-15s | %-15s | %s\n",
               "ctrl-agent", "3.0.0",
               cJSON_IsString(extended) ? extended->valuestring : "N/A");
    } else {
        fprintf(stderr, "Error: Unexpected JSON type in version response.\n");
        print_raw_json(version_json);
    }

    printf("=================================================================================================\n");
}

/**
 * @brief Pretty-prints the JSON response from a 'config-get' command.
 *
 * For configuration, a "pretty" print is simply a well-formatted,
 * indented JSON string.
 *
 * @param config_json The cJSON object returned by kea_cmd_config_get.
 */
void print_pretty_config(const cJSON* config_json) {
    if (!config_json) {
        fprintf(stderr, "Error: Invalid data (NULL) passed to config printer.\n");
        return;
    }

    // cJSON_Print() creates a formatted string with indentation.
    char* pretty_str = cJSON_Print(config_json);
    if (pretty_str) {
        printf("%s\n", pretty_str);
        free(pretty_str);
    } else {
        fprintf(stderr, "Error: Failed to format configuration JSON to string.\n");
    }
}