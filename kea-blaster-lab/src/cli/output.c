#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <string.h>
#include "cJSON.h"
#include "output.h"

// Helper to safely get a string value from a cJSON object
static const char *get_string (const cJSON *obj, const char *key)
{
    const cJSON *item = cJSON_GetObjectItem (obj, key);
    return cJSON_IsString (item) ? item->valuestring : "N/A";
}

// Helper to safely get an integer value from a cJSON object
static int get_int (const cJSON *obj, const char *key)
{
    const cJSON *item = cJSON_GetObjectItem (obj, key);
    return cJSON_IsNumber (item) ? item->valueint : 0;
}

void print_raw_json (const cJSON *response_array)
{
    if (!response_array) {
        return;
    }
    cJSON *first_result = cJSON_GetArrayItem (response_array, 0);
    if (!first_result) {
        return;
    }

    cJSON *arguments = cJSON_GetObjectItem (first_result, "arguments");
    if (!arguments) {
        return;
    }

    char *raw_str = cJSON_PrintUnformatted (arguments);
    if (raw_str) {
        printf ("%s\n", raw_str);
        free (raw_str);
    }
}

void print_pretty_version (const cJSON *response_array)
{
    if (!response_array) {
        return;
    }
    printf ("================================================================================\n");
    printf (" Service          | Version          | Extended Version\n");
    printf ("--------------------------------------------------------------------------------\n");

    cJSON *result_obj = cJSON_GetArrayItem (response_array, 0);
    if (!result_obj) {
        return;
    }

    const cJSON *arguments = cJSON_GetObjectItem (result_obj, "arguments");
    if (!arguments) {
        return;
    }

    if (cJSON_IsArray (arguments)) {
        cJSON *service_info = NULL;
        cJSON_ArrayForEach (service_info, arguments) {
            const char *service_str = get_string (service_info, "service");
            const cJSON *nested_args = cJSON_GetObjectItem (service_info, "arguments");
            const char *version_str = "ERROR";
            const char *extended_str = get_string (service_info, "text");

            cJSON *result_code = cJSON_GetObjectItem (service_info, "result");
            if (result_code && result_code->valueint == 0) {
                version_str = get_string (nested_args, "version");
                extended_str = get_string (nested_args, "extended");
            }
            printf (" %-16s | %-16s | %s\n", service_str, version_str, extended_str);
        }
    } else if (cJSON_IsObject (arguments)) { // Single service call (or ctrl-agent)
        const char *version_str = get_string (arguments, "version");
        const char *extended_str = get_string (arguments, "extended");
        printf (" %-16s | %-16s | %s\n", "ctrl-agent", version_str, extended_str);
    }

    printf ("================================================================================\n");
}

void print_pretty_generic_response (const cJSON *response_array)
{
    if (!response_array) {
        return;
    }
    char *pretty_str = cJSON_Print (response_array);
    if (pretty_str) {
        printf ("%s\n", pretty_str);
        free (pretty_str);
    }
}

void print_pretty_config (const cJSON *response_array)
{
    if (!response_array) {
        return;
    }
    cJSON *result_obj = cJSON_GetArrayItem (response_array, 0);
    if (!result_obj) {
        return;
    }

    cJSON *arguments = cJSON_GetObjectItem (result_obj, "arguments");
    if (!arguments || !arguments->child) {
        print_pretty_generic_response (response_array);
        return;
    }
    char *pretty_str = cJSON_Print (arguments->child);
    if (pretty_str) {
        printf ("%s\n", pretty_str);
        free (pretty_str);
    }
}

void print_pretty_status (const cJSON *response_array)
{
    if (!response_array) {
        return;
    }
    cJSON *result_obj = cJSON_GetArrayItem (response_array, 0);
    if (!result_obj) {
        return;
    }

    const cJSON *args = cJSON_GetObjectItem (result_obj, "arguments");
    if (!cJSON_IsObject (args)) {
        return;
    }

    printf ("----------------------------------------\n");
    printf ("           Service Status\n");
    printf ("----------------------------------------\n");
    printf ("  PID: %d\n", get_int (args, "pid"));
    printf ("  Uptime (seconds): %d\n", get_int (args, "uptime"));
    printf ("----------------------------------------\n");
}

void print_pretty_lease_list (const cJSON *response_array, int is_ipv6)
{
    if (!response_array) {
        return;
    }
    cJSON *result_obj = cJSON_GetArrayItem (response_array, 0);
    if (!result_obj) {
        return;
    }

    const cJSON *arguments = cJSON_GetObjectItem (result_obj, "arguments");
    if (!cJSON_IsObject (arguments)) {
        return;
    }

    const cJSON *leases_array = cJSON_GetObjectItem (arguments, "leases");
    if (!cJSON_IsArray (leases_array)) {
        return;
    }

    printf ("================================================================================================\n");
    printf (" %-16s | %-18s | %-38s | %-8s | %s\n", "IP Address", "HW Address", "Client ID", "SubnetID", "Hostname");
    printf ("------------------------------------------------------------------------------------------------\n");

    const cJSON *lease = NULL;
    cJSON_ArrayForEach (lease, leases_array) {
        printf (" %-16s | %-18s | %-38s | %-8d | %s\n",
                        get_string (lease, "ip-address"), get_string (lease, "hw-address"),
                        get_string (lease, "client-id"), get_int (lease, "subnet-id"), get_string (lease, "hostname"));
    }
    printf ("================================================================================================\n");
}

void print_pretty_subnet_list (const cJSON *response_array, int is_ipv6)
{
    if (!response_array) {
        return;
    }
    cJSON *result_obj = cJSON_GetArrayItem (response_array, 0);
    if (!result_obj) {
        return;
    }

    const cJSON *arguments = cJSON_GetObjectItem (result_obj, "arguments");
    if (!cJSON_IsObject (arguments)) {
        return;
    }

    const cJSON *subnets_array = cJSON_GetObjectItem (arguments, "subnets");
    if (!cJSON_IsArray (subnets_array)) {
        return;
    }

    printf ("==========================================================================\n");
    printf (" %-8s | %-45s | %s\n", "ID", "Subnet", "Pools");
    printf ("--------------------------------------------------------------------------\n");

    const cJSON *subnet = NULL;
    cJSON_ArrayForEach (subnet, subnets_array) {
        const cJSON *pools_array = cJSON_GetObjectItem (subnet, "pools");
        char pools_str[128] = "N/A";
        if (cJSON_IsArray (pools_array) && cJSON_GetArraySize (pools_array) > 0) {
            cJSON *first_pool = cJSON_GetArrayItem (pools_array, 0);
            strncpy (pools_str, get_string (first_pool, "pool"), sizeof (pools_str) - 1);
        }
        printf (" %-8d | %-45s | %s\n", get_int (subnet, "id"), get_string (subnet, "subnet"), pools_str);
    }
    printf ("==========================================================================\n");
}

void print_pretty_statistics (const cJSON *response_array)
{
    if (!response_array) {
        return;
    }
    cJSON *result_obj = cJSON_GetArrayItem (response_array, 0);
    if (!result_obj) {
        return;
    }

    const cJSON *stats_map = cJSON_GetObjectItem (result_obj, "arguments");
    if (!cJSON_IsObject (stats_map)) {
        printf ("%s\n", get_string (result_obj, "text"));
        return;
    }

    printf ("================================================================================\n");
    printf (" %-35s | %-15s | %s\n", "Statistic Name", "Value", "Timestamp");
    printf ("--------------------------------------------------------------------------------\n");

    const cJSON *stat_item = stats_map->child;
    while (stat_item) {
        const char *name = stat_item->string;
        const cJSON *value_array_wrapper = cJSON_GetArrayItem (stat_item, 0);

        if (cJSON_IsArray (value_array_wrapper) && cJSON_GetArraySize (value_array_wrapper) >= 2) {
            const cJSON *count = cJSON_GetArrayItem (value_array_wrapper, 0);
            const cJSON *ts = cJSON_GetArrayItem (value_array_wrapper, 1);
            if (cJSON_IsNumber (count) && cJSON_IsString (ts)) {
                printf (" %-35s | %-15" PRId64 " | %s\n", name, (int64_t) count->valuedouble, ts->valuestring);
            }
        }
        stat_item = stat_item->next;
    }
    printf ("================================================================================\n");
}

void print_pretty_simple_status (const cJSON *response_array)
{
    if (!response_array) {
        return;
    }
    cJSON *result_obj = cJSON_GetArrayItem (response_array, 0);
    if (!result_obj) {
        return;
    }

    printf ("%s\n", get_string (result_obj, "text"));
}