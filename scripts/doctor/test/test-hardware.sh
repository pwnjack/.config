# Tests for scripts/doctor/checks/hardware.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash
#
# The host probe is exercised for real against a fake DRM tree via
# DOCTOR_DRM_SYSFS, rather than being shadowed by a stub function. That seam
# already exists in this repo — scripts/waybar/battery.sh takes BATTERY_SYSFS
# for the same reason — and testing the real probe also covers the card-prefix
# strip, which a stub would skip entirely.
#
# Checks run ONCE, redirected to a file under $DOCTOR_TEST_TMP, and the output
# is read back. `out="$(check_hardware)"` would run the check in a subshell and
# discard its severity counters.

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/hardware.sh"

# Assigned throughout this file but read only by the check sourced above.
export DOCTOR_ROOT DOCTOR_DRM_SYSFS

hw_out_file="$DOCTOR_TEST_TMP/hardware.out"

# hw_sysfs <dir> <name:status>... — build a fake /sys/class/drm.
hw_sysfs() {
    local dir="$1"; shift
    local entry
    mkdir -p "$dir"
    for entry in "$@"; do
        mkdir -p "$dir/${entry%%:*}"
        printf '%s\n' "${entry##*:}" > "$dir/${entry%%:*}/status"
    done
}

# hw_track <root> <path> <content> — write a file and stage it, so git ls-files
# sees it. An unstaged file is invisible to the check by design.
hw_track() {
    mkdir -p "$(dirname "$1/$2")"
    printf '%s\n' "$3" > "$1/$2"
    git -C "$1" add -- "$2"
}

# --- the probe itself ------------------------------------------------------
hw_drm="$DOCTOR_TEST_TMP/drm-a"
hw_sysfs "$hw_drm" "card1-DP-1:connected" "card1-HDMI-A-1:disconnected" \
                   "card0-eDP-1:connected"
DOCTOR_DRM_SYSFS="$hw_drm"
hw_probe="$(_hw_connected_outputs | sort | tr '\n' ' ')"
assert_eq "$hw_probe" "DP-1 eDP-1 " "probe strips the card prefix and keeps only connected"

# --- a fixture exercising every finding ------------------------------------
hw_fixture="$(make_fixture)"
DOCTOR_ROOT="$hw_fixture"
hw_track "$hw_fixture" "options/mainmonitor" "HDMI-A-1"
hw_track "$hw_fixture" "hypr/good.conf" "monitor=DP-1,highrr,auto,1"
hw_track "$hw_fixture" "hypr/stale.conf" '$monitor = eDP-9'
hw_track "$hw_fixture" "README.md" "mainmonitor  # DP-9"
hw_track "$hw_fixture" "docs/note.txt" "example uses DP-9"
hw_track "$hw_fixture" "scripts/doctor/checks/hardware.sh" "eDP|DP|HDMI-A pattern DP-9"

hw_drm2="$DOCTOR_TEST_TMP/drm-b"
hw_sysfs "$hw_drm2" "card1-DP-1:connected"
DOCTOR_DRM_SYSFS="$hw_drm2"

doctor_reset
check_hardware > "$hw_out_file" 2>&1
hw_out="$(cat "$hw_out_file")"

assert_contains "$hw_out" "options/mainmonitor names HDMI-A-1" "disconnected connector is reported"
assert_contains "$hw_out" "hypr/stale.conf names eDP-9" "eDP-9 is matched whole, not as DP-9"
assert_not_contains "$hw_out" "hypr/good.conf" "a connected connector is not reported"
assert_not_contains "$hw_out" "README.md" "markdown is skipped — docs carry example names"
assert_not_contains "$hw_out" "docs/note.txt" "docs/ is skipped"
assert_not_contains "$hw_out" "scripts/doctor/checks/hardware.sh" "the doctor's own tree is skipped"
assert_eq "$DOCTOR_WARNINGS" "2" "exactly two warnings"
assert_eq "$DOCTOR_ERRORS" "0" "a stale connector is never an error"

# --- a clean tree gets the all-clear, and nothing else ----------------------
hw_clean="$(make_fixture)"
DOCTOR_ROOT="$hw_clean"
hw_track "$hw_clean" "options/mainmonitor" ""
hw_track "$hw_clean" "hypr/monitor.conf" "monitor=,highrr,auto,1"

doctor_reset
check_hardware > "$hw_out_file" 2>&1
hw_out="$(cat "$hw_out_file")"

assert_contains "$hw_out" "no tracked config names a disconnected output" "clean tree prints ok"
assert_eq "$DOCTOR_WARNINGS" "0" "clean tree warns about nothing"

# --- no DRM nodes at all: one INFO, never a wall of warnings ----------------
hw_empty="$DOCTOR_TEST_TMP/drm-empty"
mkdir -p "$hw_empty"
DOCTOR_DRM_SYSFS="$hw_empty"
DOCTOR_ROOT="$hw_fixture"

doctor_reset
check_hardware > "$hw_out_file" 2>&1
hw_out="$(cat "$hw_out_file")"

assert_contains "$hw_out" "no connected display output" "headless run explains itself"
assert_eq "$DOCTOR_WARNINGS" "0" "headless run warns about nothing"
