#!/bin/bash
#
# Dotfiles test runner
# Runs the repo's test suites -- all of them, or only those covering a path.
#
# Usage: ./test.sh [--list] [--for PATH...]
#
#   (no args)      run every discovered suite
#   --for PATH...  run only the suites whose owning directory covers a PATH.
#                  Paths are repo-relative, as git and git diff report them.
#   --list         print each suite and its owning directory, run nothing
#
# Exits 0 if every suite passed, 1 if any failed or the root is not a git
# repository, 2 on a usage error.
#
# A suite is DISCOVERED, never listed. A tracked file is a suite entry point if
# its basename is run-tests.sh, or it matches test-*.sh and its directory holds
# no run-tests.sh. The second clause is load-bearing: it keeps the doctor's
# sourced fragments out, which expect a harness around them and fail if run
# alone. A third suite in either style is covered the moment it is committed.
#
# Suites are invoked as `bash <path>`, so discovery depends on neither the exec
# bit nor shebang variance. The only contract with a suite is that it runs
# under bash and exits non-zero on failure. Both existing suites already do.
#
# A suite's OWNING DIRECTORY is its own directory with a trailing test/
# component stripped, so scripts/doctor/test/run-tests.sh covers
# scripts/doctor/ and scripts/waybar/test-battery.sh covers scripts/waybar/.
# A suite directly under a top-level test/ maps to the empty prefix and so
# covers the whole tree -- which is how this file's own tests run when test.sh
# itself changes. This mapping lives here and nowhere else; the pre-commit hook
# passes staged paths to --for rather than deciding for itself.
#
# Output is CAPTURED, not streamed: the doctor's suite alone emits 222 lines,
# and printing that on every commit is how a gate gets ignored. A failing
# suite's output is printed in full, so diagnosing one needs no second command.
#
# Deliberately NOT `set -e`, for the same reason doctor.sh is not: one failing
# suite must not abort the run, or the roll-up would only ever name the first.
set -uo pipefail

TEST_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default to the tree this script lives in, so a clone anywhere works without
# configuration. Overridable so this runner's own tests can point discovery at
# a fixture repo -- the same seam as DOCTOR_ROOT and BATTERY_SYSFS.
TEST_ROOT="${TEST_ROOT:-$TEST_SELF_DIR}"

TEST_GREEN='\033[0;32m'
TEST_RED='\033[0;31m'
TEST_DIM='\033[2m'
TEST_NC='\033[0m'

# Lines 3-14 are the user-facing header; everything below is an implementation
# note that does not belong in --help output.
_test_usage() {
    sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# _test_dir <path> -- sets TEST_DIR_OUT to the directory a path lives in, "."
# at the repo root.
#
# One definition, used by both discovery passes and by _test_owner, because
# "the directory of a path" appearing twice is a second source of truth: a
# slashless root-level path makes ${file%/*} return the FILENAME, which would
# silently stop the fragment-exclusion clause firing at the repo root.
#
# A "." sentinel rather than "": bash rejects an empty associative-array
# subscript outright, and "." can never appear as a git ls-files path.
#
# Assigns rather than prints. Printing costs a fork per tracked file per pass
# -- 470 of them on this repo, ~86ms -- and this runs on every commit once the
# pre-commit hook calls it. Inlining the case at each site would be as fast,
# but that is exactly the duplication this function exists to prevent.
_test_dir() {
    case "$1" in
        */*) TEST_DIR_OUT="${1%/*}" ;;
        *)   TEST_DIR_OUT="." ;;
    esac
}

# _test_suites -- every suite entry point, one NUL-terminated root-relative
# path per record, in git's sorted order so a run is deterministic.
#
# NUL-terminated, not newline: a tracked path may legally contain a newline,
# and splitting on one would invent two bogus suite paths out of a real file.
# That is the same reason the reads below are -d ''.
#
# Two passes over the same listing. One cannot work: a test-*.sh may be listed
# before the run-tests.sh that supersedes it, so which directories are owned
# has to be known before any entry point is emitted.
_test_suites() {
    local file dir TEST_DIR_OUT
    local -A owned=()

    # Process substitution, not a pipeline: a pipeline would fill `owned` in a
    # subshell and the second pass would see an empty map.
    while IFS= read -r -d '' file; do
        case "${file##*/}" in
            run-tests.sh) _test_dir "$file"; owned["$TEST_DIR_OUT"]=1 ;;
        esac
    done < <(git -C "$TEST_ROOT" ls-files -z 2>/dev/null)

    while IFS= read -r -d '' file; do
        _test_dir "$file"
        dir="$TEST_DIR_OUT"
        case "${file##*/}" in
            run-tests.sh) printf '%s\0' "$file" ;;
            test-*.sh)    [ -n "${owned[$dir]:-}" ] || printf '%s\0' "$file" ;;
        esac
    done < <(git -C "$TEST_ROOT" ls-files -z 2>/dev/null)
}

# _test_owner <suite-path> -- the path prefix a suite covers, with its trailing
# slash. Prints nothing for a suite that covers the whole tree, so that the
# prefix comparison below matches every path.
_test_owner() {
    local dir TEST_DIR_OUT
    _test_dir "$1"
    dir="$TEST_DIR_OUT"
    case "$dir" in
        .|test)  return 0 ;;
        */test)  dir="${dir%/test}" ;;
    esac
    printf '%s/' "$dir"
}

# _test_covers <owner-prefix> <path>...
# True when any path lies under the prefix. The prefix is quoted inside the
# case pattern so a glob character in a directory name stays literal.
#
# The comparison is TEXTUAL and the paths must be repo-relative. A deleted file
# still matches, which is deliberate -- the hook passes staged paths that may
# no longer exist on disk. But an ABSOLUTE path matches no owner prefix except
# the repo root's empty one, so passing one selects only the repo-root suite
# and still reports "1 suite passed": a targeted run that looks successful
# while testing nothing it was aimed at. Callers must pass what git reports.
_test_covers() {
    local owner="$1" path
    shift
    for path in "$@"; do
        case "$path" in
            "$owner"*) return 0 ;;
        esac
    done
    return 1
}

# Milliseconds since the epoch. %3N is GNU date; this repo is Arch-only.
_test_now_ms() {
    date +%s%3N
}

# _test_duration <start-ms> <end-ms> -- elapsed time as seconds to one decimal.
_test_duration() {
    local ms=$(( $2 - $1 ))
    printf '%d.%d' "$(( ms / 1000 ))" "$(( (ms % 1000) / 100 ))"
}

TEST_MODE=run
TEST_FOR=()

case "${1:-}" in
    --help|-h)
        _test_usage
        exit 0
        ;;
    --list)
        TEST_MODE=list
        ;;
    --for)
        TEST_MODE=for
        shift
        TEST_FOR=("$@")
        if [ "${#TEST_FOR[@]}" -eq 0 ]; then
            echo "test: --for needs at least one path" >&2
            echo >&2
            _test_usage >&2
            exit 2
        fi
        ;;
    "")
        ;;
    *)
        echo "test: unknown option '$1'" >&2
        echo >&2
        _test_usage >&2
        exit 2
        ;;
esac

# Discovery derives from git, so without this guard "not a repository" and "no
# suites in this repo" would print the same reassuring nothing. Same reasoning
# as doctor_require_repo.
if ! git -C "$TEST_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'test: %s is not a git repository -- suites are discovered from git\n' "$TEST_ROOT" >&2
    exit 1
fi

mapfile -d '' -t TEST_SUITES < <(_test_suites)

[ "$TEST_MODE" = list ] || printf 'Testing %s\n\n' "$TEST_ROOT"

TEST_RAN=0
TEST_FAILED=0

for _test_suite in ${TEST_SUITES[@]+"${TEST_SUITES[@]}"}; do
    _test_owner_prefix="$(_test_owner "$_test_suite")"

    if [ "$TEST_MODE" = list ]; then
        printf '%s\t%s\n' "$_test_suite" "${_test_owner_prefix:-(repo root)}"
        continue
    fi

    if [ "$TEST_MODE" = for ] && ! _test_covers "$_test_owner_prefix" "${TEST_FOR[@]}"; then
        continue
    fi

    TEST_RAN=$((TEST_RAN + 1))
    _test_start="$(_test_now_ms)"
    # A command substitution runs the suite in a subshell, but the `if` and the
    # counters below live in this shell, so nothing is lost.
    if _test_out="$(bash "$TEST_ROOT/$_test_suite" 2>&1)"; then
        printf '  %b✓%b %s %b(%ss)%b\n' "$TEST_GREEN" "$TEST_NC" "$_test_suite" \
            "$TEST_DIM" "$(_test_duration "$_test_start" "$(_test_now_ms)")" "$TEST_NC"
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        printf '  %b✗%b %s %b(%ss)%b\n' "$TEST_RED" "$TEST_NC" "$_test_suite" \
            "$TEST_DIM" "$(_test_duration "$_test_start" "$(_test_now_ms)")" "$TEST_NC"
        printf '%s\n' "$_test_out" | sed 's/^/      /'
    fi
done

[ "$TEST_MODE" = list ] && exit 0

echo
if [ "$TEST_RAN" -eq 0 ]; then
    if [ "$TEST_MODE" = for ]; then
        echo "no suites cover the changed files"
    else
        echo "no test suites found"
    fi
    exit 0
fi

if [ "$TEST_FAILED" -eq 0 ]; then
    echo "$TEST_RAN suite$([ "$TEST_RAN" -eq 1 ] || echo s) passed"
    exit 0
fi

echo "$TEST_FAILED of $TEST_RAN suite$([ "$TEST_RAN" -eq 1 ] || echo s) failed"
exit 1
