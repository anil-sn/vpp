#ifndef TEST_MAIN_H
#define TEST_MAIN_H

#include <stdio.h>
#include <stdlib.h>

#include "libkeactrl.h" // All tests need access to the library API

/* ========================================================================== */
/*                            Test Runner Macros                              */
/* ========================================================================== */

// Color codes for pretty printing test results
#define KGRN "\x1B[32m"
#define KRED "\x1B[31m"
#define KNRM "\x1B[0m"

// Global counters for test statistics
extern int tests_run;
extern int tests_failed;

// A function pointer type that represents a single test case
typedef void (*test_case_func)(void);

/**
 * @brief Defines a test case function.
 * This macro simply provides a standard way to declare a test.
 */
#define TEST_CASE(name) void name(void)

/**
 * @brief Runs a test case and prints the result.
 * It increments the global counters.
 */
#define RUN_TEST(test) do { \
    printf("  Running: %s...", #test); \
    fflush(stdout); \
    int failures_before = tests_failed; \
    test(); \
    if (tests_failed == failures_before) { \
        printf("\r  [%sPASS%s] %s\n", KGRN, KNRM, #test); \
    } \
    tests_run++; \
} while (0)

/* ========================================================================== */
/*                             Assertion Macros                               */
/* ========================================================================== */

/**
 * @brief Core assertion macro. Checks a condition and reports failure if it's false.
 */
#define ASSERT_TRUE(cond) do { \
    if (!(cond)) { \
        printf("\r  [%sFAIL%s] %s\n       at %s:%d\n       Assertion failed: (%s)\n", \
               KRED, KNRM, __func__, __FILE__, __LINE__, #cond); \
        tests_failed++; \
        return; /* Stop the current test case on first failure */ \
    } \
} while (0)

/**
 * @brief Asserts that a condition is false.
 */
#define ASSERT_FALSE(cond) ASSERT_TRUE(!(cond))

/**
 * @brief Asserts that a pointer is not NULL.
 */
#define ASSERT_NOT_NULL(ptr) ASSERT_TRUE((ptr) != NULL)

/**
 * @brief Asserts that a pointer is NULL.
 */
#define ASSERT_NULL(ptr) ASSERT_TRUE((ptr) == NULL)

/**
 * @brief Asserts that two integers are equal.
 */
#define ASSERT_INT_EQ(a, b) do { \
    if ((a) != (b)) { \
        printf("\r  [%sFAIL%s] %s\n       at %s:%d\n       Assertion failed: %d != %d\n", \
               KRED, KNRM, __func__, __FILE__, __LINE__, (a), (b)); \
        tests_failed++; \
        return; \
    } \
} while (0)

/**
 * @brief Asserts that two strings are equal.
 */
#define ASSERT_STR_EQ(a, b) do { \
    if (strcmp((a), (b)) != 0) { \
        printf("\r  [%sFAIL%s] %s\n       at %s:%d\n       Assertion failed: \"%s\" != \"%s\"\n", \
               KRED, KNRM, __func__, __FILE__, __LINE__, (a), (b)); \
        tests_failed++; \
        return; \
    } \
} while (0)


/* ========================================================================== */
/*                     Test Suite Function Prototypes                         */
/* ========================================================================== */

// Each file containing tests will have a function like this, which
// the main test runner will call.
void add_generic_commands_tests(void);
void add_config_commands_tests(void);
void add_lease_commands_tests(void);
void add_stats_ha_commands_tests(void);


#endif // TEST_MAIN_H