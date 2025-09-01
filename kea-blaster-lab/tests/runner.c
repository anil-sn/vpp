#include "test_main.h"
#include "helpers/bngblaster_api.h"
#include <stdio.h>

int tests_run = 0;
int tests_failed = 0;

// Forcefully clean up all existing BNG Blaster instances and their lock files.
static void pre_test_cleanup (void)
{
    printf ("--- Pre-Test Cleanup: Removing all stale BNG Blaster instances and locks ---\n");

    // Forcefully remove any stale lock files to prevent instance start failures.
    system ("rm -f /run/lock/bngblaster_* 2>/dev/null");
    printf ("  - Stale lock files removed.\n");

    bngblaster_ctx_t *ctx = bngblaster_init ("127.0.0.1", 8001);
    if (!ctx) {
        printf ("  [WARN] Could not connect to BNG Blaster controller for API cleanup.\n");
        return;
    }

    // Use system calls for a robust, one-off cleanup of all instances via the API.
    system ("curl -s -X GET http://127.0.0.1:8001/api/v1/instances | jq -r '.[]' | xargs -I {} curl -s -X POST http://127.0.0.1:8001/api/v1/instances/{}/_stop > /dev/null 2>&1");
    sleep (2); // Wait for instances to stop
    system ("curl -s -X GET http://127.0.0.1:8001/api/v1/instances | jq -r '.[]' | xargs -I {} curl -s -X DELETE http://127.0.0.1:8001/api/v1/instances/{} > /dev/null 2>&1");

    bngblaster_free (ctx);
    printf ("--- Cleanup Complete ---\n\n");
}

int main (void)
{
    printf ("===================================================\n");
    printf ("       Running libkeactrl Integration Tests\n");
    printf ("===================================================\n");
    printf ("NOTE: These tests require a live Kea lab environment.\n");
    printf ("---------------------------------------------------\n\n");

    // Run suites that DON'T use BNG Blaster first.
    run_generic_commands_tests();
    run_config_commands_tests();
    run_subnet_commands_tests();

    // Enforce a clean state before each suite that uses the BNG Blaster.
    pre_test_cleanup();
    run_lease_commands_tests();

    // FIX: Add a pause to let the OS fully clean up resources from the previous bngblaster process.
    printf ("\n--- Pausing for 3 seconds to allow OS resource cleanup ---\n\n");
    sleep (3);

    pre_test_cleanup();
    run_stat_commands_tests();

    printf ("\n---------------------------------------------------\n");
    printf ("                  Test Summary\n");
    printf ("---------------------------------------------------\n");

    if (tests_failed == 0) {
        printf ("%sPASSED:%s All %d tests passed.\n", KGRN, KNRM, tests_run);
        printf ("===================================================\n");
        return 0;
    } else {
        printf ("%sFAILED:%s %d out of %d tests failed.\n", KRED, KNRM, tests_failed, tests_run);
        printf ("===================================================\n");
        return 1;
    }
}