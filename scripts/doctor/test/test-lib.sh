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
