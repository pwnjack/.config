# Repo Engineering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the repo one command that runs every test suite, adopt the orphaned battery suite into the commit gate, and add a doctor check covering waybar.

**Architecture:** A dependency-free `test.sh` at the repo root discovers suite entry points from `git ls-files` by naming convention and runs each as a subprocess, capturing output. Each suite has an *owning directory* — its own directory minus a trailing `test/` component — which is the only place the file-area-to-suite mapping lives; the pre-commit hook passes staged paths to `--for` and lets the runner decide what runs. Independently, a fifth doctor check module derives waybar's placed modules, configured blocks and handler commands from `waybar/config.jsonc` by grep and awk.

**Tech Stack:** Bash 5, git, GNU sed/awk/date, shellcheck. No new package dependencies.

**Spec:** `docs/superpowers/specs/2026-08-01-repo-engineering-design.md`

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `test.sh` | Create | Suite discovery, owning-directory mapping, subprocess execution, roll-up |
| `test/test-runner.sh` | Create | Tests for `test.sh`, standalone, fixture-driven |
| `scripts/doctor/checks/waybar.sh` | Create | `check_waybar` — three findings derived from `config.jsonc` |
| `scripts/doctor/test/test-waybar.sh` | Create | Tests for the above, sourced fragment |
| `doctor.sh` | Modify | Register the new module (lines 51 and 70) |
| `scripts/hooks/pre-commit` | Modify | Replace the doctor-only stanza with a `test.sh --for` call |
| `install.sh` | Modify | Line 291 success message |
| `README.md` | Modify | Lines 128-140, hook description and test command |
| `CLAUDE.md` | Modify | Key Commands, doctor tree, discovery convention |
| `scripts/waybar/test-battery.sh` | Modify | Header comment line 8 |

**Why `test/test-runner.sh` sits at the repo root rather than under `scripts/`.** The owning-directory rule strips a trailing `test/` component, so `test/` maps to the empty prefix — the whole repo. That is what makes the runner's own tests run when `test.sh` itself is staged. Putting them at `scripts/test/test-runner.sh` would give them the owner `scripts/`, which does **not** contain the root-level `test.sh`, leaving a broken discovery rule able to land through the gate untested.

---

### Task 1: The test runner

**Goal:** `./test.sh` discovers both existing suites, runs them as subprocesses, and reports a roll-up; `--list` and `--for` work.

**Files:**
- Create: `test.sh`
- Test: `test/test-runner.sh`

**Acceptance Criteria:**
- [ ] `./test.sh --list` prints exactly `scripts/doctor/test/run-tests.sh` and `scripts/waybar/test-battery.sh`, plus `test/test-runner.sh`, with owners `scripts/doctor/`, `scripts/waybar/` and `(repo root)`
- [ ] The doctor's six `test-*.sh` fragments are NOT listed as entry points
- [ ] `./test.sh` exits 0 and runs every suite
- [ ] A failing suite makes `./test.sh` exit 1 and prints that suite's full captured output
- [ ] `./test.sh --for rofi/powermenu.sh` exits 0 and runs only `test/test-runner.sh`, which owns the repo root — not the doctor or battery suites
- [ ] In a fixture with no repo-root suite, an uncovered `--for` prints "no suites cover the changed files" and exits 0
- [ ] `./test.sh --for scripts/waybar/battery.sh` runs the battery suite and the repo-root suite, not the doctor suite
- [ ] `./test.sh --help` prints usage and exits 0; an unknown option exits 2
- [ ] A non-git `TEST_ROOT` exits 1 with a message naming git as the source of discovery
- [ ] `shellcheck -S warning test.sh test/test-runner.sh` is silent

**Verify:** `bash test/test-runner.sh` → ends with `test.sh: N passed, 0 failed`, exit 0

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `test/test-runner.sh`. It builds fixture repos and drives the real `test.sh` against them via `TEST_ROOT`, so it never executes the repo's real suites and cannot recurse.

```bash
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

# suite <root> <path> <exit-code> -- a one-line stub suite that prints its own
# name so the runner's output capture can be asserted on.
suite() {
    local root=$1 path=$2 code=$3
    mkdir -p "$root/$(dirname "$path")"
    {
        echo '#!/bin/bash'
        echo "echo \"ran $path\""
        echo "exit $code"
    } > "$root/$path"
    chmod +x "$root/$path"
}

# fixture -- a git repo laid out like this one: a doctor-style suite with
# sibling fragments, a standalone suite, and a non-suite script.
fixture() {
    local root
    root="$(mktemp -d "$TMP/repo.XXXXXX")"
    git -C "$root" init -q -b main
    git -C "$root" config user.email "test@test"
    git -C "$root" config user.name "test"
    suite "$root" "scripts/doctor/test/run-tests.sh" 0
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

assert_contains "$out" "scripts/doctor/" "run-tests.sh owner drops the test/ component"
assert_contains "$out" "scripts/waybar/" "a suite outside a test/ dir owns its own directory"

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

run "$root" --for; out="$RUN_OUT"
assert_eq "$RC" "2" "--for with no path is a usage error"

# --- usage ----------------------------------------------------------------
run "$root" --help; out="$RUN_OUT"
assert_eq "$RC" "0" "--help exits 0"
assert_contains "$out" "Usage:" "--help prints usage"
assert_not_contains "$out" "#" "--help strips the comment markers"

run "$root" --nonsense; out="$RUN_OUT"
assert_eq "$RC" "2" "an unknown option exits 2"
assert_contains "$out" "unknown option" "an unknown option says which"

# --- not a repository -----------------------------------------------------
bare="$(mktemp -d "$TMP/bare.XXXXXX")"
run "$bare"; out="$RUN_OUT"
assert_eq "$RC" "1" "a non-repository root exits 1"
assert_contains "$out" "not a git repository" "a non-repository root says so"
assert_not_contains "$out" "no test suites found" "a non-repository is not reported as an empty repo"

echo
echo "test.sh: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash test/test-runner.sh`
Expected: FAIL — every case fails because `test.sh` does not exist yet. The last line reads `test.sh: 0 passed, N failed` and the exit status is 1.

- [ ] **Step 3: Write the runner**

Create `test.sh`. The header block is lines 3-13, which is what `--help` prints — keep it exactly this length or update the `sed` range to match.

```bash
#!/bin/bash
#
# Dotfiles test runner
# Runs the repo's test suites -- all of them, or only those covering a path.
#
# Usage: ./test.sh [--list] [--for PATH...]
#
#   (no args)      run every discovered suite
#   --for PATH...  run only the suites whose owning directory covers a PATH
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

# Lines 3-13 are the user-facing header; everything below is an implementation
# note that does not belong in --help output.
_test_usage() {
    sed -n '3,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# _test_suites -- every suite entry point, one root-relative path per line, in
# git's sorted order so a run is deterministic.
#
# Two passes over the same listing. One cannot work: a test-*.sh may be listed
# before the run-tests.sh that supersedes it, so which directories are owned
# has to be known before any entry point is emitted.
_test_suites() {
    local file dir
    local -A owned=()

    # Process substitution, not a pipeline: a pipeline would fill `owned` in a
    # subshell and the second pass would see an empty map.
    while IFS= read -r -d '' file; do
        case "${file##*/}" in
            run-tests.sh) owned["${file%/*}"]=1 ;;
        esac
    done < <(git -C "$TEST_ROOT" ls-files -z 2>/dev/null)

    while IFS= read -r -d '' file; do
        dir="${file%/*}"
        case "${file##*/}" in
            run-tests.sh) printf '%s\n' "$file" ;;
            test-*.sh)    [ -n "${owned[$dir]:-}" ] || printf '%s\n' "$file" ;;
        esac
    done < <(git -C "$TEST_ROOT" ls-files -z 2>/dev/null)
}

# _test_owner <suite-path> -- the path prefix a suite covers, with its trailing
# slash. Prints nothing for a suite that covers the whole tree, so that the
# prefix comparison below matches every path.
_test_owner() {
    local dir
    case "$1" in
        */*) dir="${1%/*}" ;;
        *)   return 0 ;;
    esac
    case "$dir" in
        test)    return 0 ;;
        */test)  dir="${dir%/test}" ;;
    esac
    printf '%s/' "$dir"
}

# _test_covers <owner-prefix> <path>...
# True when any path lies under the prefix. The prefix is quoted inside the
# case pattern so a glob character in a directory name stays literal.
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

mapfile -t TEST_SUITES < <(_test_suites)

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
```

- [ ] **Step 4: Make both files executable and run the tests**

```bash
chmod +x test.sh test/test-runner.sh
bash test/test-runner.sh
```

Expected: PASS — final line `test.sh: N passed, 0 failed` where N is the number of assertions in the file (31 as written above), exit 0. What matters is `0 failed`. If the `--help` assertions fail, the header block is no longer lines 3-13; adjust the `sed -n '3,13p'` range in `_test_usage` to match the actual block.

- [ ] **Step 5: Verify against the real repo**

```bash
./test.sh --list
./test.sh
```

Expected from `--list`, three lines: `scripts/doctor/test/run-tests.sh` → `scripts/doctor/`, `scripts/waybar/test-battery.sh` → `scripts/waybar/`, `test/test-runner.sh` → `(repo root)`. No `test-binaries.sh`, `test-lib.sh`, `test-references.sh`, `test-services.sh`, `test-symlinks.sh` or `test-entrypoint.sh` among them.

Expected from `./test.sh`: three green ticks and `3 suites passed`, exit 0, in roughly 2 seconds.

- [ ] **Step 6: Prove a failure is visible, then revert**

```bash
printf '\nexit 1\n' >> scripts/waybar/test-battery.sh
./test.sh; echo "exit: $?"
git checkout -- scripts/waybar/test-battery.sh
```

Expected: `✗ scripts/waybar/test-battery.sh`, that suite's full output indented beneath it, `1 of 3 suites failed`, exit 1. Then the checkout restores the file — confirm with `git status --short` printing nothing for it.

- [ ] **Step 7: Lint**

```bash
shellcheck -S warning test.sh test/test-runner.sh
```

Expected: no output, exit 0.

- [ ] **Step 8: Commit**

```bash
git add test.sh test/test-runner.sh
git commit -m "feat(test): add a repo-wide test runner that discovers its suites

Discovers entry points from git by naming convention rather than a list:
run-tests.sh, or test-*.sh in a directory that has none. That adopts the
orphaned scripts/waybar/test-battery.sh with no change to either suite.

A suite's owning directory -- its own, minus a trailing test/ component -- is
the mapping the pre-commit hook will use, kept here so it lives in one place."
```

---

### Task 2: The doctor's waybar check

**Goal:** `./doctor.sh` gains a Waybar group that reports unconfigured modules, orphaned config blocks, and handler binaries that are not installed.

**Files:**
- Create: `scripts/doctor/checks/waybar.sh`
- Modify: `doctor.sh:51`, `doctor.sh:70`
- Test: `scripts/doctor/test/test-waybar.sh`

**Acceptance Criteria:**
- [ ] A `custom/*` module placed with no config block is an ERROR
- [ ] A built-in module placed with no config block is a WARN
- [ ] A config block placed in no `modules-*` list is an INFO
- [ ] A handler binary not in `PATH` is a WARN
- [ ] `~/.config` and `$HOME/.config` handler paths are skipped — `references.sh` owns them
- [ ] The waybar action keywords produce no finding
- [ ] Both the inline and multi-line `modules-*` array forms are parsed
- [ ] Nested keys (`actions`, `format`) are not mistaken for config blocks
- [ ] `ok` prints only when the check found nothing at all
- [ ] On the live repo the group reports exactly one INFO — the orphaned `user` block — and `./doctor.sh` still exits 0

**Verify:** `./scripts/doctor/test/run-tests.sh` → `7 files, N assertions, 0 failures`, exit 0

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `scripts/doctor/test/test-waybar.sh`. Sourced fragment, so no shebang — same as its five siblings.

```bash
# Tests for scripts/doctor/checks/waybar.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash
#
# Checks are run ONCE, redirected to a file under $DOCTOR_TEST_TMP, and the
# output is read back. `out="$(check_x)"` would run the check in a subshell and
# discard its severity counters.
#
# _way_have_cmd is shadowed by a function rather than by manipulating PATH: the
# check runs in this shell, so a definition here wins, and the test then does
# not depend on what happens to be installed on the machine running it.

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/waybar.sh"

# Assigned throughout this file but read only by the check sourced above.
export DOCTOR_ROOT

way_out_file="$DOCTOR_TEST_TMP/waybar.out"

# Only these two resolve; everything else the fixtures name does not.
_way_have_cmd() {
    case "$1" in
        installed-tool|hyprctl) return 0 ;;
        *) return 1 ;;
    esac
}

# way_config <root> <body> — write a config.jsonc into a fixture repo.
way_config() {
    mkdir -p "$1/waybar"
    printf '%s\n' "$2" > "$1/waybar/config.jsonc"
}

# --- a config exercising every finding ------------------------------------
way_fixture="$(make_fixture)"
way_config "$way_fixture" '{
  "layer": "bottom",
  "spacing": 0,

  // inline form, as modules-left is written in the real config
  "modules-left": ["hyprland/window", "custom/orphaned"],

  // multi-line form
  "modules-right": [
    "clock",
    "typoed-builtin",
    "custom/media",
  ],

  "hyprland/window": {
    "format": "{}",
  },

  "clock": {
    "on-click": "installed-tool",
    "actions": {
      "on-click-middle": "mode",
      "on-scroll-up": "shift_up",
      "on-scroll-down": "shift_down",
    },
  },

  "custom/media": {
    "exec": "~/.config/scripts/hyprland/mediaexec.sh",
    "on-click": "missing-tool",
    "on-scroll-up": "hyprctl dispatch workspace r-1",
  },

  "unplaced-block": {
    "format": "{}",
  },
}'

DOCTOR_ROOT="$way_fixture"
doctor_reset
check_waybar > "$way_out_file" 2>&1
way_out="$(<"$way_out_file")"

# --- placed but unconfigured ----------------------------------------------
assert_contains "$way_out" "custom/orphaned" "a custom module with no block is reported"
assert_contains "$way_out" "ERROR" "a custom module with no block is ERROR severity"
assert_contains "$way_out" "typoed-builtin" "a built-in with no block is reported"
assert_not_contains "$way_out" "hyprland/window but" "a configured module produces no finding"

# --- configured but unplaced ----------------------------------------------
assert_contains "$way_out" "unplaced-block" "a block in no modules list is reported"
assert_contains "$way_out" "INFO" "an unplaced block is INFO severity"

# --- handler binaries -----------------------------------------------------
assert_contains "$way_out" "missing-tool" "an uninstalled handler binary is reported"
assert_not_contains "$way_out" "installed-tool" "an installed handler binary produces no finding"
assert_not_contains "$way_out" "hyprctl" "only the first token of a handler is checked"
assert_not_contains "$way_out" "mediaexec.sh" "a ~/.config handler is left to references.sh"

# --- waybar's own action vocabulary ---------------------------------------
# These sit where a command would and resolve nowhere; without the skip set
# they are five warnings on a healthy machine.
assert_not_contains "$way_out" "mode," "an action keyword is not read as a command"
assert_not_contains "$way_out" "shift_up" "shift_up is not read as a command"
assert_not_contains "$way_out" "shift_down" "shift_down is not read as a command"

# --- nested keys are not config blocks ------------------------------------
# "format" and "actions" are nested inside clock; reading them as top-level
# blocks would report both as unplaced.
assert_not_contains "$way_out" "configures format" "a nested key is not read as a config block"
assert_not_contains "$way_out" "configures actions" "an actions sub-block is not read as a config block"

assert_eq "$DOCTOR_ERRORS" "1" "one custom module without a block counted as an error"
assert_eq "$DOCTOR_WARNINGS" "2" "the typoed built-in and the missing binary counted as warnings"
assert_eq "$DOCTOR_NOTICES" "1" "one unplaced block counted as a notice"

# --- fix hints ------------------------------------------------------------
assert_contains "$way_out" "$way_fixture/waybar/config.jsonc" "hints name the config file"
assert_not_contains "$way_out" "<" "no hint contains what a shell reads as a redirection"

# --- a clean config gets the all-clear ------------------------------------
way_clean="$(make_fixture)"
way_config "$way_clean" '{
  "modules-left": ["clock"],
  "clock": {
    "on-click": "installed-tool",
  },
}'

DOCTOR_ROOT="$way_clean"
doctor_reset
check_waybar > "$way_out_file" 2>&1
way_clean_out="$(<"$way_out_file")"

assert_contains "$way_clean_out" "✓" "a clean config gets the green tick"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS$DOCTOR_NOTICES" "000" "a clean config records no findings"
assert_not_contains "$way_out" "✓" "a config with findings gets no green tick"

# --- no waybar config at all ----------------------------------------------
# Not an error: DOCTOR_ROOT may be a fixture or a partial clone, and the
# absence of a bar is not a broken bar.
way_bare="$(make_fixture)"
DOCTOR_ROOT="$way_bare"
doctor_reset
check_waybar > "$way_out_file" 2>&1
way_bare_out="$(<"$way_out_file")"

assert_contains "$way_bare_out" "nothing to check" "a repo without a waybar config says so"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS" "00" "a missing waybar config is not an error or warning"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./scripts/doctor/test/run-tests.sh`
Expected: FAIL — the run aborts sourcing `test-waybar.sh` because `scripts/doctor/checks/waybar.sh` does not exist, and the trap prints `ABORTED after N of 7 files`.

- [ ] **Step 3: Write the check module**

Create `scripts/doctor/checks/waybar.sh`.

```bash
#!/bin/bash
#
# Waybar bar integrity: every module on the bar is configured, every configured
# block is on the bar, and every command a handler invokes exists.
#
# Nothing is enumerated here. The placed modules come out of the modules-left,
# modules-center and modules-right arrays; the configured blocks come out of
# the file's own top-level keys; the commands come out of the handler values. A
# module added tomorrow is covered the moment it is committed.
#
# WHY GREP AND AWK RATHER THAN jq. config.jsonc is JSONC: jq fails on it
# outright (comments, trailing commas), and stripping comments first would
# corrupt any string containing //. The file's own two-space top-level indent
# is a more reliable handle than a pre-processor.
#
# WHAT IS DELIBERATELY NOT REPORTED:
#
#   Handler paths under ~/.config or $HOME/.config. references.sh already scans
#   every tracked file for those, and config.jsonc is tracked, so checking them
#   here would report the same fact twice against the same file.
#
#   A built-in module placed with no config block is NOT an error. waybar
#   renders clock or cpu perfectly well on its defaults. It is still worth a
#   WARN, because it is also exactly what a typo looks like -- waybar drops an
#   unknown module name silently, so a bar missing a module looks identical to
#   a bar that never had one.
#
#   A style.css selector for every module. CSS selectors nest and group, so the
#   derivation is unreliable in a way the other two are not.
#
# SEVERITY:
#
#   A custom/* module placed with no block is an ERROR. It has no exec and no
#   format, so there is nothing for waybar to run or draw: the module is dead.
#
#   A built-in placed with no block is a WARN, per the note above.
#
#   A block placed in no modules list is INFO -- doctor.sh's header defines
#   that severity as exactly this ("tidiness -- orphaned config").
#
#   A missing handler binary is a WARN, matching references.sh: one broken
#   interaction is degradation, not a broken session, and calling it an ERROR
#   would make doctor.sh exit 1 on a machine whose bar comes up fine.
#
# Accepted limitations:
#   - A handler value containing an escaped quote is truncated at that quote.
#     No such value exists here, and waybar's own parser has no escape either.
#   - Only the first token of a handler is checked, so `sh -c "foo"` is checked
#     as `sh`. Checking deeper means parsing a shell command line out of JSON.
#   - The two-space indent rule assumes the file keeps its current formatting.
#     A reformat that changes top-level indentation makes the block list come
#     back empty, which shows up immediately as every placed module reported.
#

# Waybar's own action keywords. They sit exactly where a command would, and are
# NOT separable by module: hyprland/workspaces carries "on-click": "activate"
# and "on-scroll-up": "hyprctl dispatch workspace r-1" in the same block.
#
# This is upstream waybar vocabulary, not a second source of truth for anything
# in this repo, so no change here can make it stale -- only a waybar release
# can. Both failure modes are bounded and visible: a keyword added upstream and
# used here produces one false WARN, and a binary genuinely named like a
# keyword hides one real finding.
DOCTOR_WAYBAR_ACTIONS="activate close minimize minimize-raise fullscreen mode shift_up shift_down shift_reset"

# _way_placed <config>
# Every module name inside the modules-left/center/right arrays, sorted.
#
# Both array forms appear in this repo -- inline, as modules-left is written,
# and one-per-line, as modules-right is -- so the extractor tracks the array
# rather than matching a line shape. The key is stripped from the opening line
# before names are pulled out, so "modules-left" is not itself reported; a
# continuation line has no colon, so the strip is a no-op there.
_way_placed() {
    awk '
        /^[[:space:]]*"modules-(left|center|right)"[[:space:]]*:/ { inarr = 1 }
        inarr {
            line = $0
            sub(/^[^:]*:/, "", line)
            while (match(line, /"[^"]*"/)) {
                print substr(line, RSTART + 1, RLENGTH - 2)
                line = substr(line, RSTART + RLENGTH)
            }
            if (index($0, "]")) inarr = 0
        }
    ' "$1" 2>/dev/null | sort -u
}

# _way_configured <config>
# Every module config block, i.e. every top-level key whose value opens a brace.
#
# The two-space indent excludes nested keys such as "actions" and "format".
# Requiring { excludes the scalar settings ("layer": "bottom") and the
# modules-* arrays themselves, which open [.
_way_configured() {
    sed -n 's/^  "\([^"]*\)"[[:space:]]*:[[:space:]]*{.*$/\1/p' "$1" 2>/dev/null | sort -u
}

# _way_commands <config>
# The first token of every handler value waybar executes as a shell command.
_way_commands() {
    sed -n 's/^[[:space:]]*"\(exec\|on-click\|on-click-right\|on-click-middle\|on-scroll-up\|on-scroll-down\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*$/\2/p' "$1" 2>/dev/null \
        | awk 'NF { print $1 }' \
        | sort -u
}

# _way_have_cmd <token> — host probe, in its own function so tests can stub it.
_way_have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# _way_is_action <token> — true for one of waybar's own action keywords.
_way_is_action() {
    printf '%s\n' "$DOCTOR_WAYBAR_ACTIONS" | tr ' ' '\n' | grep -qxF -- "$1"
}

check_waybar() {
    group "Waybar"

    local config="$DOCTOR_ROOT/waybar/config.jsonc"
    local before_errors="$DOCTOR_ERRORS"
    local before_warnings="$DOCTOR_WARNINGS"
    local before_notices="$DOCTOR_NOTICES"
    local placed configured name cmd

    if [ ! -f "$config" ]; then
        note "no waybar/config.jsonc in $DOCTOR_ROOT — nothing to check" \
             "restore $(doctor_q "$config") if this clone is meant to have a bar"
        return 0
    fi

    placed="$(_way_placed "$config")"
    configured="$(_way_configured "$config")"

    # Process substitution, not a pipeline — see the contract note in lib.sh.
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        printf '%s\n' "$configured" | grep -qxF -- "$name" && continue

        case "$name" in
            custom/*)
                err "waybar places $name, which has no config block — a custom module without one has nothing to run" \
                    "add a \"$name\" block to $(doctor_q "$config"), or drop the name from the modules list"
                ;;
            *)
                warn "waybar places $name, which has no config block — it renders on waybar defaults, or the name is a typo waybar will drop" \
                     "add a \"$name\" block to $(doctor_q "$config"), or correct the name in the modules list"
                ;;
        esac
    done < <(printf '%s\n' "$placed")

    while IFS= read -r name; do
        [ -n "$name" ] || continue
        printf '%s\n' "$placed" | grep -qxF -- "$name" && continue
        note "waybar configures $name but places it in no modules list" \
             "add $name to a modules- list in $(doctor_q "$config"), or delete the block"
    done < <(printf '%s\n' "$configured")

    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue

        # references.sh owns every ~/.config path in a tracked file, and this
        # file is tracked. Both spellings, as configs write them.
        # shellcheck disable=SC2088
        case "$cmd" in
            '~/.config/'*|'$HOME/.config/'*) continue ;;
        esac

        _way_is_action "$cmd" && continue

        case "$cmd" in
            /*) [ -x "$cmd" ] && continue ;;
            *)  _way_have_cmd "$cmd" && continue ;;
        esac

        warn "waybar invokes $cmd, which is not installed" \
             "install the package providing $cmd, or change the handler in $(doctor_q "$config")"
    done < <(_way_commands "$config")

    # ok is the all-clear and nothing else — see the note in references.sh.
    if [ "$DOCTOR_ERRORS" -eq "$before_errors" ] &&
       [ "$DOCTOR_WARNINGS" -eq "$before_warnings" ] &&
       [ "$DOCTOR_NOTICES" -eq "$before_notices" ]; then
        ok "every waybar module is configured and every handler resolves"
    fi
}
```

- [ ] **Step 4: Register the module in doctor.sh**

At `doctor.sh:51`, change:

```bash
for _doctor_module in symlinks references binaries services; do
```

to:

```bash
for _doctor_module in symlinks references binaries services waybar; do
```

At `doctor.sh:70`, after the `check_services` line, add:

```bash
check_waybar
```

The loop stays a hand-written list on purpose: it is the module registry and it fixes report order, not a derived target list. Globbing it would silently reorder the four existing groups alphabetically.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
./scripts/doctor/test/run-tests.sh
```

Expected: PASS — `7 files, N assertions, 0 failures`, exit 0. The `▸ contract` block must still report `ok no pipeline-into-while in check modules`; if it fails, a `| while` crept into the new module.

- [ ] **Step 6: Verify against the live system**

```bash
./doctor.sh; echo "exit: $?"
```

Expected: a `▸ Waybar` group containing exactly one `· INFO` line — `waybar configures user but places it in no modules list` — and no ERROR or WARN in that group. No green tick in the group, since it has a finding. `exit: 0`.

- [ ] **Step 7: Lint**

```bash
shellcheck -S warning scripts/doctor/checks/waybar.sh scripts/doctor/test/test-waybar.sh doctor.sh
```

Expected: no output, exit 0.

- [ ] **Step 8: Commit**

```bash
git add scripts/doctor/checks/waybar.sh scripts/doctor/test/test-waybar.sh doctor.sh
git commit -m "feat(doctor): check that the bar's modules and handlers resolve

Nothing covered waybar. binaries.sh derives its targets from keybinds.conf and
autostart.conf, so the six binaries the bar's click handlers invoke were
unchecked, and nothing noticed a module placed without a config block.

Derived by grep and awk, not jq: config.jsonc is JSONC and jq will not parse
it. Handler paths under ~/.config are skipped, since references.sh already
scans every tracked file for those.

Reports one INFO on this repo today: the user block is placed nowhere."
```

---

### Task 3: Hook wiring

**Goal:** Committing a change under a suite's owning directory runs that suite, through `test.sh`, with no area names hardcoded in the hook.

**Files:**
- Modify: `scripts/hooks/pre-commit:49-58`

**Acceptance Criteria:**
- [ ] The hook contains no `^scripts/doctor/` literal
- [ ] Staging a `scripts/waybar/` change runs the battery suite and not the doctor suite
- [ ] Staging a `scripts/doctor/` change runs the doctor suite
- [ ] Staging a `rofi/` change runs neither the doctor nor the battery suite and does not block the commit — `test/test-runner.sh` owns the repo root and so runs on every commit by design
- [ ] A failing suite blocks the commit and prints that suite's output
- [ ] `shellcheck -S warning scripts/hooks/pre-commit` is silent

**Verify:** `git commit --dry-run` behaviour exercised by the manual steps below; `shellcheck -S warning scripts/hooks/pre-commit` → silent

**Steps:**

- [ ] **Step 1: Collect every staged path in the pass the hook already makes**

In `scripts/hooks/pre-commit`, replace the `STAGED_SH` collection block (lines 28-33):

```bash
STAGED_SH=()
while IFS= read -r -d '' _hook_file; do
    case "$_hook_file" in
        *.sh|scripts/hooks/*) STAGED_SH+=("$_hook_file") ;;
    esac
done < <(staged)
```

with one that fills both arrays in the same pass:

```bash
STAGED_SH=()
STAGED_ALL=()
while IFS= read -r -d '' _hook_file; do
    STAGED_ALL+=("$_hook_file")
    case "$_hook_file" in
        *.sh|scripts/hooks/*) STAGED_SH+=("$_hook_file") ;;
    esac
done < <(staged)
```

- [ ] **Step 2: Replace the doctor-only stanza with a runner call**

Replace lines 49-58 — the whole `--- doctor's own test suite ---` block:

```bash
# --- doctor's own test suite ---------------------------------------------
# The suite is fast (~1s) and its whole purpose is catching regressions in the
# checks. Run it whenever anything under scripts/doctor changes.
if staged | tr '\0' '\n' | grep -q '^scripts/doctor/'; then
    echo "pre-commit: doctor test suite"
    if ! "$REPO/scripts/doctor/test/run-tests.sh" >/dev/null 2>&1; then
        echo "pre-commit: doctor tests failed — run ./scripts/doctor/test/run-tests.sh to see why"
        FAILED=1
    fi
fi
```

with:

```bash
# --- test suites ----------------------------------------------------------
# Which suites cover which files is test.sh's business, not this hook's: the
# owning-directory rule lives there, so a new suite needs no edit here. Passing
# the staged paths keeps the existing principle that an unrelated pre-existing
# failure never blocks an unrelated commit.
#
# Output is NOT redirected. test.sh prints one line per suite and a failing
# suite's output in full, so there is no second command to suggest.
if [ "${#STAGED_ALL[@]}" -gt 0 ]; then
    if ! "$REPO/test.sh" --for "${STAGED_ALL[@]}"; then
        FAILED=1
    fi
fi
```

- [ ] **Step 3: Commit the hook change BEFORE running any probe**

Do the lint and commit (Steps 7 and 8 below) first, then return here. The probes undo themselves with `git reset --hard HEAD~1`, which discards working-tree changes to tracked files — so an uncommitted hook edit sitting alongside a probe commit is destroyed by the first undo. Committing first also means the probes exercise exactly the hook that will ship.

- [ ] **Step 4: Verify a waybar change runs only the battery suite**

```bash
printf '\n# gate probe\n' >> scripts/waybar/battery.sh
git add scripts/waybar/battery.sh
git commit -m "probe: hook selects the battery suite"
```

Expected: the hook prints `pre-commit: shellcheck (1 file(s))`, then `Testing …`, then green ticks for `scripts/waybar/test-battery.sh` and `test/test-runner.sh` — the latter owns the repo root and runs on every commit by design — and `2 suites passed`. `scripts/doctor/test/run-tests.sh` does **not** appear. The commit succeeds.

Then undo the probe commit, leaving the file as it was:

```bash
git reset --hard HEAD~1
git status --short
```

Expected: `git status --short` prints nothing.

- [ ] **Step 5: Verify an unrelated change runs neither area suite**

```bash
printf '\n' >> README.md
git add README.md
git commit -m "probe: hook runs no area suite for an unrelated file"
```

Expected: one green tick for `test/test-runner.sh` and `1 suite passed`. Neither `scripts/doctor/test/run-tests.sh` nor `scripts/waybar/test-battery.sh` appears, and the commit succeeds. The repo-root suite running here is by design — it is what gates a change to `test.sh` itself.

Then:

```bash
git reset --hard HEAD~1
```

- [ ] **Step 6: Verify a failing suite blocks the commit**

```bash
printf '\nexit 1\n' >> scripts/waybar/test-battery.sh
git add scripts/waybar/test-battery.sh
git commit -m "probe: a failing suite blocks the commit"
```

Expected: `✗ scripts/waybar/test-battery.sh` with its output beneath, then `pre-commit: checks failed. Fix the issues above, or bypass with --no-verify.` and a non-zero exit — **the commit does not happen**. Confirm with `git log --oneline -1` showing the previous commit.

Then:

```bash
git restore --staged scripts/waybar/test-battery.sh
git checkout -- scripts/waybar/test-battery.sh
git status --short
```

Expected: `git status --short` prints nothing.

- [ ] **Step 7: Lint**

```bash
shellcheck -S warning scripts/hooks/pre-commit
```

Expected: no output, exit 0.

- [ ] **Step 8: Commit**

```bash
git add scripts/hooks/pre-commit
git commit -m "feat(hooks): run the suites covering the staged files

The hook no longer names scripts/doctor/. It hands the staged paths to
test.sh, which owns the file-area-to-suite mapping, so a new suite is picked
up with no edit here -- and scripts/waybar/test-battery.sh is now gated.

Output is no longer sent to /dev/null: test.sh prints a failing suite's output
in full, so the 'run X to see why' hint had nothing left to say."
```

---

### Task 4: Documentation

**Goal:** Every place that describes the test setup describes the one that now exists.

**Files:**
- Modify: `install.sh:291`
- Modify: `README.md:135-140`
- Modify: `CLAUDE.md` (Key Commands, doctor tree, conventions)
- Modify: `scripts/waybar/test-battery.sh:8`

**Acceptance Criteria:**
- [ ] No tracked file claims the hook runs only "doctor tests"
- [ ] `CLAUDE.md` Key Commands lists `./test.sh`
- [ ] `CLAUDE.md`'s doctor tree includes `waybar.sh` and `test-waybar.sh`
- [ ] `CLAUDE.md` states the discovery convention
- [ ] `test-battery.sh`'s header records the answer to the question it poses
- [ ] `./doctor.sh` reports no new reference findings from the edited docs

**Verify:** `grep -rn "doctor tests\|doctor's test suite" install.sh README.md CLAUDE.md` → no stale claim remains

**Steps:**

- [ ] **Step 1: Update install.sh**

At `install.sh:291`, change:

```bash
    success "Pre-commit gate active (shellcheck + doctor tests + ags bundle)"
```

to:

```bash
    success "Pre-commit gate active (shellcheck + test suites + ags bundle)"
```

- [ ] **Step 2: Update README.md**

Replace the paragraph at lines 135-140:

```markdown
A pre-commit hook (`scripts/hooks/pre-commit`, activated by `install.sh` via
`core.hooksPath`) runs `shellcheck` on staged shell scripts, the doctor's test
suite when `scripts/doctor/` changes, and `ags bundle` on staged panel
sources. Bypass with `git commit --no-verify`.

Run the doctor's own tests with `./scripts/doctor/test/run-tests.sh`.
```

with:

```markdown
A pre-commit hook (`scripts/hooks/pre-commit`, activated by `install.sh` via
`core.hooksPath`) runs `shellcheck` on staged shell scripts, the test suites
covering whatever the commit touches, and `ags bundle` on staged panel
sources. Bypass with `git commit --no-verify`.

Run every test suite with `./test.sh`, or `./test.sh --list` to see what it
found. Each suite is still runnable on its own —
`./scripts/doctor/test/run-tests.sh`, `./scripts/waybar/test-battery.sh`.
```

- [ ] **Step 3: Update CLAUDE.md Key Commands**

Replace these two lines in the Key Commands block:

```bash
# Run the doctor's own test suite
./scripts/doctor/test/run-tests.sh
```

with:

```bash
# Run every test suite in the repo (or --list to see which ones exist)
./test.sh
```

- [ ] **Step 4: Update CLAUDE.md's doctor tree**

In the `## Doctor Architecture` block, add the two new files:

```
├── checks/
│   ├── symlinks.sh          # check_symlinks   — from `git ls-files -s` mode 120000
│   ├── references.sh        # check_references — from `source =` lines and literal ~/.config paths
│   ├── binaries.sh          # check_binaries   — from keybinds.conf `exec,` and autostart `exec-once`
│   ├── services.sh          # check_services   — from autostart daemons, D-Bus roles, install.sh arrays
│   └── waybar.sh            # check_waybar     — from config.jsonc's modules-* arrays and handler values
└── test/
    ├── run-tests.sh         # Dependency-free harness; auto-discovers test-*.sh
    └── test-*.sh            # One per module, sourced into one shared shell
```

- [ ] **Step 5: Add the discovery convention to CLAUDE.md**

Add to the `## Conventions` list:

```markdown
- `./test.sh` discovers suites rather than listing them: a tracked file is an
  entry point if it is named `run-tests.sh`, or matches `test-*.sh` and its
  directory has no `run-tests.sh`. Name a new suite either way and it is picked
  up — by the runner and by the pre-commit hook — with no registration step. A
  suite's *owning directory* is its own directory minus a trailing `test/`
  component, and that is what decides which commits run it; `test/` at the top
  level maps to the whole repo, which is why `test/test-runner.sh` runs on
  every commit.
```

- [ ] **Step 6: Update the battery suite's header**

In `scripts/waybar/test-battery.sh`, replace lines 5-9:

```bash
# Standalone and runnable on its own, exit 1 on any failure. It executes the
# script under test as a subprocess, because that is exactly how waybar runs
# it -- unlike scripts/doctor/test/test-*.sh, which are sourced fragments
# sharing one shell so that severity counters survive. Chunk D decides whether
# the two styles get one runner.
```

with:

```bash
# Standalone and runnable on its own, exit 1 on any failure. It executes the
# script under test as a subprocess, because that is exactly how waybar runs
# it -- unlike scripts/doctor/test/test-*.sh, which are sourced fragments
# sharing one shell so that severity counters survive. Both styles are kept:
# ../../test.sh runs each suite as a subprocess and asks nothing of it beyond
# an exit code, so neither had to be rewritten to fit the other.
```

- [ ] **Step 7: Verify nothing stale is left, and the doctor is unaffected**

```bash
grep -rn "doctor tests\|doctor's test suite" install.sh README.md CLAUDE.md
./doctor.sh; echo "exit: $?"
./test.sh
```

Expected: the grep prints nothing. `./doctor.sh` still reports exactly one Waybar INFO and no new Config-references findings, `exit: 0`. `./test.sh` reports `3 suites passed`.

- [ ] **Step 8: Commit**

```bash
git add install.sh README.md CLAUDE.md scripts/waybar/test-battery.sh
git commit -m "docs: describe the test runner that now exists

Four files claimed the pre-commit gate ran 'doctor tests', and test-battery.sh
still posed the question of whether the two test styles would get one runner.
They do, and it asks nothing of either style beyond an exit code."
```

---

## Post-Implementation Verification

Run in order once all four tasks are done:

```bash
./test.sh --list          # 3 suites, owners scripts/doctor/, scripts/waybar/, (repo root)
./test.sh                 # 3 suites passed, exit 0
./doctor.sh; echo $?      # Waybar group, exactly one INFO (user), exit 0
git ls-files -z '*.sh' | xargs -0 shellcheck -f gcc -S warning | wc -l   # 0
```

The last one guards the repo-wide invariant this work must not break: `shellcheck -S warning` was clean across all 56 tracked scripts before it started.
