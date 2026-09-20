#!/bin/bash
# Tests for the Waybar reload and visibility lifecycle scripts.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  ok   $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL $1"; }

mkdir -p "$TMP/bin"
# These single-quoted lines are intentionally written verbatim into the fakes.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'printf "%s\n" "$*" > "$PKILL_LOG"' \
    'exit "$PKILL_STATUS"' > "$TMP/bin/pkill"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'printf "started\n" > "$WAYBAR_LOG"' > "$TMP/bin/waybar"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'case "$*" in' \
    '    *" get-property "*) exit 0 ;;' \
    '    *" list") printf "%s\n" "org.kde.StatusNotifierItem-proton.vpn.app.gtk-123 123 proton" "org.example.Unrelated 456 other" ;;' \
    '    *" call "*) printf "%s\n" "$*" >> "$BUSCTL_LOG" ;;' \
    'esac' > "$TMP/bin/busctl"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$TMP/bin/sleep"
chmod +x "$TMP/bin/pkill" "$TMP/bin/waybar" "$TMP/bin/busctl" "$TMP/bin/sleep"

run_script() {
    : > "$TMP/pkill.log"
    : > "$TMP/busctl.log"
    rm -f "$TMP/waybar.log"
    PKILL_LOG="$TMP/pkill.log" WAYBAR_LOG="$TMP/waybar.log" \
        BUSCTL_LOG="$TMP/busctl.log" \
        PKILL_STATUS="$2" PATH="$TMP/bin:$PATH" bash "$1"
}

assert_running_case() {
    local script="$1" signal="$2" label="$3"
    run_script "$script" 0
    if [ "$(<"$TMP/pkill.log")" = "$signal -x waybar" ] &&
       [ ! -e "$TMP/waybar.log" ] &&
       { [ "$signal" != -USR2 ] || grep -qF \
           'RegisterStatusNotifierItem s org.kde.StatusNotifierItem-proton.vpn.app.gtk-123' \
           "$TMP/busctl.log"; }; then
        pass "$label"
    else
        fail "$label"
    fi
}

assert_absent_case() {
    local script="$1" label="$2" attempt
    run_script "$script" 1
    for ((attempt = 0; attempt < 100; attempt++)); do
        [ ! -e "$TMP/waybar.log" ] || break
        sleep 0.01
    done
    if [ -e "$TMP/waybar.log" ]; then
        pass "$label"
    else
        fail "$label"
    fi
}

echo "waybar lifecycle"

assert_running_case "$TEST_DIR/waybar.sh" -USR2 \
    "reload sends SIGUSR2 and restores existing tray items"
assert_absent_case "$TEST_DIR/waybar.sh" \
    "reload starts Waybar when it is absent"
assert_running_case "$TEST_DIR/waybartoggle.sh" -USR1 \
    "visibility toggle keeps the running process and sends SIGUSR1"
assert_absent_case "$TEST_DIR/waybartoggle.sh" \
    "visibility toggle starts Waybar when it is absent"

echo
echo "$PASSED passed, $FAILED failed"
exit "$((FAILED > 0))"
