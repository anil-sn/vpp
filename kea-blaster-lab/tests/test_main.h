#ifndef TEST_MAIN_H
#define TEST_MAIN_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <unistd.h>
#include "keactrl.h"

#define KGRN "\x1B[32m"
#define KRED "\x1B[31m"
#define KNRM "\x1B[0m"

extern int tests_run;
extern int tests_failed;

#define TEST_CASE(name) static void name(void)

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

#define ASSERT_TRUE(cond, msg) do { \
        if (!(cond)) { \
            printf("\r  [%sFAIL%s] %s\n       at %s:%d\n       Assertion failed: %s\n", \
                            KRED, KNRM, __func__, __FILE__, __LINE__, msg); \
            tests_failed++; \
            goto cleanup; \
        } \
    } while (0)

#define ASSERT_NOT_NULL(ptr, msg) ASSERT_TRUE((ptr) != NULL, msg)
#define ASSERT_NULL(ptr, msg) ASSERT_TRUE((ptr) == NULL, msg)

#define ASSERT_KEA_API_OK(json_ptr, ctx) do { \
        if (!(json_ptr)) { \
            printf("\r  [%sFAIL%s] %s\n       at %s:%d\n       Kea API call failed: %s\n", \
                            KRED, KNRM, __func__, __FILE__, __LINE__, kea_ctrl_get_last_error(ctx)); \
            tests_failed++; \
            goto cleanup; \
        } \
    } while (0)

#define ASSERT_BNG_OK(err, ctx, msg) do { \
        if ((err) != BBERR_OK) { \
            printf("\r  [%sFAIL%s] %s\n       at %s:%d\n       %s\n       API Error: %s\n", \
                            KRED, KNRM, __func__, __FILE__, __LINE__, msg, bngblaster_get_last_error(ctx)); \
            tests_failed++; \
            goto cleanup; \
        } \
    } while (0)

#define ASSERT_INT_EQ(actual, expected) do { \
        if ((actual) != (expected)) { \
            printf("\r  [%sFAIL%s] %s\n       at %s:%d\n       Assertion failed: integers are not equal.\n" \
                            "         Expected: %d\n" \
                            "         Actual  : %d\n", \
                            KRED, KNRM, __func__, __FILE__, __LINE__, (expected), (actual)); \
            tests_failed++; \
            goto cleanup; \
        } \
    } while (0)

#define ASSERT_INT_EQ_MSG(actual, expected, fmt, ...) do { \
        if ((actual) != (expected)) { \
            printf("\r  [%sFAIL%s] %s\n       at %s:%d\n       Assertion failed: integers are not equal.\n" \
                            "         Expected: %d\n" \
                            "         Actual  : %d\n", \
                            KRED, KNRM, __func__, __FILE__, __LINE__, (expected), (actual)); \
            printf("       Message: " fmt "\n", ##__VA_ARGS__); \
            tests_failed++; \
            goto cleanup; \
        } \
    } while (0)

#define ASSERT_JSON_TYPE(obj, type_check_fn) do { \
        if (!(type_check_fn(obj))) { \
            printf("\r  [%sFAIL%s] %s\n       at %s:%d\n       Assertion failed: JSON item has incorrect type.\n", \
                            KRED, KNRM, __func__, __FILE__, __LINE__); \
            tests_failed++; \
            goto cleanup; \
        } \
    } while (0)

void run_generic_commands_tests (void);
void run_config_commands_tests (void);
void run_lease_commands_tests (void);
void run_subnet_commands_tests (void);
void run_stat_commands_tests (void);

#endif // TEST_MAIN_H