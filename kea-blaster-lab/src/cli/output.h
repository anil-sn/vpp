#ifndef OUTPUT_H
#define OUTPUT_H

#include "cJSON.h"

void print_raw_json (const cJSON *response_array);
void print_pretty_version (const cJSON *response_array);
void print_pretty_generic_response (const cJSON *response_array);
void print_pretty_config (const cJSON *response_array);
void print_pretty_status (const cJSON *response_array);
void print_pretty_lease_list (const cJSON *response_array, int is_ipv6);
void print_pretty_subnet_list (const cJSON *response_array, int is_ipv6);
void print_pretty_statistics (const cJSON *response_array);
void print_pretty_simple_status (const cJSON *response_array);

#endif // OUTPUT_H