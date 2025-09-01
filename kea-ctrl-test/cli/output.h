#ifndef OUTPUT_H
#define OUTPUT_H

#include "cJSON.h"

// The generic JSON printer (useful for debugging or for --json flag)
void print_raw_json(const cJSON* json);

// Specific pretty-printer for the 'version-get' command
void print_pretty_version(const cJSON* version_json);

// Specific pretty-printer for the 'config-get' command
void print_pretty_config(const cJSON* config_json);


#endif // OUTPUT_H