# Dotfiles Doctor & Lint Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a report-only `doctor.sh` that validates the live Hyprland setup by deriving every check from tracked files, plus a `core.hooksPath` pre-commit gate running shellcheck and `ags bundle`.

**Architecture:** A thin top-level entry point sources a reporting library and four independent check modules, each owning one category (symlinks, references, binaries, services). Every module derives its targets from tracked files — git symlink modes, `source =` lines, `exec,` targets, `install.sh` package arrays — so no manifest exists to drift. A `DOCTOR_ROOT` environment override lets the whole suite run against throwaway fixture repos, which is what makes it testable.

**Tech Stack:** Bash 5, git plumbing (`git ls-files -s`), `busctl` (systemd DBus), `pacman`, `shellcheck`, `ags bundle`. No test framework — a dependency-free harness ships with the checks.

**Spec:** `docs/superpowers/specs/2026-07-25-dotfiles-doctor-design.md`

---

## File Structure

| File | Responsibility |
|---|---|
| `doctor.sh` | Entry point. Arg parsing, sources lib + modules, runs checks in order, prints summary, sets exit code. |
| `scripts/doctor/lib.sh` | Reporting primitives (`group`/`ok`/`err`/`warn`/`note`/`summary`), severity counters, `DOCTOR_ROOT` resolution. No checks. |
| `scripts/doctor/checks/symlinks.sh` | `check_symlinks` — dangling and non-portable tracked symlinks. |
| `scripts/doctor/checks/references.sh` | `check_references` — `source =` targets, literal `~/.config` paths, `wall.sh` color scripts, pywal cache. |
| `scripts/doctor/checks/binaries.sh` | `check_binaries` — Hyprland variable resolution, keybind and autostart binaries. |
| `scripts/doctor/checks/services.sh` | `check_services` — autostart daemons, notification-daemon DBus ownership, `install.sh` package drift. |
| `scripts/doctor/test/run-tests.sh` | Dependency-free harness: assertion helpers, fixture builder, runs all test files. |
| `scripts/doctor/test/test-*.sh` | One test file per check module, sourced by the harness. |
| `scripts/hooks/pre-commit` | Staged-file gate: shellcheck on `*.sh`, `ags bundle` on `ags/**`. |

### Module contract

Every check module:

1. Defines exactly one function, `check_<name>`, and defines nothing else at source time.
2. Uses only `lib.sh` primitives for output. It never calls `echo` for findings directly.
3. Reads the tree at `$DOCTOR_ROOT`, never a hardcoded `$HOME/.config`.
4. **Never runs its main loop in a pipeline or subshell.** Severity counters are shell variables; `cmd | while read` would increment them in a subshell and silently lose every finding. Always use `while read ...; do ... done < <(cmd)`.

Rule 4 is the single most likely way to break this codebase. It is restated in `lib.sh`'s header comment.

### Two deliberate deviations from the spec

**1. `doctor.sh` does not use `set -e`.** `install.sh` does, but doctor must survive a failing check and still print the summary — aborting on the first non-zero return would defeat the entire report. It uses `set -uo pipefail` instead. Task 6 documents this inline.

**2. The generic "orphan config" rule is narrowed to notification daemons.** The spec's derivation table proposed: *tracked config dir + no autostart entry + no running process → INFO*. Applied literally, that fires on `btop/`, `cava/`, `yazi`, `bottom/`, `fastfetch/` — every on-demand CLI tool, none of which is an orphan. The rule would produce more false positives than findings and train the user to ignore output, which the spec's own severity section warns against.

Narrowed rule, implemented in Task 5: for the single-owner DBus role `org.freedesktop.Notifications`, report the owner (INFO) and flag any *other* installed package that provides `notification-daemon` and has a tracked config dir (INFO orphan). This is exact, has zero false positives, and still catches the mako finding the spec was written around. Extending it to other single-owner roles (polkit agent, idle daemon) is a one-line addition to a table, noted in the code.

**3. `lib.sh` defines its own output helpers rather than sourcing `install.sh`'s.** The spec says doctor "reuses `install.sh`'s existing `info`/`warning`/`success` helpers so the two entry points look like one tool." That is not achievable literally — `install.sh` is not sourceable: it runs `set -e`, parses arguments, prints a banner, and begins installing at source time. `lib.sh` instead duplicates the same colour constants and glyph vocabulary, so the two look identical on screen without doctor being able to accidentally run an install. The spec's *intent* (visual consistency) is met; its stated *mechanism* is not.

---

### Task 1: Reporting library and test harness

**Goal:** Severity-tracking output primitives and a dependency-free test harness, both verified by tests.

**Files:**
- Create: `scripts/doctor/lib.sh`
- Create: `scripts/doctor/test/run-tests.sh`
- Create: `scripts/doctor/test/test-lib.sh`

**Acceptance Criteria:**
- [ ] `err`/`warn`/`note` each increment their own counter and print severity-tagged lines
- [ ] A second argument to any of them prints an indented `fix:` line; omitting it prints no fix line
- [ ] `summary` returns 1 when errors > 0, returns 0 when only warnings/notices exist
- [ ] Counters survive across many calls in the same shell
- [ ] `run-tests.sh` exits 0 when all assertions pass, 1 when any fails
- [ ] `shellcheck -S warning` passes on all three files

**Verify:** `./scripts/doctor/test/run-tests.sh` → `3 files, N assertions, 0 failures`, exit 0

**Steps:**

- [ ] **Step 1: Write the test harness**

Create `scripts/doctor/test/run-tests.sh`:

```bash
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
```

- [ ] **Step 2: Write the failing test for lib.sh**

Create `scripts/doctor/test/test-lib.sh`:

```bash
# Tests for scripts/doctor/lib.sh — sourced by run-tests.sh

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"

# --- severity counters ---
doctor_reset
out="$(err "broken thing" "run the fix" 2>&1)"
assert_contains "$out" "ERROR" "err prints ERROR tag"
assert_contains "$out" "broken thing" "err prints the message"
assert_contains "$out" "fix: run the fix" "err prints the fix hint"
assert_eq "$DOCTOR_ERRORS" "1" "err increments error counter"

doctor_reset
out="$(warn "degraded thing" 2>&1)"
assert_contains "$out" "WARN" "warn prints WARN tag"
assert_not_contains "$out" "fix:" "warn omits fix line when no hint given"
assert_eq "$DOCTOR_WARNINGS" "1" "warn increments warning counter"

doctor_reset
note "tidy thing" >/dev/null 2>&1
note "another" >/dev/null 2>&1
assert_eq "$DOCTOR_NOTICES" "2" "note counter accumulates"

# --- exit code semantics ---
doctor_reset
warn "just a warning" >/dev/null 2>&1
note "just a notice" >/dev/null 2>&1
summary >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "$rc" "0" "summary exits 0 when no errors"

doctor_reset
err "a real error" >/dev/null 2>&1
summary >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "$rc" "1" "summary exits 1 when errors present"

doctor_reset
out="$(err "e" >/dev/null 2>&1; warn "w" >/dev/null 2>&1; summary 2>&1)"
assert_contains "$out" "1 error" "summary reports error count"

# --- DOCTOR_ROOT override ---
assert_eq "${DOCTOR_ROOT:+set}" "set" "DOCTOR_ROOT is always defined"
```

- [ ] **Step 3: Run the test, verify it fails**

Run: `chmod +x scripts/doctor/test/run-tests.sh && ./scripts/doctor/test/run-tests.sh`
Expected: FAIL — `lib.sh: No such file or directory`

- [ ] **Step 4: Write lib.sh**

Create `scripts/doctor/lib.sh`:

```bash
#!/bin/bash
#
# Reporting primitives for doctor.sh checks.
#
# CONTRACT FOR CHECK MODULES:
#   Never run a check loop in a pipeline or subshell. The severity counters
#   below are plain shell variables, so `cmd | while read` increments them in
#   a subshell and every finding is silently discarded. Always write:
#       while read -r x; do ... done < <(cmd)
#

# Root of the dotfiles tree under test. Overridable so the test suite can point
# the checks at a throwaway fixture repo instead of the live system.
DOCTOR_ROOT="${DOCTOR_ROOT:-$HOME/.config}"

DOCTOR_RED='\033[0;31m'
DOCTOR_GREEN='\033[0;32m'
DOCTOR_YELLOW='\033[1;33m'
DOCTOR_BLUE='\033[0;34m'
DOCTOR_DIM='\033[2m'
DOCTOR_NC='\033[0m'

DOCTOR_ERRORS=0
DOCTOR_WARNINGS=0
DOCTOR_NOTICES=0

doctor_reset() {
    DOCTOR_ERRORS=0
    DOCTOR_WARNINGS=0
    DOCTOR_NOTICES=0
}

group() {
    echo
    echo -e "${DOCTOR_BLUE}▸${DOCTOR_NC} $1"
}

ok() {
    echo -e "  ${DOCTOR_GREEN}✓${DOCTOR_NC} $1"
}

# _finding <colored-tag> <message> [fix-hint]
_finding() {
    echo -e "  $1  $2"
    if [ -n "${3:-}" ]; then
        echo -e "           ${DOCTOR_DIM}fix: $3${DOCTOR_NC}"
    fi
}

err() {
    DOCTOR_ERRORS=$((DOCTOR_ERRORS + 1))
    _finding "${DOCTOR_RED}✗ ERROR${DOCTOR_NC}" "$1" "${2:-}"
}

warn() {
    DOCTOR_WARNINGS=$((DOCTOR_WARNINGS + 1))
    _finding "${DOCTOR_YELLOW}! WARN ${DOCTOR_NC}" "$1" "${2:-}"
}

note() {
    DOCTOR_NOTICES=$((DOCTOR_NOTICES + 1))
    _finding "${DOCTOR_DIM}· INFO ${DOCTOR_NC}" "$1" "${2:-}"
}

# Prints the tally. Returns 1 if any ERROR was recorded, else 0.
summary() {
    local e="$DOCTOR_ERRORS" w="$DOCTOR_WARNINGS" n="$DOCTOR_NOTICES"
    echo
    echo "$e error$([ "$e" -eq 1 ] || echo s), $w warning$([ "$w" -eq 1 ] || echo s), $n notice$([ "$n" -eq 1 ] || echo s)"
    if [ "$e" -gt 0 ]; then
        return 1
    fi
    return 0
}
```

- [ ] **Step 5: Run the test, verify it passes**

Run: `./scripts/doctor/test/run-tests.sh`
Expected: PASS — `1 files, 13 assertions, 0 failures`, exit 0

- [ ] **Step 6: Lint**

Run: `shellcheck -S warning scripts/doctor/lib.sh scripts/doctor/test/run-tests.sh`
Expected: no output, exit 0

- [ ] **Step 7: Commit**

```bash
git add scripts/doctor/lib.sh scripts/doctor/test/
git commit -m "feat(doctor): reporting primitives and test harness"
```

---

### Task 2: Symlink checks

**Goal:** Detect dangling tracked symlinks (ERROR) and username-hardcoding absolute targets (WARN), deriving the symlink list from git rather than any hand-written list.

**Files:**
- Create: `scripts/doctor/checks/symlinks.sh`
- Create: `scripts/doctor/test/test-symlinks.sh`

**Acceptance Criteria:**
- [ ] Symlink list comes from `git ls-files -s` mode `120000` — no path is enumerated in code
- [ ] A dangling symlink produces ERROR
- [ ] A resolving symlink whose target starts with `/home/` produces WARN
- [ ] A resolving relative symlink produces no finding
- [ ] A count of healthy symlinks is printed via `ok`
- [ ] Counters are non-zero after the check (proves no subshell loss)

**Verify:** `./scripts/doctor/test/run-tests.sh` → `0 failures`, exit 0

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `scripts/doctor/test/test-symlinks.sh`:

```bash
# Tests for scripts/doctor/checks/symlinks.sh

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/symlinks.sh"

fixture="$(make_fixture)"
FIXTURES+=("$fixture")

mkdir -p "$fixture/target-dir" "$fixture/sub"
echo "real" > "$fixture/target-dir/real-file"

ln -s "../target-dir/real-file" "$fixture/sub/good-relative"
ln -s "/home/someone/nowhere/missing-file" "$fixture/sub/absolute-dangling"
ln -s "../target-dir/nonexistent" "$fixture/sub/relative-dangling"
ln -s "$fixture/target-dir/real-file" "$fixture/sub/absolute-resolving"

git -C "$fixture" add -A
git -C "$fixture" commit -qm "fixture"

DOCTOR_ROOT="$fixture"
doctor_reset
out="$(check_symlinks 2>&1)"
# Re-run outside the subshell so the counters are observable.
doctor_reset
check_symlinks >/dev/null 2>&1

assert_contains "$out" "relative-dangling" "dangling relative symlink is reported"
assert_contains "$out" "ERROR" "dangling symlink is ERROR severity"
assert_contains "$out" "absolute-resolving" "absolute-but-resolving symlink is reported"
assert_contains "$out" "WARN" "absolute symlink is WARN severity"
assert_not_contains "$out" "good-relative" "healthy relative symlink produces no finding"

assert_eq "$DOCTOR_ERRORS" "2" "two dangling symlinks counted as errors"
assert_eq "$DOCTOR_WARNINGS" "1" "one absolute resolving symlink counted as warning"

DOCTOR_ROOT="${HOME}/.config"
```

Note: `absolute-dangling` is both absolute and dangling; the check reports dangling first and does not double-count, so errors = 2 (`absolute-dangling` + `relative-dangling`) and warnings = 1 (`absolute-resolving` only).

- [ ] **Step 2: Run the test, verify it fails**

Run: `./scripts/doctor/test/run-tests.sh`
Expected: FAIL — `checks/symlinks.sh: No such file or directory`

- [ ] **Step 3: Write the check**

Create `scripts/doctor/checks/symlinks.sh`:

```bash
#!/bin/bash
#
# Symlink integrity. The list of symlinks is derived from git itself:
# `git ls-files -s` reports mode 120000 for every tracked symlink, so no
# path is ever enumerated here and new symlinks are covered automatically.
#

check_symlinks() {
    group "Symlinks"

    local total=0 healthy=0
    local mode _object _stage path target

    # Process substitution, not a pipe — see the contract note in lib.sh.
    while read -r mode _object _stage path; do
        [ "$mode" = "120000" ] || continue
        total=$((total + 1))
        target="$(readlink "$DOCTOR_ROOT/$path" 2>/dev/null)"

        if [ ! -e "$DOCTOR_ROOT/$path" ]; then
            err "$path → $target (dangling)" \
                "recreate the target, or: ln -sfn <correct-target> $DOCTOR_ROOT/$path"
        elif [[ "$target" == /home/* ]]; then
            warn "$path → $target (absolute path hardcodes a username)" \
                 "repoint at a relative target: ln -sfn <relative-path> $DOCTOR_ROOT/$path"
        else
            healthy=$((healthy + 1))
        fi
    done < <(git -C "$DOCTOR_ROOT" ls-files -s)

    if [ "$total" -eq 0 ]; then
        warn "no tracked symlinks found — is $DOCTOR_ROOT a git repository?"
    else
        ok "$healthy of $total tracked symlinks are healthy and portable"
    fi
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `./scripts/doctor/test/run-tests.sh`
Expected: PASS — `2 files, N assertions, 0 failures`

- [ ] **Step 5: Lint**

Run: `shellcheck -S warning scripts/doctor/checks/symlinks.sh`
Expected: no output, exit 0

- [ ] **Step 6: Commit**

```bash
git add scripts/doctor/checks/symlinks.sh scripts/doctor/test/test-symlinks.sh
git commit -m "feat(doctor): dangling and non-portable symlink checks"
```

---

### Task 3: Config reference checks

**Goal:** Verify every `source =` target, every literal `~/.config` path referenced in a tracked file, the `wall.sh` color-script fan-out, and the pywal cache.

**Files:**
- Create: `scripts/doctor/checks/references.sh`
- Create: `scripts/doctor/test/test-references.sh`

**Acceptance Criteria:**
- [ ] A missing `source =` target in `hypr/hyprland.conf` produces ERROR
- [ ] A missing literal `$HOME/.config/...` path referenced by a tracked file produces ERROR
- [ ] `docs/` and `*.md` files are excluded from literal-path scanning (they contain illustrative paths)
- [ ] Paths still containing an unresolved `$` or a glob are skipped, not reported
- [ ] A missing `wall.sh` color script produces WARN (wall.sh existence-checks them)
- [ ] A missing `~/.cache/wal/colors-hyprland.conf` produces ERROR

**Verify:** `./scripts/doctor/test/run-tests.sh` → `0 failures`, exit 0

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `scripts/doctor/test/test-references.sh`:

```bash
# Tests for scripts/doctor/checks/references.sh

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/references.sh"

fixture="$(make_fixture)"
FIXTURES+=("$fixture")

mkdir -p "$fixture/hypr/config" "$fixture/scripts/hyprland" "$fixture/docs" "$fixture/present"

cat > "$fixture/hypr/hyprland.conf" <<'EOF'
source = config/present.conf
source = config/absent.conf
EOF
echo "# present" > "$fixture/hypr/config/present.conf"

cat > "$fixture/scripts/hyprland/wall.sh" <<'EOF'
#!/bin/bash
for script in \
    "$HOME/.config/present/apply_wal_colors.sh" \
    "$HOME/.config/absent/apply_wal_colors.sh" \
    ; do
    [ -x "$script" ] && "$script"
done
EOF
echo "#!/bin/bash" > "$fixture/present/apply_wal_colors.sh"

cat > "$fixture/scripts/hyprland/refs.sh" <<'EOF'
#!/bin/bash
cat "$HOME/.config/present/apply_wal_colors.sh"
cat "$HOME/.config/missing-thing/file"
glob="$HOME/.config/present/*.sh"
var="$HOME/.config/$SOMETHING/file"
EOF

# docs/ must be excluded — it references paths that need not exist
echo 'see $HOME/.config/imaginary/path for details' > "$fixture/docs/notes.md"

git -C "$fixture" add -A
git -C "$fixture" commit -qm "fixture"

DOCTOR_ROOT="$fixture"
DOCTOR_CACHE="$fixture/fake-cache"    # stand-in for ~/.cache/wal
mkdir -p "$DOCTOR_CACHE/wal"

doctor_reset
out="$(check_references 2>&1)"

assert_contains "$out" "config/absent.conf" "missing source target is reported"
assert_contains "$out" "missing-thing" "missing literal ~/.config path is reported"
assert_not_contains "$out" "imaginary" "docs/ paths are excluded from scanning"
assert_not_contains "$out" "SOMETHING" "paths with unresolved variables are skipped"
assert_not_contains "$out" "*.sh" "glob paths are skipped"
assert_contains "$out" "absent/apply_wal_colors.sh" "missing wall.sh color script is reported"
assert_contains "$out" "colors-hyprland.conf" "missing pywal cache is reported"

doctor_reset
check_references >/dev/null 2>&1
assert_eq "$DOCTOR_ERRORS" "3" "source target, literal path, and pywal cache are errors"
assert_eq "$DOCTOR_WARNINGS" "1" "missing wall.sh color script is a warning"

unset DOCTOR_CACHE
DOCTOR_ROOT="${HOME}/.config"
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `./scripts/doctor/test/run-tests.sh`
Expected: FAIL — `checks/references.sh: No such file or directory`

- [ ] **Step 3: Write the check**

Create `scripts/doctor/checks/references.sh`:

```bash
#!/bin/bash
#
# Config reference integrity: every path a tracked file points at must exist.
# Targets are extracted from the configs themselves, never listed here.
#

# Cache root, overridable for tests.
DOCTOR_CACHE="${DOCTOR_CACHE:-$HOME/.cache}"

# _check_source_lines <conf-file-relative-to-root> <base-dir-relative-to-root>
# Hyprland resolves `source =` relative to the sourcing file's directory.
_check_source_lines() {
    local conf="$1" base="$2" target
    [ -f "$DOCTOR_ROOT/$conf" ] || return 0

    while read -r target; do
        [ -n "$target" ] || continue
        if [ ! -e "$DOCTOR_ROOT/$base/$target" ]; then
            err "$conf sources $target, which does not exist" \
                "create $DOCTOR_ROOT/$base/$target or remove the source line"
        fi
    done < <(sed -n 's/^[[:space:]]*source[[:space:]]*=[[:space:]]*//p' "$DOCTOR_ROOT/$conf" | sed 's/[[:space:]]*#.*//')
}

check_references() {
    group "Config references"

    local before_errors="$DOCTOR_ERRORS"

    # 1. Hyprland source chains
    _check_source_lines "hypr/hyprland.conf" "hypr"
    _check_source_lines "hypr/hyprlock.conf" "hypr"

    # 2. Literal ~/.config paths referenced anywhere in tracked files.
    #    docs/ and *.md are excluded: plans and specs cite illustrative paths
    #    that intentionally do not exist.
    local file path rel
    while read -r file; do
        case "$file" in
            docs/*|*.md) continue ;;
        esac
        [ -f "$DOCTOR_ROOT/$file" ] || continue

        while read -r path; do
            [ -n "$path" ] || continue
            # Skip anything still holding a variable or a glob — not resolvable.
            case "$path" in
                *'$'*|*'*'*|*'?'*) continue ;;
            esac
            rel="${path#*/.config/}"
            if [ ! -e "$DOCTOR_ROOT/$rel" ]; then
                err "$file references ~/.config/$rel, which does not exist" \
                    "create it, or drop the reference from $file"
            fi
        done < <(grep -oE '(\$HOME|~)/\.config/[A-Za-z0-9._/-]+' "$DOCTOR_ROOT/$file" 2>/dev/null | sort -u)
    done < <(git -C "$DOCTOR_ROOT" ls-files)

    # 3. wall.sh colour fan-out. wall.sh existence-checks these, so a missing
    #    one degrades theming rather than breaking the session -> WARN.
    local wall="scripts/hyprland/wall.sh" script
    if [ -f "$DOCTOR_ROOT/$wall" ]; then
        while read -r script; do
            rel="${script#*/.config/}"
            if [ ! -e "$DOCTOR_ROOT/$rel" ]; then
                warn "$wall applies colours via ~/.config/$rel, which is missing" \
                     "restore the script or remove it from the list in $wall"
            fi
        done < <(grep -oE '(\$HOME|~)/\.config/[A-Za-z0-9._/-]+apply_wal_colors\.sh' "$DOCTOR_ROOT/$wall" | sort -u)
    fi

    # 4. The pywal cache every colour symlink depends on.
    if [ ! -e "$DOCTOR_CACHE/wal/colors-hyprland.conf" ]; then
        err "pywal cache missing: $DOCTOR_CACHE/wal/colors-hyprland.conf" \
            "wal -i \"\$(readlink -f $DOCTOR_ROOT/options/wallpaper)\""
    fi

    if [ "$DOCTOR_ERRORS" -eq "$before_errors" ]; then
        ok "all config references resolve"
    fi
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `./scripts/doctor/test/run-tests.sh`
Expected: PASS — `3 files, N assertions, 0 failures`

- [ ] **Step 5: Lint**

Run: `shellcheck -S warning scripts/doctor/checks/references.sh`
Expected: no output, exit 0

- [ ] **Step 6: Commit**

```bash
git add scripts/doctor/checks/references.sh scripts/doctor/test/test-references.sh
git commit -m "feat(doctor): config reference and pywal cache checks"
```

---

### Task 4: Binary reference checks

**Goal:** Resolve Hyprland's `$variable` indirection the way Hyprland does, then verify every binary invoked by a keybind or autostart entry exists on PATH.

**Files:**
- Create: `scripts/doctor/checks/binaries.sh`
- Create: `scripts/doctor/test/test-binaries.sh`

**Acceptance Criteria:**
- [ ] `$terminal` and `$browser` resolve from `options/`
- [ ] `$fileManager`, `$textEditor`, `$polkitAgent` resolve from `hypr/config/apptype.conf`, with trailing comments stripped
- [ ] A keybind invoking an absent binary produces WARN
- [ ] An `exec-once` invoking an absent binary produces WARN
- [ ] A keybind whose target is a path (`~/.config/...`) is skipped — Task 3 owns those
- [ ] An unresolvable `$variable` produces WARN
- [ ] Each missing binary is reported once even if bound several times

**Verify:** `./scripts/doctor/test/run-tests.sh` → `0 failures`, exit 0

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `scripts/doctor/test/test-binaries.sh`:

```bash
# Tests for scripts/doctor/checks/binaries.sh

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/binaries.sh"

fixture="$(make_fixture)"
FIXTURES+=("$fixture")

mkdir -p "$fixture/hypr/config/software" "$fixture/hypr/config/setup" "$fixture/options"

echo "bash" > "$fixture/options/terminal"
echo "definitely-not-a-real-binary-xyz" > "$fixture/options/browser"

cat > "$fixture/hypr/config/apptype.conf" <<'EOF'
$fileManager = ls        # GUI file manager
$textEditor = cat        # Text editor
$polkitAgent = also-not-real-abc  # Authentication agent
EOF

cat > "$fixture/hypr/config/software/keybinds.conf" <<'EOF'
bind = $Mod, RETURN, exec, $terminal
bind = $Mod, B, exec, $browser
bind = $Mod, E, exec, $fileManager
bind = $Mod, X, exec, another-missing-binary-qq
bind = $Mod, Y, exec, another-missing-binary-qq --flag
bind = $Mod, A, exec, ~/.config/scripts/thing.sh
bind = $Mod, Z, exec, $undefinedVariable
EOF

cat > "$fixture/hypr/config/setup/autostart.conf" <<'EOF'
exec-once = env
exec-once = missing-daemon-jj &
exec-once = $polkitAgent
exec-once = $HOME/.config/scripts/hyprland/startup.sh
EOF

git -C "$fixture" add -A
git -C "$fixture" commit -qm "fixture"

DOCTOR_ROOT="$fixture"

# --- variable resolution ---
assert_eq "$(_resolve_hypr_var terminal)" "bash" "\$terminal resolves from options/"
assert_eq "$(_resolve_hypr_var fileManager)" "ls" "\$fileManager resolves from apptype.conf"
assert_eq "$(_resolve_hypr_var textEditor)" "cat" "trailing comment is stripped"
assert_eq "$(_resolve_hypr_var undefinedVariable)" "" "unknown variable resolves to empty"

# --- findings ---
doctor_reset
out="$(check_binaries 2>&1)"

assert_contains "$out" "definitely-not-a-real-binary-xyz" "missing \$browser binary reported"
assert_contains "$out" "another-missing-binary-qq" "missing literal keybind binary reported"
assert_contains "$out" "missing-daemon-jj" "missing autostart binary reported"
assert_contains "$out" "also-not-real-abc" "missing \$polkitAgent binary reported"
assert_contains "$out" "undefinedVariable" "unresolvable variable reported"
assert_not_contains "$out" "scripts/thing.sh" "path targets are left to the reference check"
assert_not_contains "$out" " bash" "present binary produces no finding"

# reported once, not twice, despite two binds
count="$(printf '%s' "$out" | grep -c "another-missing-binary-qq")"
assert_eq "$count" "1" "duplicate binds report the binary once"

DOCTOR_ROOT="${HOME}/.config"
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `./scripts/doctor/test/run-tests.sh`
Expected: FAIL — `checks/binaries.sh: No such file or directory`

- [ ] **Step 3: Write the check**

Create `scripts/doctor/checks/binaries.sh`:

```bash
#!/bin/bash
#
# Binary availability for everything the keybinds and autostart invoke.
#
# Scripts under scripts/ are deliberately NOT scanned for the commands they
# call: reliably extracting invocations from bash defeats naive parsing, and
# the repo's scripts already guard with `command -v`. Their paths are still
# validated by the reference check.
#

# _resolve_hypr_var <name> -> value, or empty if undefined
# Mirrors how Hyprland resolves the variables used in keybinds.conf.
_resolve_hypr_var() {
    local name="$1" value=""
    case "$name" in
        terminal|browser)
            if [ -f "$DOCTOR_ROOT/options/$name" ]; then
                value="$(head -n1 "$DOCTOR_ROOT/options/$name")"
            fi
            ;;
        *)
            if [ -f "$DOCTOR_ROOT/hypr/config/apptype.conf" ]; then
                value="$(sed -n "s/^\\\$$name[[:space:]]*=[[:space:]]*//p" \
                    "$DOCTOR_ROOT/hypr/config/apptype.conf" | head -n1)"
                value="${value%%#*}"
            fi
            ;;
    esac
    # Trim surrounding whitespace.
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

# _check_command <raw-command-string> <source-label> <seen-list-name>
_check_command() {
    local raw="$1" origin="$2" seen_var="$3"
    local first bin

    # First token only; strip a trailing `&`.
    raw="${raw%&}"
    read -r first _ <<< "$raw"
    [ -n "$first" ] || return 0

    # Paths belong to the reference check, not here.
    case "$first" in
        /*|~/*|'$HOME'/*) return 0 ;;
    esac

    if [[ "$first" == \$* ]]; then
        bin="$(_resolve_hypr_var "${first#\$}")"
        if [ -z "$bin" ]; then
            warn "$origin invokes $first, which is not defined anywhere" \
                 "define it in hypr/config/apptype.conf or options/"
            return 0
        fi
    else
        bin="$first"
    fi

    # Report each missing binary once.
    local seen="${!seen_var}"
    case " $seen " in
        *" $bin "*) return 0 ;;
    esac
    printf -v "$seen_var" '%s' "$seen $bin"

    if ! command -v "$bin" >/dev/null 2>&1; then
        warn "$origin invokes '$bin', which is not installed" \
             "pacman -S $bin   (or update the config to drop it)"
    fi
}

check_binaries() {
    group "Binaries"

    local before="$DOCTOR_WARNINGS"
    local seen="" line

    local keybinds="hypr/config/software/keybinds.conf"
    if [ -f "$DOCTOR_ROOT/$keybinds" ]; then
        while read -r line; do
            _check_command "$line" "$keybinds" seen
        done < <(sed -n 's/^[[:space:]]*bind[a-z]*[[:space:]]*=.*[[:space:]]exec,[[:space:]]*//p' "$DOCTOR_ROOT/$keybinds")
    fi

    local autostart="hypr/config/setup/autostart.conf"
    if [ -f "$DOCTOR_ROOT/$autostart" ]; then
        while read -r line; do
            _check_command "$line" "$autostart" seen
        done < <(sed -n 's/^[[:space:]]*exec-once[[:space:]]*=[[:space:]]*//p' "$DOCTOR_ROOT/$autostart")
    fi

    if [ "$DOCTOR_WARNINGS" -eq "$before" ]; then
        ok "every binary referenced by keybinds and autostart is installed"
    fi
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `./scripts/doctor/test/run-tests.sh`
Expected: PASS — `4 files, N assertions, 0 failures`

- [ ] **Step 5: Lint**

Run: `shellcheck -S warning scripts/doctor/checks/binaries.sh`
Expected: no output, exit 0

- [ ] **Step 6: Commit**

```bash
git add scripts/doctor/checks/binaries.sh scripts/doctor/test/test-binaries.sh
git commit -m "feat(doctor): keybind and autostart binary checks"
```

---

### Task 5: Service, DBus, and package checks

**Goal:** Verify autostart daemons are running, report which process owns the notification bus, flag competing notification daemons, and detect `install.sh` package drift.

**Files:**
- Create: `scripts/doctor/checks/services.sh`
- Create: `scripts/doctor/test/test-services.sh`

**Acceptance Criteria:**
- [ ] Daemon list is derived from bare-binary `exec-once` entries in `autostart.conf`
- [ ] Entries that are paths (one-shot scripts) are excluded from the process check
- [ ] A daemon that is installed but not running produces WARN
- [ ] `PACKAGES` and `AUR_PACKAGES` are parsed out of `install.sh`; a listed-but-absent package produces INFO
- [ ] The owner of `org.freedesktop.Notifications` is reported as INFO
- [ ] An installed package providing `notification-daemon` that has a tracked config dir but does not own the bus produces INFO
- [ ] All package/DBus probes degrade gracefully when `pacman` or `busctl` is unavailable

**Verify:** `./scripts/doctor/test/run-tests.sh` → `0 failures`, exit 0

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `scripts/doctor/test/test-services.sh`:

```bash
# Tests for scripts/doctor/checks/services.sh

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/services.sh"

fixture="$(make_fixture)"
FIXTURES+=("$fixture")

mkdir -p "$fixture/hypr/config/setup"

cat > "$fixture/hypr/config/setup/autostart.conf" <<'EOF'
exec-once = not-a-running-daemon-pp
exec-once = $HOME/.config/scripts/hyprland/startup.sh
exec-once = $polkitAgent
EOF

cat > "$fixture/install.sh" <<'EOF'
PACKAGES=(
    "bash"                 # definitely installed
    "totally-absent-pkg-1"
)
AUR_PACKAGES=(
    "totally-absent-pkg-2"
)
EOF

git -C "$fixture" add -A
git -C "$fixture" commit -qm "fixture"

DOCTOR_ROOT="$fixture"

# --- autostart daemon extraction ---
daemons="$(_autostart_daemons)"
assert_contains "$daemons" "not-a-running-daemon-pp" "bare binary is treated as a daemon"
assert_not_contains "$daemons" "startup.sh" "path entries are excluded from the daemon list"
assert_not_contains "$daemons" "polkitAgent" "variable entries are excluded from the daemon list"

# --- package list parsing ---
pkgs="$(_install_packages)"
assert_contains "$pkgs" "bash" "PACKAGES entries are parsed"
assert_contains "$pkgs" "totally-absent-pkg-2" "AUR_PACKAGES entries are parsed"
assert_not_contains "$pkgs" "#" "comments are stripped from the package list"
assert_not_contains "$pkgs" '"' "quotes are stripped from the package list"

# --- findings ---
doctor_reset
out="$(check_services 2>&1)"

assert_contains "$out" "not-a-running-daemon-pp" "non-running autostart daemon is reported"
if command -v pacman >/dev/null 2>&1; then
    assert_contains "$out" "totally-absent-pkg-1" "package drift is reported"
fi
if command -v busctl >/dev/null 2>&1; then
    assert_contains "$out" "Notifications" "notification bus owner is reported"
fi

DOCTOR_ROOT="${HOME}/.config"
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `./scripts/doctor/test/run-tests.sh`
Expected: FAIL — `checks/services.sh: No such file or directory`

- [ ] **Step 3: Write the check**

Create `scripts/doctor/checks/services.sh`:

```bash
#!/bin/bash
#
# Runtime state: autostart daemons, single-owner DBus roles, package drift.
#
# One-shot exec-once entries (restore-wallpaper.sh, startup.sh, ...) are
# expected to exit, so only bare-binary entries are process-checked.
#

# Single-owner DBus roles worth auditing. Extend this table to cover more
# roles (polkit agent, idle daemon) as the need arises.
DOCTOR_DBUS_ROLES="org.freedesktop.Notifications:notification-daemon"

# _autostart_daemons -> newline-separated bare binaries from autostart.conf
_autostart_daemons() {
    local conf="$DOCTOR_ROOT/hypr/config/setup/autostart.conf" line first
    [ -f "$conf" ] || return 0

    while read -r line; do
        line="${line%&}"
        read -r first _ <<< "$line"
        [ -n "$first" ] || continue
        case "$first" in
            /*|~/*|'$'*) continue ;;   # paths and variables are not daemons
        esac
        printf '%s\n' "$first"
    done < <(sed -n 's/^[[:space:]]*exec-once[[:space:]]*=[[:space:]]*//p' "$conf") | sort -u
}

# _install_packages -> newline-separated package names from install.sh
_install_packages() {
    local installer="$DOCTOR_ROOT/install.sh"
    [ -f "$installer" ] || return 0

    awk '
        /^(PACKAGES|AUR_PACKAGES)=\(/ { inside = 1; next }
        inside && /^\)/               { inside = 0; next }
        inside                        { print }
    ' "$installer" \
        | sed 's/#.*//' \
        | tr -d '"' \
        | tr ' ' '\n' \
        | sed '/^[[:space:]]*$/d' \
        | sort -u
}

_check_daemons() {
    local daemon before="$DOCTOR_WARNINGS"

    while read -r daemon; do
        [ -n "$daemon" ] || continue
        command -v "$daemon" >/dev/null 2>&1 || continue   # absence is the binary check's finding
        if ! pgrep -x "$daemon" >/dev/null 2>&1 && ! pgrep -f "$daemon" >/dev/null 2>&1; then
            warn "$daemon is autostarted but is not running" \
                 "start it manually to see why: $daemon"
        fi
    done < <(_autostart_daemons)

    if [ "$DOCTOR_WARNINGS" -eq "$before" ]; then
        ok "all autostart daemons are running"
    fi
}

_check_dbus_roles() {
    command -v busctl >/dev/null 2>&1 || return 0
    command -v pacman >/dev/null 2>&1 || return 0

    local role bus provide owner dir pkg
    for role in $DOCTOR_DBUS_ROLES; do
        bus="${role%%:*}"
        provide="${role##*:}"

        owner="$(busctl --user list 2>/dev/null | awk -v n="$bus" '$1 == n { print $3; exit }')"
        if [ -z "$owner" ]; then
            warn "no process owns $bus" \
                 "check that the daemon in autostart.conf actually started"
            continue
        fi
        note "$bus is served by $owner"

        # Any other installed provider with a tracked config dir is dead weight.
        while read -r dir; do
            pkg="$(basename "$dir")"
            [ "$pkg" = "$owner" ] && continue
            pacman -Qi "$pkg" >/dev/null 2>&1 || continue
            if pacman -Qi "$pkg" 2>/dev/null | grep -q "$provide"; then
                note "$pkg/ is tracked and installed but $owner owns $bus — $pkg is inert" \
                     "remove $pkg/ and its references, or switch back to it deliberately"
            fi
        done < <(find "$DOCTOR_ROOT" -maxdepth 1 -mindepth 1 -type d -not -name '.*' 2>/dev/null)
    done
}

_check_packages() {
    command -v pacman >/dev/null 2>&1 || return 0

    local pkg missing=0
    while read -r pkg; do
        [ -n "$pkg" ] || continue
        if ! pacman -Qq "$pkg" >/dev/null 2>&1 \
            && ! pacman -Qq "${pkg%-bin}" >/dev/null 2>&1 \
            && ! pacman -Qq "${pkg}-git" >/dev/null 2>&1; then
            note "install.sh lists '$pkg' but it is not installed" \
                 "pacman -S $pkg   (or drop it from install.sh)"
            missing=$((missing + 1))
        fi
    done < <(_install_packages)

    if [ "$missing" -eq 0 ]; then
        ok "every package listed in install.sh is installed"
    fi
}

check_services() {
    group "Services & packages"
    _check_daemons
    _check_dbus_roles
    _check_packages
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `./scripts/doctor/test/run-tests.sh`
Expected: PASS — `5 files, N assertions, 0 failures`

- [ ] **Step 5: Lint**

Run: `shellcheck -S warning scripts/doctor/checks/services.sh`
Expected: no output, exit 0

- [ ] **Step 6: Commit**

```bash
git add scripts/doctor/checks/services.sh scripts/doctor/test/test-services.sh
git commit -m "feat(doctor): daemon, DBus role, and package drift checks"
```

---

### Task 6: `doctor.sh` entry point

**Goal:** Wire the library and four check modules into a runnable top-level command with a correct exit code.

**Files:**
- Create: `doctor.sh`
- Create: `scripts/doctor/test/test-entrypoint.sh`

**Acceptance Criteria:**
- [ ] `./doctor.sh` runs all four checks in order and prints a tally
- [ ] Exit code is 1 when any ERROR was reported, 0 otherwise
- [ ] `./doctor.sh --help` prints usage and exits 0 without running checks
- [ ] The script does **not** use `set -e` (a failing check must not abort the report)
- [ ] It fails clearly if `$DOCTOR_ROOT` is not a git repository
- [ ] `shellcheck -S warning` passes

**Verify:** `./doctor.sh; echo "exit=$?"` → full report followed by `exit=0` on the current system

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `scripts/doctor/test/test-entrypoint.sh`:

```bash
# Tests for doctor.sh

DOCTOR_BIN="$REPO_DIR/doctor.sh"

out="$(bash "$DOCTOR_BIN" --help 2>&1)"
assert_contains "$out" "Usage" "--help prints usage"
assert_not_contains "$out" "Symlinks" "--help does not run checks"

# A fixture with a deliberate ERROR must exit 1.
fixture="$(make_fixture)"
FIXTURES+=("$fixture")
mkdir -p "$fixture/hypr"
ln -s "./nowhere-at-all" "$fixture/broken-link"
printf 'source = config/missing.conf\n' > "$fixture/hypr/hyprland.conf"
git -C "$fixture" add -A
git -C "$fixture" commit -qm "fixture"

out="$(DOCTOR_ROOT="$fixture" DOCTOR_CACHE="$fixture/no-cache" bash "$DOCTOR_BIN" 2>&1)" && rc=0 || rc=$?
assert_eq "$rc" "1" "exit code is 1 when errors are present"
assert_contains "$out" "ERROR" "errors appear in the report"
assert_contains "$out" "error" "tally line is printed"

# Not a git repo -> clear failure, not a stack of confusing findings.
notrepo="$(mktemp -d)"
FIXTURES+=("$notrepo")
out="$(DOCTOR_ROOT="$notrepo" bash "$DOCTOR_BIN" 2>&1)" && rc=0 || rc=$?
assert_contains "$out" "not a git repository" "non-repo root is reported clearly"
assert_eq "$rc" "1" "non-repo root exits non-zero"
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `./scripts/doctor/test/run-tests.sh`
Expected: FAIL — `doctor.sh: No such file or directory`

- [ ] **Step 3: Write doctor.sh**

Create `doctor.sh`:

```bash
#!/bin/bash
#
# Dotfiles Doctor
# Validates the live Hyprland setup against the tracked configuration.
#
# Usage: ./doctor.sh [--help]
#
# Reports findings at three severities and never modifies anything:
#   ERROR  the session is broken or will break on next login
#   WARN   degraded — a keybind does nothing, a daemon did not start
#   INFO   tidiness — orphaned config, package drift
#
# Exits 1 if any ERROR was found, otherwise 0.
#
# Note: deliberately NOT `set -e`. A check returning non-zero must not abort
# the run — the whole point is to collect every finding and print a summary.
set -uo pipefail

DOCTOR_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR_ROOT="${DOCTOR_ROOT:-$DOCTOR_SELF_DIR}"
export DOCTOR_ROOT

# Lines 3-13 are the user-facing header; line 15 onward is an implementation
# note that does not belong in --help output.
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

# shellcheck source=scripts/doctor/lib.sh
source "$DOCTOR_SELF_DIR/scripts/doctor/lib.sh"

if ! git -C "$DOCTOR_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "doctor: $DOCTOR_ROOT is not a git repository — every check derives its"
    echo "        targets from tracked files, so there is nothing to check."
    exit 1
fi

for module in symlinks references binaries services; do
    # shellcheck source=/dev/null
    source "$DOCTOR_SELF_DIR/scripts/doctor/checks/$module.sh"
done

echo "Checking $DOCTOR_ROOT"

check_symlinks
check_references
check_binaries
check_services

summary
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `chmod +x doctor.sh && ./scripts/doctor/test/run-tests.sh`
Expected: PASS — `6 files, N assertions, 0 failures`

- [ ] **Step 5: Run it against the live system**

Run: `./doctor.sh; echo "exit=$?"`
Expected: a four-section report ending in a tally and `exit=0`. Confirm no ERROR appears — the spec verified on 2026-07-25 that no ERROR-class condition exists on this machine. If an ERROR does appear, it is a real finding: fix the system, not the check.

- [ ] **Step 6: Lint**

Run: `shellcheck -S warning doctor.sh`
Expected: no output, exit 0

- [ ] **Step 7: Commit**

```bash
git add doctor.sh scripts/doctor/test/test-entrypoint.sh
git commit -m "feat(doctor): top-level entry point"
```

---

### Task 7: Pre-commit hook and install.sh wiring

**Goal:** A tracked pre-commit hook that shellchecks staged scripts and bundle-checks staged AGS sources, activated via `core.hooksPath`.

**Files:**
- Create: `scripts/hooks/pre-commit`
- Modify: `install.sh` (add hook activation before the "Final wiring" section, around line 290)

**Acceptance Criteria:**
- [ ] Hook runs `shellcheck -S warning` on staged `*.sh` files only
- [ ] Hook runs `ags bundle` only when staged files touch `ags/`
- [ ] Hook exits 0 and prints nothing intrusive when nothing relevant is staged
- [ ] Missing `shellcheck` or `ags` produces a warning and does not block the commit
- [ ] `install.sh` sets `core.hooksPath` to `scripts/hooks`
- [ ] `install.sh --dry-run` still completes without error
- [ ] The bundle output goes to a temp file and is deleted

**Verify:** `git config core.hooksPath` → `scripts/hooks`, and staging a script with a shellcheck warning blocks the commit

**Steps:**

- [ ] **Step 1: Write the hook**

Create `scripts/hooks/pre-commit`:

```bash
#!/bin/bash
#
# Pre-commit gate. Activated by install.sh via:
#   git config core.hooksPath scripts/hooks
#
# Tracked in the repo (rather than copied into .git/hooks) so it updates with
# a pull and cannot silently diverge from the configs it guards.
#
set -uo pipefail

REPO="$(git rev-parse --show-toplevel)"
FAILED=0

staged() {
    git diff --cached --name-only --diff-filter=ACM
}

# --- shell scripts ---
mapfile -t STAGED_SH < <(staged | grep -E '\.sh$' || true)
if [ "${#STAGED_SH[@]}" -gt 0 ]; then
    if command -v shellcheck >/dev/null 2>&1; then
        echo "pre-commit: shellcheck (${#STAGED_SH[@]} file(s))"
        for f in "${STAGED_SH[@]}"; do
            [ -f "$REPO/$f" ] || continue
            if ! shellcheck -S warning "$REPO/$f"; then
                FAILED=1
            fi
        done
    else
        echo "pre-commit: shellcheck not installed, skipping shell lint"
    fi
fi

# --- AGS settings panel ---
# `ags bundle` is the only compile gate available: there is no tsc, no
# package.json and no node_modules in ags/. esbuild catches syntax errors but
# NOT type errors, so tsconfig's `strict: true` is not enforced here.
if staged | grep -q '^ags/'; then
    if command -v ags >/dev/null 2>&1; then
        echo "pre-commit: ags bundle"
        BUNDLE_OUT="$(mktemp)"
        if ! (cd "$REPO/ags" && ags bundle app.ts "$BUNDLE_OUT" >/dev/null); then
            echo "pre-commit: ags bundle failed"
            FAILED=1
        fi
        rm -f "$BUNDLE_OUT"
    else
        echo "pre-commit: ags not installed, skipping panel build check"
    fi
fi

if [ "$FAILED" -ne 0 ]; then
    echo
    echo "pre-commit: checks failed. Fix the issues above, or bypass with --no-verify."
    exit 1
fi
exit 0
```

- [ ] **Step 2: Make it executable and activate it**

```bash
chmod +x scripts/hooks/pre-commit
git config core.hooksPath scripts/hooks
```

- [ ] **Step 3: Verify the hook blocks a bad commit**

```bash
cat > /tmp/claude-1000/bad-test.sh <<'EOF'
#!/bin/bash
foo=$1
echo $foo
EOF
cp /tmp/claude-1000/bad-test.sh scripts/doctor/bad-test.sh
git add scripts/doctor/bad-test.sh
git commit -m "should be blocked" && echo "UNEXPECTED PASS" || echo "correctly blocked"
```

Expected: `SC2086` reported, commit blocked, `correctly blocked` printed.

- [ ] **Step 4: Clean up the probe**

```bash
git reset scripts/doctor/bad-test.sh
rm -f scripts/doctor/bad-test.sh
```

- [ ] **Step 5: Verify a clean commit still succeeds**

Staging any already-clean tracked script and committing must succeed — confirmed by the commit in Step 7 itself, which stages `.sh` files and must pass the hook.

- [ ] **Step 6: Wire it into install.sh**

In `install.sh`, immediately before the `# Final wiring` banner comment (currently around line 290), insert:

```bash
# ------------------------------------------------------------------
# Git hooks
# ------------------------------------------------------------------
# Tracked hooks live in scripts/hooks and are activated by pointing git at
# them, so they update with a pull instead of rotting in .git/hooks.
if [ -d "$CONFIG_DIR/.git" ]; then
    info "Activating tracked git hooks..."
    execute git -C "$CONFIG_DIR" config core.hooksPath scripts/hooks
    success "Pre-commit gate active (shellcheck + ags bundle)"
fi
```

Also add `"shellcheck"` to the `PACKAGES` array under the `# Script dependencies` comment (line 109), since the hook now depends on it.

- [ ] **Step 7: Verify install.sh still works and commit**

```bash
./install.sh --dry-run > /dev/null && echo "dry-run ok"
git add scripts/hooks/pre-commit install.sh
git commit -m "feat(hooks): pre-commit shellcheck and ags bundle gate"
```

Expected: `dry-run ok`, then the hook runs on its own commit and passes.

---

### Task 8: Documentation and live acceptance

**Goal:** Document `doctor.sh` alongside `install.sh`, and confirm the tool independently reproduces the three findings established by hand while designing.

**Files:**
- Modify: `README.md` (structure section and a new Maintenance section)
- Modify: `CLAUDE.md` (Key Commands section)
- Modify: `CHANGELOG.md` (new dated entry at the top)

**Acceptance Criteria:**
- [ ] `README.md` documents `./doctor.sh` and the three severity levels
- [ ] `CLAUDE.md` Key Commands includes `./doctor.sh` and the test command
- [ ] `CHANGELOG.md` has a `[2026-07-25]` entry describing the doctor, the hook, and the two findings
- [ ] A live run reports: flameshot package drift, mako inert, two absolute symlinks
- [ ] A live run exits 0 (no ERROR-class conditions on this machine)
- [ ] Full test suite passes

**Verify:** `./doctor.sh | grep -E 'flameshot|mako|colors.rasi|colors.css'` → all four lines present

**Steps:**

- [ ] **Step 1: Run the live acceptance check**

```bash
./doctor.sh; echo "exit=$?"
```

Expected — these four findings must appear unprompted:

| Finding | Severity |
|---|---|
| `install.sh lists 'flameshot' but it is not installed` | INFO |
| `mako/ is tracked and installed but swaync owns org.freedesktop.Notifications` | INFO |
| `rofi/options/colors.rasi → /home/pwnjack/... (absolute path hardcodes a username)` | WARN |
| `waybar/colors.css → /home/pwnjack/... (absolute path hardcodes a username)` | WARN |

and `exit=0`.

If any is missing, the corresponding check has a bug — fix the check before proceeding. These four are the reason the tool exists; a doctor that misses them is not done.

- [ ] **Step 2: Run the full test suite**

```bash
./scripts/doctor/test/run-tests.sh
```

Expected: `6 files, N assertions, 0 failures`, exit 0

- [ ] **Step 3: Update README.md**

Add to the structure tree, directly under the `~/.config/` root entry:

```
├── doctor.sh                   # Health check (see Maintenance)
```

Add a new `## Maintenance` section after the Structure section:

````markdown
## Maintenance

```bash
./doctor.sh          # validate the live system
./doctor.sh --help   # usage
```

`doctor.sh` reports and never modifies. Every check derives its targets from
tracked files — git's symlink modes, `source =` lines in `hyprland.conf`,
`exec,` targets in `keybinds.conf`, the package arrays in `install.sh` — so
adding a keybind or an autostart entry extends coverage automatically.

| Severity | Meaning | Effect on exit code |
|---|---|---|
| `ERROR` | The session is broken or will break on next login | exits 1 |
| `WARN` | Degraded — a keybind does nothing, a daemon did not start | exits 0 |
| `INFO` | Tidiness — orphaned config, package drift | exits 0 |

A pre-commit hook (`scripts/hooks/pre-commit`, activated by `install.sh`)
runs `shellcheck` on staged shell scripts and `ags bundle` on staged panel
sources. Bypass with `git commit --no-verify`.

Run the doctor's own tests with `./scripts/doctor/test/run-tests.sh`.
````

- [ ] **Step 4: Update CLAUDE.md**

In the `## Key Commands` block, after the install commands, add:

```bash
# Validate the live system (report-only; exits 1 only on ERROR findings)
./doctor.sh

# Run the doctor's test suite
./scripts/doctor/test/run-tests.sh
```

And append to the `## Conventions` section:

```markdown
- `doctor.sh` and its checks derive every target from tracked files. When adding
  a check, never introduce a hand-written list of paths, binaries, or packages —
  parse the config that already declares them.
- Check modules must never run their loops in a pipeline (`cmd | while read`);
  severity counters are shell variables and would be lost in the subshell.
  Use `while read ...; do ... done < <(cmd)`.
```

- [ ] **Step 5: Update CHANGELOG.md**

Insert directly below the `# Changelog` header and its intro line:

```markdown
## [2026-07-25] - Doctor & Lint Gate

### Added
- **`doctor.sh`**: report-only health check for the live system. Validates
  tracked symlinks, Hyprland `source` chains, literal `~/.config` references,
  keybind and autostart binaries, running daemons, DBus role ownership, and
  `install.sh` package drift. Every target is derived from tracked files, so
  there is no list to keep in sync. Exits 1 only on ERROR-class findings.
- **Pre-commit hook** (`scripts/hooks/pre-commit`, activated via
  `core.hooksPath`): `shellcheck` on staged scripts, `ags bundle` on staged
  panel sources.
- **Doctor test suite** (`scripts/doctor/test/`): dependency-free harness
  running each check against throwaway git fixtures.

### Found
- `flameshot` is listed in `install.sh` but is not installed; `flameshot/` is
  tracked while screenshots actually go through `hyprshot` and
  `rofi/screenshot.sh`.
- **mako is inert.** swaync owns `org.freedesktop.Notifications`, the DBus name
  a notification daemon must hold to receive anything. This corrects the
  "mako stays (still in use alongside SwayNC)" decision recorded in the
  2026-07-19 polish spec, which was never tested.
- `rofi/options/colors.rasi` and `waybar/colors.css` are tracked symlinks with
  absolute `/home/pwnjack` targets. The 2026-07-15 "portable symlinks" fix
  converted two of the four known cases and missed these.

Acting on these findings is deliberately left as separate work.
```

- [ ] **Step 6: Commit**

```bash
git add README.md CLAUDE.md CHANGELOG.md
git commit -m "docs: document doctor.sh, the pre-commit gate, and its first findings"
```

---

## Notes for the implementer

**Run the test suite after every task.** Each check module is sourced into the same shell as the others; a stray top-level statement in one module breaks all of them, and the suite catches that immediately.

**When a check finds something on the live system, that is data, not a bug.** The four findings in Task 8 are expected. Anything *else* it finds is worth reporting back rather than silently fixing — a doctor that surprises you on day one is doing its job.

**Do not act on the findings in this plan.** Deleting `flameshot/`, removing `mako/`, or converting the two absolute symlinks is separate work, deliberately out of scope. The tool ships first; the cleanup is a decision made with its output in hand.
