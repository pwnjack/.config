# Tests for scripts/doctor/lib.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"

# --- severity counters ---
doctor_reset
out="$(err "broken thing" "run the fix" 2>&1)"
assert_contains "$out" "ERROR" "err prints ERROR tag"
assert_contains "$out" "broken thing" "err prints the message"
assert_contains "$out" "fix: run the fix" "err prints the fix hint"
# The call above ran in a command substitution, so its increment was lost with
# the subshell. Call err again in this shell to observe the counter.
err "broken thing" "run the fix" >/dev/null 2>&1
assert_eq "$DOCTOR_ERRORS" "1" "err increments error counter"

doctor_reset
out="$(warn "degraded thing" 2>&1)"
assert_contains "$out" "WARN" "warn prints WARN tag"
assert_contains "$out" "degraded thing" "warn prints the message"
assert_not_contains "$out" "fix:" "warn omits fix line when no hint given"
# Same subshell caveat as the err case above.
warn "degraded thing" >/dev/null 2>&1
assert_eq "$DOCTOR_WARNINGS" "1" "warn increments warning counter"

doctor_reset
note "tidy thing" >/dev/null 2>&1
note "another" >/dev/null 2>&1
assert_eq "$DOCTOR_NOTICES" "2" "note counter accumulates"

doctor_reset
ok "fine" >/dev/null 2>&1
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS$DOCTOR_NOTICES" "000" "ok does not touch counters"

doctor_reset
out="$(group "Symlinks" 2>&1)"
assert_contains "$out" "Symlinks" "group prints its heading"

# --- messages are printed literally, never escape-interpreted ---
# Every message this tool emits is a path, a regex or a runnable command, so
# echo -e would silently rewrite \n and \t and corrupt copy-pasteable hints.
doctor_reset
out="$(err 'path C:\new\test' 'sed -i "s/\tfoo/bar/" file' 2>&1)"
assert_contains "$out" 'path C:\new\test' "err keeps backslashes in the message"
assert_contains "$out" 'fix: sed -i "s/\tfoo/bar/" file' "err keeps backslashes in the fix hint"

doctor_reset
out="$(warn 'stale ref ~/Dots\b' 2>&1)"
assert_contains "$out" 'stale ref ~/Dots\b' "warn keeps backslashes in the message"

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

# --- summary reports all three counts, with correct pluralisation ---
doctor_reset
out="$(summary 2>&1)"
assert_contains "$out" "0 errors, 0 warnings, 0 notices" "summary pluralises zero counts"

doctor_reset
err "e" >/dev/null 2>&1
warn "w" >/dev/null 2>&1
note "n" >/dev/null 2>&1
out="$(summary 2>&1)"
assert_contains "$out" "1 error, 1 warning, 1 notice" "summary uses singular at one"

doctor_reset
err "e1" >/dev/null 2>&1; err "e2" >/dev/null 2>&1
warn "w1" >/dev/null 2>&1; warn "w2" >/dev/null 2>&1
note "n1" >/dev/null 2>&1; note "n2" >/dev/null 2>&1
out="$(summary 2>&1)"
assert_contains "$out" "2 errors, 2 warnings, 2 notices" "summary pluralises counts above one"

# --- DOCTOR_ROOT override ---
# The harness exports a safe non-existent DOCTOR_ROOT, so the built-in default
# can only be observed in a shell where the variable is unset.
assert_eq "$(env -u DOCTOR_ROOT bash -c 'source "$DOCTOR_DIR/lib.sh"; printf %s "$DOCTOR_ROOT"')" \
    "$HOME/.config" "DOCTOR_ROOT defaults to ~/.config"
assert_eq "$(DOCTOR_ROOT=/tmp/fake bash -c 'source "$DOCTOR_DIR/lib.sh"; printf %s "$DOCTOR_ROOT"')" \
    "/tmp/fake" "DOCTOR_ROOT honours the environment"
