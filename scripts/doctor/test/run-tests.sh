#!/bin/bash
#
# Dependency-free test harness for the doctor checks.
# Sources every test-*.sh in this directory and reports assertion results.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR_DIR="$(dirname "$TEST_DIR")"
REPO_DIR="$(dirname "$(dirname "$DOCTOR_DIR")")"
export DOCTOR_DIR REPO_DIR

TESTS_PASSED=0
TESTS_FAILED=0
FILES_RUN=0

# assert_contains <haystack> <needle> <label>
assert_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ok   $3"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL $3"
        echo "       expected to contain: $2"
        echo "       actual output:"
        printf '%s\n' "$1" | sed 's/^/         /'
    fi
}

# assert_not_contains <haystack> <needle> <label>
assert_not_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL $3"
        echo "       expected NOT to contain: $2"
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ok   $3"
    fi
}

# assert_eq <actual> <expected> <label>
assert_eq() {
    if [ "$1" = "$2" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ok   $3"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL $3"
        echo "       expected: $2"
        echo "       actual:   $1"
    fi
}

# make_fixture -> prints path to a fresh git repo in a temp dir
make_fixture() {
    local dir
    dir="$(mktemp -d)"
    git -C "$dir" init -q
    git -C "$dir" config user.email "test@test"
    git -C "$dir" config user.name "test"
    printf '%s' "$dir"
}

FIXTURES=()
cleanup_fixtures() {
    local f
    for f in "${FIXTURES[@]:-}"; do
        [ -n "$f" ] && [ -d "$f" ] && rm -rf "$f"
    done
}
trap cleanup_fixtures EXIT

for test_file in "$TEST_DIR"/test-*.sh; do
    [ -e "$test_file" ] || continue
    FILES_RUN=$((FILES_RUN + 1))
    echo "▸ $(basename "$test_file")"
    # shellcheck source=/dev/null
    source "$test_file"
done

echo
echo "$FILES_RUN files, $((TESTS_PASSED + TESTS_FAILED)) assertions, $TESTS_FAILED failures"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
exit 0
