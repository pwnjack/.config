#!/bin/bash
#
# Self-test for scripts/lib/assert.sh. It lives in test/ so it runs on every
# commit: the suites that source the library only run when their own
# directory changes, so a broken assertion could otherwise pass unnoticed.
#
# Each case runs the assertion in a subshell with its own counters and checks
# whether it passed or failed, so a failing case here is the expected outcome.
#

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"

# outcome <assertion> [args...] -> "pass" or "fail"
outcome() {
    (
        PASSED=0 FAILED=0
        "$@" >/dev/null
        [ "$FAILED" -eq 0 ] && [ "$PASSED" -eq 1 ] && echo pass || echo fail
    )
}

check() {
    local expected="$1" label="$2"
    shift 2
    assert_eq "$(outcome "$@")" "$expected" "$label"
}

json='{"a":"one","b":["x","y"]}'

check pass "assert_eq on equal values"            assert_eq same same l
check fail "assert_eq on different values"        assert_eq same other l
check pass "assert_contains finds a substring"    assert_contains "a-b-c" "b-" l
check fail "assert_contains misses"               assert_contains "a-b-c" "z" l
check pass "assert_not_contains on absence"       assert_not_contains "abc" "z" l
check fail "assert_not_contains on presence"      assert_not_contains "abc" "b" l
check pass "assert_json_field matches"            assert_json_field "$json" '.a' one l
check fail "assert_json_field mismatches"         assert_json_field "$json" '.a' two l
check pass "assert_json_contains finds"           assert_json_contains "$json" '.b | join(",")' 'x,y' l
check fail "assert_json_contains misses"          assert_json_contains "$json" '.b | join(",")' 'z' l
check pass "assert_json_lacks on absence"         assert_json_lacks "$json" '.a' zz l
check fail "assert_json_lacks on presence"        assert_json_lacks "$json" '.a' on l

summary_status=$( (PASSED=0 FAILED=1; test_summary >/dev/null) && echo 0 || echo 1)
assert_eq "$summary_status" 1 "test_summary returns nonzero after a failure"

test_summary
