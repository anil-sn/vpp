#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "libkeactrl.h"
#include "output.h"

void print_usage() {
    fprintf(stderr, "Usage: keactl <command> [args...]\n");
    fprintf(stderr, "\nCommands:\n");
    fprintf(stderr, "  version-get              Get version information for all Kea services.\n");
    fprintf(stderr, "  config-get <service>     Get the current configuration for a service (e.g., dhcp4).\n");
}

int main(int argc, char **argv) {
    if (argc < 2) {
        print_usage();
        return 1;
    }

    const char* command = argv[1];

    // The return type of kea_ctrl_create is now kea_ctrl_context_t, which is a pointer.
    kea_ctrl_context_t ctx = kea_ctrl_create(NULL);
    if (!ctx) {
        fprintf(stderr, "Error: Failed to initialize Kea control library.\n");
        return 1;
    }

    int exit_code = 0;
    cJSON* result = NULL;

    // --- version-get ---
    if (strcmp(command, "version-get") == 0) {
        printf("Requesting version information...\n");
        result = kea_cmd_version_get(ctx, NULL); // Pass ctx directly
        if (!result) {
            fprintf(stderr, "Error: %s\n", kea_ctrl_get_last_error(ctx));
            exit_code = 1;
        } else {
            print_pretty_version(result);
        }
    }
    // --- config-get ---
    else if (strcmp(command, "config-get") == 0) {
        if (argc < 3) {
            fprintf(stderr, "Error: 'config-get' requires a service name.\n");
            print_usage();
            exit_code = 1;
        } else {
            const char* service = argv[2];
            printf("Requesting configuration for service '%s'...\n", service);
            result = kea_cmd_config_get(ctx, service); // Pass ctx directly
            if (!result) {
                fprintf(stderr, "Error: %s\n", kea_ctrl_get_last_error(ctx));
                exit_code = 1;
            } else {
                print_pretty_config(result);
            }
        }
    }
    else {
        fprintf(stderr, "Error: Unknown command '%s'\n", command);
        print_usage();
        exit_code = 1;
    }

    // --- Cleanup ---
    cJSON_Delete(result);
    kea_ctrl_destroy(ctx); // Pass ctx directly
    
    return exit_code;
}