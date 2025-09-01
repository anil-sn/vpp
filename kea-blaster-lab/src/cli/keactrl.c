#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

#include "keactrl.h" // The public API of our library
#include "output.h"  // CLI-specific output formatters

static void print_full_help()
{
    printf ("Usage: keactrl [options] <command> [arguments...]\n\n");
    printf ("A command-line tool for interacting with the Kea Control Agent REST API.\n\n");
    printf ("Options:\n");
    printf ("  --json     Output the raw JSON 'arguments' payload from the response.\n\n");

    printf ("Supported Commands:\n");
    printf ("  list-commands <service>\n");
    printf ("  version-get [service...]\n");
    printf ("  status-get <service>\n");
    printf ("  config-get <service>\n");
    printf ("  subnet4-list\n");
    printf ("  subnet6-list\n");
    printf ("  lease4-get-by-ip <ip-address>\n");
    printf ("  statistic-get-all <service>\n");
    printf ("  cache-get <service>\n");
    printf ("  cache-size <service>\n");
    printf ("  cache-clear <service>\n");
}

static void print_command_usage (const char *command, const char *usage)
{
    fprintf (stderr, "Usage: keactrl %s %s\n", command, usage);
}

int main (int argc, char **argv)
{
    if (argc < 2 || strcmp (argv[1], "help") == 0 || strcmp (argv[1], "--help") == 0) {
        print_full_help();
        return 0;
    }

    bool raw_json_output = false;
    int command_index = 1;

    for (int i = 1; i < argc; ++i) {
        if (strcmp (argv[i], "--json") == 0) {
            raw_json_output = true;
            for (int j = i; j < argc - 1; ++j) {
                argv[j] = argv[j + 1];
            }
            argc--;
            i--;
        }
    }

    if (argc < 2) {
        print_full_help();
        return 1;
    }

    const char *command = argv[command_index];
    int exit_code = 0;
    cJSON *result_json = NULL;

    kea_ctrl_context_t ctx = kea_ctrl_create (NULL);
    if (!ctx) {
        fprintf (stderr, "Error: Failed to initialize Kea control library.\n");
        return 1;
    }

    // --- Command Dispatcher ---
    if (strcmp (command, "list-commands") == 0) {
        if (argc < 3) {
            print_command_usage (command, "<service>");
            exit_code = 1;
        } else {
            result_json = kea_cmd_list_commands (ctx, argv[2]);
        }
    } else if (strcmp (command, "version-get") == 0) {
        const char **services = (argc > 2) ? (const char **) &argv[2] : NULL;
        result_json = kea_cmd_version_get (ctx, services);
    } else if (strcmp (command, "status-get") == 0) {
        if (argc < 3) {
            print_command_usage (command, "<service>");
            exit_code = 1;
        } else {
            result_json = kea_cmd_status_get (ctx, argv[2]);
        }
    } else if (strcmp (command, "config-get") == 0) {
        if (argc < 3) {
            print_command_usage (command, "<service>");
            exit_code = 1;
        } else {
            result_json = kea_cmd_config_get (ctx, argv[2]);
        }
    } else if (strcmp (command, "subnet4-list") == 0) {
        result_json = kea_cmd_subnet4_list (ctx);
    } else if (strcmp (command, "subnet6-list") == 0) {
        result_json = kea_cmd_subnet6_list (ctx);
    } else if (strcmp (command, "lease4-get-by-ip") == 0) {
        if (argc < 3) {
            print_command_usage (command, "<ip-address>");
            exit_code = 1;
        } else {
            result_json = kea_cmd_lease4_get_by_ip (ctx, argv[2]);
        }
    } else if (strcmp (command, "statistic-get-all") == 0) {
        if (argc < 3) {
            print_command_usage (command, "<service>");
            exit_code = 1;
        } else {
            result_json = kea_cmd_statistic_get_all (ctx, argv[2]);
        }
    } else if (strcmp (command, "cache-get") == 0) {
        if (argc < 3) {
            print_command_usage (command, "<service>");
            exit_code = 1;
        } else {
            result_json = kea_cmd_cache_get (ctx, argv[2]);
        }
    } else if (strcmp (command, "cache-size") == 0) {
        if (argc < 3) {
            print_command_usage (command, "<service>");
            exit_code = 1;
        } else {
            result_json = kea_cmd_cache_size (ctx, argv[2]);
        }
    } else if (strcmp (command, "cache-clear") == 0) {
        if (argc < 3) {
            print_command_usage (command, "<service>");
            exit_code = 1;
        } else {
            result_json = kea_cmd_cache_clear (ctx, argv[2]);
        }
    } else {
        fprintf (stderr, "Error: Unknown command '%s'\n", command);
        print_full_help();
        exit_code = 1;
    }

    // --- Result Handling ---
    if (exit_code == 0) {
        if (!result_json) {
            fprintf (stderr, "Error: %s\n", kea_ctrl_get_last_error (ctx));
            exit_code = 1;
        } else {
            if (raw_json_output) {
                print_raw_json (result_json);
            } else {
                if (strcmp (command, "version-get") == 0) {
                    print_pretty_version (result_json);
                } else if (strcmp (command, "config-get") == 0) {
                    print_pretty_config (result_json);
                } else if (strcmp (command, "status-get") == 0) {
                    print_pretty_status (result_json);
                } else if (strcmp (command, "subnet4-list") == 0 || strcmp (command, "subnet6-list") == 0) {
                    print_pretty_subnet_list (result_json, strcmp (command, "subnet6-list") == 0);
                } else if (strcmp (command, "lease4-get-by-ip") == 0) {
                    print_pretty_lease_list (result_json, false);
                } else if (strcmp (command, "statistic-get-all") == 0) {
                    print_pretty_statistics (result_json);
                } else if (strcmp (command, "cache-clear") == 0) {
                    print_pretty_simple_status (result_json);
                } else {
                    print_pretty_generic_response (result_json);
                }
            }
        }
    }

    cJSON_Delete (result_json);
    kea_ctrl_destroy (ctx);

    return exit_code;
}