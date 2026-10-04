#include "check.h"

int main(void)
{
    CHECK(1 + 1 == 2, "arithmetic");
    return check_done("test_smoke");
}
