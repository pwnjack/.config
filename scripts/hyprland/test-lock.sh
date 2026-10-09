#!/bin/bash
#
# Tests for scripts/hyprland/lock.sh against the real record.sh and the
# capture fakes: a running recording is saved before hyprlock starts, and a
# running hyprlock is never started twice.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TEST_DIR/../.." && pwd)"
RECORD="$ROOT/scripts/capture/record.sh"
TMP="$(mktemp -d)"

# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"

export FAKE_LOG="$TMP/log" CAPTURE_OPTIONS="$TMP/options"
export CAPTURE_STATE_DIR="$TMP/state" CAPTURE_VIDEOS="$TMP/videos"
# lock.sh finds record.sh under $XDG_CONFIG_HOME, which is this checkout.
export XDG_CONFIG_HOME="$ROOT"
export PATH="$ROOT/scripts/capture/fakes:$PATH"
mkdir -p "$FAKE_LOG" "$CAPTURE_OPTIONS"
trap 'bash "$RECORD" stop >/dev/null 2>&1; rm -rf "$TMP"' EXIT

bash "$RECORD" start region 100x100+0+0
bash "$RECORD" status >/dev/null && pass "fixture: a recording is running" || fail "fixture: a recording is running"

bash "$TEST_DIR/lock.sh"
assert_eq "$(cat "$FAKE_LOG/hyprlock")" "saved=yes args=" "hyprlock starts once, after the recording was saved"
bash "$RECORD" status >/dev/null; rc=$?
assert_eq "$rc" 1 "no recording after locking"

bash "$TEST_DIR/lock.sh" --grace 30
assert_eq "$(wc -l < "$FAKE_LOG/hyprlock")" 1 "a running hyprlock is not started again"

rm -f "$FAKE_LOG/hyprlock" "$FAKE_LOG/hyprlock.running"
bash "$TEST_DIR/lock.sh" --grace 30
assert_eq "$(cat "$FAKE_LOG/hyprlock")" "saved=yes args=--grace 30" "arguments reach hyprlock"

test_summary lock
