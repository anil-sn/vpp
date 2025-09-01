#ifndef CONFIG_HELPER_H
#define CONFIG_HELPER_H

#include <stdbool.h>
#include "keactrl.h"

bool apply_kea_config_from_string (kea_ctrl_context_t ctx, const char *service, const char *config_json_string);
bool apply_kea_config_from_json (kea_ctrl_context_t ctx, const char *service, const cJSON *config_json);

#endif // CONFIG_HELPER_H