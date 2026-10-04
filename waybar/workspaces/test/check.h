/* Minimal assertion harness for the module's C tests. Each test binary
 * includes this once, calls CHECK*, and returns check_done(). */
#pragma once
#include <math.h>
#include <stdio.h>

static int check_failures, check_count;

#define CHECK(cond, ...)                                                   \
    do {                                                                   \
        check_count++;                                                     \
        if (!(cond)) {                                                     \
            check_failures++;                                              \
            fprintf(stderr, "  FAIL %s:%d: ", __FILE__, __LINE__);         \
            fprintf(stderr, __VA_ARGS__);                                  \
            fputc('\n', stderr);                                           \
        }                                                                  \
    } while (0)

#define CHECK_NEAR(a, b, eps, ...) \
    CHECK(fabs((double)(a) - (double)(b)) <= (eps), __VA_ARGS__)

static inline int check_done(const char *name)
{
    if (check_failures) {
        fprintf(stderr, "%s: %d of %d checks failed\n", name, check_failures, check_count);
        return 1;
    }
    printf("%s: %d checks passed\n", name, check_count);
    return 0;
}
