#!/bin/bash
#
# Tests for scripts/capture/record.sh, run as a subprocess the way the strip,
# the keybind and Waybar run it. Everything it drives is a fake from
# scripts/capture/fakes/ on PATH: nothing records, no toast appears and the
# real Waybar is never signalled.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECORD="$TEST_DIR/record.sh"
TMP="$(mktemp -d)"

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

export FAKE_LOG="$TMP/log" CAPTURE_OPTIONS="$TMP/options"
export CAPTURE_STATE_DIR="$TMP/state" CAPTURE_VIDEOS="$TMP/videos"
export PATH="$TEST_DIR/fakes:$PATH"
BASE="-c mp4 -k h264 -ac aac -f 60 -q very_high -cursor yes"

rec() { bash "$RECORD" "$@"; }
opt() { printf '%s\n' "$2" > "$CAPTURE_OPTIONS/$1"; }
last_argv() { tail -n1 "$FAKE_LOG/gsr.argv" 2>/dev/null; }
# wait_grep <file> <text> -- up to 3 s for an asynchronous write.
wait_grep() {
    local i
    for ((i = 0; i < 30; i++)); do
        grep -qF -- "$2" "$1" 2>/dev/null && return 0
        sleep 0.1
    done
    return 1
}
# reset -- stop anything left running, then empty every fixture directory.
reset() {
    rec stop >/dev/null 2>&1
    unset FAKE_GSR FAKE_GSR_FINISH FAKE_SLURP CAPTURE_RECORDER
    rm -rf "$FAKE_LOG" "$CAPTURE_OPTIONS" "$CAPTURE_STATE_DIR" "$CAPTURE_VIDEOS"
    mkdir -p "$FAKE_LOG" "$CAPTURE_OPTIONS"
}
trap 'reset; rm -rf "$TMP"' EXIT
reset

# --- argument vectors: screen x audio ----------------------------------------
check_audio() { # <audio> <mic> <expected -a part, or empty> <label>
    reset
    opt capture-audio "$1"
    opt capture-mic "$2"
    rec start screen
    assert_eq "$(last_argv | sed 's/ -o .*//')" "-w DP-1 $BASE${3:+ $3} -v no" "$4"
    rec stop >/dev/null
}
check_audio false false "" "screen, no audio: focused monitor and the fixed encoder flags"
check_audio true false "-a default_output" "desktop audio only"
check_audio false true "-a default_input" "mic only"
check_audio true true "-a default_output|default_input" "desktop audio and mic merged into one track"

reset
rec start screen
if [[ $(last_argv) =~ \ -o\ $CAPTURE_VIDEOS/Recording_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.mp4$ ]]; then
    pass "output is Recording_YYYY-MM-DD_HH-MM-SS.mp4 under the videos directory"
else
    fail "output name" "argv: $(last_argv)"
fi

# --- status while recording ---------------------------------------------------
status_out=$(rec status); status_rc=$?
assert_eq "$status_rc" 0 "status exits 0 while recording"
assert_contains "$status_out" "recording " "status names the phase"
assert_contains "$(rec status --json)" '"class":"recording"' "status --json carries the recording class"
assert_contains "$(cat "$CAPTURE_STATE_DIR/recording.json")" '"phase":"recording"' "state file written"
assert_contains "$(cat "$FAKE_LOG/pkill")" "-RTMIN+11 waybar" "Waybar signalled on start"

# --- start while recording stops it ---------------------------------------------
output=$(rec status | cut -d' ' -f3-)
rec start screen
[ -s "$output" ] && pass "a second start stops and saves" || fail "a second start stops and saves" "missing: $output"
[ ! -e "$CAPTURE_STATE_DIR/recording.json" ] && pass "state cleared after stop" || fail "state cleared after stop"
wait_grep "$FAKE_LOG/notify" "Recording saved" && pass "saved toast" || fail "saved toast" "$(cat "$FAKE_LOG/notify" 2>/dev/null)"
assert_contains "$(cat "$FAKE_LOG/notify")" "video-x-generic" "saved toast uses a non-symbolic icon"

# --- region and window ------------------------------------------------------------
reset
export FAKE_SLURP=800x600+10+20
rec start region
assert_eq "$(last_argv | sed 's/ -o .*//')" "-w region -region 800x600+10+20 $BASE -v no" "region from slurp"
assert_contains "$(cat "$FAKE_LOG/slurp.argv")" "-f %wx%h+%x+%y" "slurp prints the recorder's geometry format"
rec stop >/dev/null

reset
rec start region 300x200+5+6
assert_eq "$(last_argv | sed 's/ -o .*//')" "-w region -region 300x200+5+6 $BASE -v no" "a given region skips slurp"
[ ! -e "$FAKE_LOG/slurp.argv" ] && pass "no slurp for a given region" || fail "no slurp for a given region"
rec stop >/dev/null

reset
export FAKE_SLURP=640x480+900+40
rec start window
assert_eq "$(cat "$FAKE_LOG/slurp.stdin")" $'10,20 800x600\n900,40 640x480' "window boxes: visible, mapped, unhidden clients only"
assert_contains "$(cat "$FAKE_LOG/slurp.argv")" "-r" "window selection is restricted to the boxes"
assert_eq "$(last_argv | sed 's/ -o .*//')" "-w region -region 640x480+900+40 $BASE -v no" "window recorded as its rectangle"
rec stop >/dev/null

# --- failures ------------------------------------------------------------------------
reset
export FAKE_GSR=die
rec start screen; rc=$?
assert_eq "$rc" 1 "early recorder death exits 1"
[ ! -e "$CAPTURE_STATE_DIR/recording.json" ] && pass "early death clears state" || fail "early death clears state"
assert_contains "$(cat "$FAKE_LOG/notify")" "Recording failed" "early death toast"
assert_contains "$(cat "$FAKE_LOG/notify")" "failed to open the capture device" "toast quotes the recorder's error"

reset
export FAKE_GSR=empty
rec start screen
rec stop; rc=$?
assert_eq "$rc" 1 "an empty file is a failed stop"
assert_contains "$(cat "$FAKE_LOG/notify")" "Recording not saved" "empty file toast"

reset
export FAKE_GSR_FINISH=1
rec start screen
output=$(rec status | cut -d' ' -f3-)
rec stop >/dev/null
[ -s "$output" ] && pass "stop waits for the recorder to write the file" || fail "stop waits for the file"

reset
rec start screen
pid=$(sed -n 's/.*"pid":\([0-9]*\).*/\1/p' "$CAPTURE_STATE_DIR/recording.json")
kill -KILL "$pid"
wait_grep "$FAKE_LOG/notify" "Recording stopped" && pass "a recorder dying mid-recording is reported" \
    || fail "a recorder dying mid-recording is reported" "$(cat "$FAKE_LOG/notify" 2>/dev/null)"

reset
export FAKE_SLURP=cancel
rec start region; rc=$?
assert_eq "$rc" 0 "Esc in slurp exits 0"
[ ! -e "$FAKE_LOG/gsr.argv" ] && [ ! -e "$FAKE_LOG/notify" ] && [ ! -e "$CAPTURE_STATE_DIR/recording.json" ] \
    && pass "Esc in slurp: no recorder, no toast, no state" || fail "Esc in slurp leaves nothing behind"

reset
export CAPTURE_RECORDER=absent-recorder-qq
rec start screen; rc=$?
assert_eq "$rc" 1 "a missing recorder exits 1"
assert_contains "$(cat "$FAKE_LOG/notify")" "gpu-screen-recorder" "a missing recorder names the package"

# --- stale state ---------------------------------------------------------------------
reset
mkdir -p "$CAPTURE_STATE_DIR"
bash -c 'exit 0' & dead=$!
wait "$dead"
printf '{"pid":%s,"started":1,"output":"x","phase":"recording"}\n' "$dead" > "$CAPTURE_STATE_DIR/recording.json"
assert_contains "$(rec status --json)" '"phase":"idle"' "a dead pid reads as idle"
[ ! -e "$CAPTURE_STATE_DIR/recording.json" ] && pass "a dead pid's state is removed" || fail "a dead pid's state is removed"

sleep 30 & other=$!
printf '{"pid":%s,"started":1,"output":"x","phase":"recording"}\n' "$other" > "$CAPTURE_STATE_DIR/recording.json"
rec status >/dev/null; rc=$?
assert_eq "$rc" 1 "a recycled pid (not a recorder) reads as idle"
kill "$other"

# --- idle -----------------------------------------------------------------------------
reset
out=$(rec status --json); rc=$?
assert_eq "$rc" 0 "status --json exits 0 when idle"
assert_contains "$out" '"phase":"idle"' "idle JSON"
rec stop; rc=$?
assert_eq "$rc" 0 "stop with nothing running is a no-op"
[ ! -e "$FAKE_LOG/notify" ] && pass "no toast for a no-op stop" || fail "no toast for a no-op stop"

test_summary record
