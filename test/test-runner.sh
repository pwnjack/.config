#!/bin/bash
#
# Tests for test.sh.
#
# Standalone and runnable on its own, exit 1 on any failure -- the same style
# as scripts/waybar/test-battery.sh, because this file is itself a discovered
# entry point and so must run without a harness around it.
#
# Every case drives the REAL test.sh with TEST_ROOT pointed at a fixture repo
# whose "suites" are one-line stubs. Nothing here runs the repo's own suites,
# so there is no recursion: the fixture contains no test.sh of its own.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$TEST_DIR")"
RUNNER="$REPO_DIR/test.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  ok   $1"; }
fail() {
    FAILED=$((FAILED + 1))
    echo "  FAIL $1"
    shift
    printf '       %s\n' "$@"
}

# assert_contains <output> <needle> <label>
assert_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then
        pass "$3"
    else
        fail "$3" "expected to contain: $2" "actual:" "$1"
    fi
}

# assert_not_contains <output> <needle> <label>
assert_not_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then
        fail "$3" "expected NOT to contain: $2" "actual:" "$1"
    else
        pass "$3"
    fi
}

# assert_eq <actual> <expected> <label>
assert_eq() {
    if [ "$1" = "$2" ]; then
        pass "$3"
    else
        fail "$3" "expected: $2" "actual:   $1"
    fi
}

# suite <root> <path> <exit-code> [exec|noexec] -- a one-line stub suite that
# prints its own name so the runner's output capture can be asserted on.
#
# Stubs are NON-EXECUTABLE by default. test.sh invokes a suite as `bash <path>`
# and its header claims discovery depends on neither the exec bit nor shebang
# variance; making the default stub mode 644 puts that claim under every
# assertion in this file rather than in one case of its own. Pass "exec" for a
# stub that needs the bit.
suite() {
    local root=$1 path=$2 code=$3 bits=${4:-noexec}
    mkdir -p "$root/$(dirname "$path")"
    {
        echo '#!/bin/bash'
        echo "echo \"ran $path\""
        echo "exit $code"
    } > "$root/$path"
    chmod 644 "$root/$path"
    [ "$bits" = exec ] && chmod +x "$root/$path"
    return 0
}

# fixture -- a git repo laid out like this one: a doctor-style suite with
# sibling fragments, a standalone suite, and a non-suite script.
fixture() {
    local root
    root="$(mktemp -d "$TMP/repo.XXXXXX")"
    git -C "$root" init -q -b main
    git -C "$root" config user.email "test@test"
    git -C "$root" config user.name "test"
    # One executable, the rest mode 644: both are meant to run, which is what
    # "discovery does not depend on the exec bit" has to mean to be worth
    # claiming. The waybar stub is the non-executable one, and the roll-up
    # assertions below all count on it having run.
    suite "$root" "scripts/doctor/test/run-tests.sh" 0 exec
    suite "$root" "scripts/doctor/test/test-alpha.sh" 1
    suite "$root" "scripts/doctor/test/test-beta.sh" 1
    suite "$root" "scripts/waybar/test-battery.sh" 0
    mkdir -p "$root/rofi"
    echo '#!/bin/bash' > "$root/rofi/powermenu.sh"
    git -C "$root" add -A
    git -C "$root" commit -qm fixture
    printf '%s' "$root"
}

# run <root> <args...> -- fills RUN_OUT with the runner's combined output and
# RC with its exit code.
#
# Deliberately NOT `out="$(run ...)"`: a command substitution runs the function
# in a subshell, so RC would be assigned there and the parent would keep seeing
# 0 -- the same subshell trap the doctor's tests document.
RUN_OUT=""
RC=0
run() {
    local root=$1
    shift
    RUN_OUT="$(TEST_ROOT="$root" bash "$RUNNER" "$@" 2>&1)"
    RC=$?
}

# --- discovery ------------------------------------------------------------
root="$(fixture)"
run "$root" --list; out="$RUN_OUT"

assert_contains "$out" "scripts/doctor/test/run-tests.sh" "a run-tests.sh is an entry point"
assert_contains "$out" "scripts/waybar/test-battery.sh" "a lone test-*.sh is an entry point"
assert_not_contains "$out" "test-alpha.sh" "a fragment beside run-tests.sh is not an entry point"
assert_not_contains "$out" "test-beta.sh" "the second fragment is not an entry point either"
assert_not_contains "$out" "powermenu.sh" "a non-test script is not an entry point"
assert_eq "$RC" "0" "--list exits 0"

# --- owning directories ----------------------------------------------------
# Asserted through --for, NOT by grepping the --list owner column: every owner
# string is also a prefix of the suite path printed beside it, so
# assert_contains on "scripts/doctor/" passes whether the owner reads
# scripts/doctor/ or scripts/doctor/test/. Only behaviour separates them.

# The owner is scripts/doctor/, not scripts/doctor/test/ -- a suite covers the
# code it tests, not the directory it lives in.
run "$root" --for scripts/doctor/checks/x.sh; out="$RUN_OUT"
assert_contains "$out" "1 suite passed" "a doctor suite covers scripts/doctor/, not scripts/doctor/test/"

# The owner's trailing slash is what keeps the prefix a directory boundary.
run "$root" --for scripts/waybarfoo/x.sh; out="$RUN_OUT"
assert_contains "$out" "no suites cover the changed files" "a sibling directory sharing a name prefix is not covered"

# --- fragment exclusion at the repo root -----------------------------------
# A run-tests.sh directly at the repo root has no slash in its path, which is
# the case where deriving "the directory of a path" as ${file%/*} silently
# yields the FILENAME instead: the two passes then key on different strings and
# the sibling fragment is emitted as an entry point of its own.
root_flat="$(mktemp -d "$TMP/flat.XXXXXX")"
git -C "$root_flat" init -q -b main
git -C "$root_flat" config user.email "test@test"
git -C "$root_flat" config user.name "test"
suite "$root_flat" "run-tests.sh" 0
suite "$root_flat" "test-frag.sh" 1
git -C "$root_flat" add -A
git -C "$root_flat" commit -qm flat
run "$root_flat" --list; out="$RUN_OUT"

assert_contains "$out" "run-tests.sh" "a run-tests.sh at the repo root is an entry point"
assert_not_contains "$out" "test-frag.sh" "a fragment beside a root-level run-tests.sh is not an entry point"

# It runs, and its exit code is the run's -- the root-level suite is not merely
# listed correctly but dispatched correctly too.
run "$root_flat"; out="$RUN_OUT"
assert_eq "$RC" "0" "a root-level run-tests.sh runs and its fragment does not"
assert_contains "$out" "1 suite passed" "only the root-level run-tests.sh ran"

# --- a path containing a newline -------------------------------------------
# git tracks such a path legally and C-quotes it in listings. Carrying the
# suite list on newlines rather than NULs splits this ONE file into two bogus
# entries, and both then fail as missing files -- a green suite turning into
# two red ones with no source change.
root_nl="$(mktemp -d "$TMP/nl.XXXXXX")"
git -C "$root_nl" init -q -b main
git -C "$root_nl" config user.email "test@test"
git -C "$root_nl" config user.name "test"
suite "$root_nl" "$(printf 'we\nird')/test-nl.sh" 0
git -C "$root_nl" add -A
git -C "$root_nl" commit -qm nl
run "$root_nl"; out="$RUN_OUT"

assert_eq "$RC" "0" "a suite whose path contains a newline runs"
assert_contains "$out" "1 suite passed" "a newline in a path yields one suite, not two"

# --- a suite at the repo root owns the whole tree --------------------------
root_top="$(fixture)"
suite "$root_top" "test/test-runner.sh" 0
git -C "$root_top" add -A
git -C "$root_top" commit -qm top
run "$root_top" --list; out="$RUN_OUT"
assert_contains "$out" "(repo root)" "a suite under a top-level test/ owns the repo root"

# A passing suite's output is never printed, so the roll-up count -- not the
# stub's own line -- is what proves which suites ran.
run "$root_top" --for README.md; out="$RUN_OUT"
assert_contains "$out" "1 suite passed" "the repo-root suite covers a path no other suite owns"

# --- running --------------------------------------------------------------
run "$root"; out="$RUN_OUT"
assert_eq "$RC" "0" "all-passing run exits 0"
assert_contains "$out" "2 suites passed" "roll-up counts the suites that ran"
assert_not_contains "$out" "ran scripts/waybar/test-battery.sh" "a passing suite's output is not printed"

# --- failure --------------------------------------------------------------
root_bad="$(fixture)"
suite "$root_bad" "scripts/waybar/test-battery.sh" 1
run "$root_bad"; out="$RUN_OUT"
assert_eq "$RC" "1" "a failing suite makes the run exit 1"
assert_contains "$out" "1 of 2 suites failed" "roll-up names how many failed"
assert_contains "$out" "ran scripts/waybar/test-battery.sh" "a failing suite's output is printed in full"

# --- --for ----------------------------------------------------------------
run "$root" --for scripts/waybar/battery.sh; out="$RUN_OUT"
assert_eq "$RC" "0" "a covered --for exits 0"
assert_contains "$out" "1 suite passed" "--for runs only the covering suite"
assert_not_contains "$out" "scripts/doctor/test/run-tests.sh" "--for skips an uncovered suite"

# This fixture has no repo-root suite, so nothing covers rofi/.
run "$root" --for rofi/powermenu.sh; out="$RUN_OUT"
assert_eq "$RC" "0" "an uncovered --for is not a failure"
assert_contains "$out" "no suites cover the changed files" "an uncovered --for says so"

# A deleted file still matches: the comparison is textual, and the hook passes
# paths that may no longer exist on disk.
run "$root" --for scripts/waybar/gone.sh; out="$RUN_OUT"
assert_contains "$out" "1 suite passed" "a path that no longer exists still selects its suite"

# Several paths at once, which is how the pre-commit hook calls it: the result
# is the UNION of the covering suites, and a path nothing covers (docs/) simply
# contributes none. A single-path case cannot exercise the loop at all.
run "$root" --for docs/notes.md scripts/waybar/battery.sh scripts/doctor/checks/x.sh; out="$RUN_OUT"
assert_eq "$RC" "0" "a multi-path --for exits 0"
assert_contains "$out" "2 suites passed" "--for selects the union of the suites covering several paths"

# Order must not matter: the covering path is last here, first above.
run "$root" --for scripts/waybar/battery.sh docs/notes.md; out="$RUN_OUT"
assert_contains "$out" "1 suite passed" "--for matches a covering path wherever it sits in the list"

run "$root" --for; out="$RUN_OUT"
assert_eq "$RC" "2" "--for with no path is a usage error"

# --- usage ----------------------------------------------------------------
run "$root" --help; out="$RUN_OUT"
assert_eq "$RC" "0" "--help exits 0"
assert_contains "$out" "Usage:" "--help prints usage"
# Paired with the assertion below, which on its own would also pass if --help
# printed nothing at all.
assert_contains "$out" "Dotfiles test runner" "--help prints the header block"
assert_not_contains "$out" "#" "--help strips the comment markers"
# Both edges of the sed range, not just the top. This range has already drifted
# once -- the header block grew from 3-13 to 3-14 on this file's first edit --
# and neither a widened nor a narrowed range is caught by the assertions above.
assert_contains "$out" "2 on a usage error" "--help prints through the end of the usage block"
assert_not_contains "$out" "A suite is DISCOVERED" "--help stops before the implementation notes"

run "$root" --nonsense; out="$RUN_OUT"
assert_eq "$RC" "2" "an unknown option exits 2"
assert_contains "$out" "unknown option" "an unknown option says which"

# An absolute path matches no owning prefix but the repo root's empty one, so
# without this guard it runs only the repo-root suite and still reports a green
# "1 suite passed" -- a targeted run that tested nothing it was aimed at.
run "$root" --for "$root/scripts/waybar/battery.sh"; out="$RUN_OUT"
assert_eq "$RC" "2" "an absolute --for path is a usage error"
assert_contains "$out" "repo-relative" "an absolute --for path says what was wanted"
# "Testing <root>", not "suite passed": the usage block printed on a usage
# error itself contains the words "every suite passed", so that needle matches
# the help text rather than a roll-up. The run header proves no suite started.
assert_not_contains "$out" "Testing " "an absolute --for path starts no run at all"

# --- an empty repository --------------------------------------------------
# Distinct from the non-repository case below: git works, there is simply
# nothing to run. Not a failure.
empty="$(mktemp -d "$TMP/empty.XXXXXX")"
git -C "$empty" init -q -b main
run "$empty"; out="$RUN_OUT"
assert_eq "$RC" "0" "a repo with no suites exits 0"
assert_contains "$out" "no test suites found" "a repo with no suites says so"
assert_not_contains "$out" "not a git repository" "an empty repo is not reported as a non-repository"

# --- not a repository -----------------------------------------------------
bare="$(mktemp -d "$TMP/bare.XXXXXX")"
run "$bare"; out="$RUN_OUT"
assert_eq "$RC" "1" "a non-repository root exits 1"
assert_contains "$out" "not a git repository" "a non-repository root says so"
assert_not_contains "$out" "no test suites found" "a non-repository is not reported as an empty repo"

echo
echo "test.sh: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
