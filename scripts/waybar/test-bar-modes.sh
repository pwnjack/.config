#!/bin/bash
#
# Tests for scripts/waybar/bar-modes.sh, run as a subprocess the way the
# settings panel and install.sh run it. BAR_OPTIONS and BAR_INCLUDE are the
# seam; a fake pkill on PATH records the reload.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/bar-modes.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck disable=SC1091 # Shared assertions are checked by their own suite.
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

mkdir -p "$TMP/opt" "$TMP/bin"
printf '#!/bin/bash\necho "$*" >> "%s/pkill.log"\n' "$TMP" > "$TMP/bin/pkill"
# A running bar, and a busctl that registers nothing, so the reload through
# waybar.sh never reaches the real session's tray.
printf '#!/bin/bash\nexit "${PGREP_STATUS:-0}"\n' > "$TMP/bin/pgrep"
printf '#!/bin/bash\nexit 0\n' > "$TMP/bin/busctl"
chmod +x "$TMP/bin/pkill" "$TMP/bin/pgrep" "$TMP/bin/busctl"

# render [--no-reload] — run the script, print the include
render() {
    BAR_OPTIONS="$TMP/opt" BAR_INCLUDE="$TMP/out/bar.jsonc" PATH="$TMP/bin:$PATH" \
        bash "$SCRIPT" "$@"
    cat "$TMP/out/bar.jsonc"
}

# set_mode <module> <value>
set_mode() { printf '%s\n' "$2" > "$TMP/opt/bar-$1"; }

out=$(render --no-reload)
assert_eq "$(jq -c . <<< "$out")" '{}' "no option files render an empty include"

set_mode cpu always; set_mode memory banana; set_mode disk always
out=$(render --no-reload)
assert_eq "$(jq -c . <<< "$out")" '{}' "always and garbage values both mean always"

set_mode cpu high
out=$(render --no-reload)
assert_eq "$(jq -c . <<< "$out")" '{"cpu":{"format-normal":""}}' "high blanks only the normal state"

set_mode cpu always; set_mode disk hidden
out=$(render --no-reload)
assert_eq "$(jq -c . <<< "$out")" '{"disk":{"format-normal":"","format-warning":"","format-critical":""}}' "hidden blanks every state"

set_mode cpu high; set_mode memory hidden; set_mode disk high
out=$(render --no-reload)
assert_eq "$(jq -c 'keys' <<< "$out")" '["cpu","disk","memory"]' "each module is rendered independently"

assert_eq "$(find "$TMP/out" -name 'bar.jsonc.*' | wc -l)" 0 "no temporary file is left behind"
if [ -e "$TMP/pkill.log" ]; then
    fail "--no-reload does not signal Waybar"
else
    pass "--no-reload does not signal Waybar"
fi
render > /dev/null
assert_eq "$(<"$TMP/pkill.log")" "-USR2 -x waybar" "a render signals Waybar once"
rm -f "$TMP/pkill.log"
PGREP_STATUS=1 render > /dev/null
if [ -e "$TMP/pkill.log" ]; then
    fail "a bar that is not running is neither started nor signalled"
else
    pass "a bar that is not running is neither started nor signalled"
fi

config="$TEST_DIR/../../waybar/config.jsonc"
# shellcheck disable=SC2088 # The literal tilde is present in Waybar's config.
assert_contains "$(grep '"include"' "$config")" '~/.local/state/waybar/bar.jsonc' "config.jsonc includes the rendered file"
if sed -n '/^  "\(cpu\|memory\|disk\)": {/,/^  },/p' "$config" | grep -Eq '"format-(normal|warning|critical)"'; then
    fail "config.jsonc must not set the per-state formats bar.jsonc controls"
else
    pass "config.jsonc leaves the per-state formats to the include"
fi

test_summary test-bar-modes
