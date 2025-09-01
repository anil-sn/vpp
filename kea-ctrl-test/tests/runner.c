#include "test_main.h" // Includes all our testing macros and declarations
#include <stdio.h>

// Initialize the global counters defined in the header.
int tests_run = 0;
int tests_failed = 0;

/**
 * @brief The main function for the test suite executable.
 *
 * This program serves as the entry point for running all integration tests.
 * It calls functions from different test files, each of which is responsible
 * for running a group of related tests. Finally, it prints a summary.
 *
 * @return 0 if all tests pass, 1 if any test fails. This is important for
 *         automation and CI/CD pipelines.
 */
int main(void) {
    printf("===================================================\n");
    printf("       Running libkeactrl Integration Tests\n");
    printf("===================================================\n");
    printf("NOTE: These tests require a live Kea server running\n");
    printf("      in the Docker container.\n");
    printf("---------------------------------------------------\n\n");

    // Add and run tests from all the different test modules.
    // Each of these functions is defined in its own test_*.c file.
    add_generic_commands_tests();
    add_config_commands_tests();
    add_lease_commands_tests();
    add_stats_ha_commands_tests();

    // --- Test Summary ---
    printf("\n---------------------------------------------------\n");
    printf("                  Test Summary\n");
    printf("---------------------------------------------------\n");

    if (tests_failed == 0) {
        printf("%sPASSED:%s All %d tests passed.\n", KGRN, KNRM, tests_run);
        printf("===================================================\n");
        return 0; // Success
    } else {
        printf("%sFAILED:%s %d out of %d tests failed.\n", KRED, KNRM, tests_failed, tests_run);
        printf("===================================================\n");
        return 1; // Failure
    }
}