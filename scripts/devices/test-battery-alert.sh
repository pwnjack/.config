#!/bin/bash
# Tests for scripts/devices/battery-alert.sh: once per critical episode.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# shellcheck disable=SC1091 # Shared assertions are checked by their own suite.
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/calls"\n' "$TMP" > "$TMP/bin/notify-send"; chmod +x "$TMP/bin/notify-send"
alert() { printf '%s' "$1" | DEVICE_ALERT_STATE="$TMP/state" PATH="$TMP/bin:$PATH" bash "$TEST_DIR/battery-alert.sh"; }
calls() { if [ -f "$TMP/calls" ]; then wc -l < "$TMP/calls"; else echo 0; fi; }
pad='[{"id":"gip0.0","name":"Xbox Controller","percent":null,"level":"critical","alert":"critical"}]'
mouse='[{"id":"hidpp_battery_0","name":"G Pro","percent":7,"level":null,"alert":"critical"}]'
echo "battery-alert.sh"
alert "$pad"; assert_eq "$(calls)" 1 "a critical device notifies"
assert_eq "$(cat "$TMP/calls")" "-a Devices -i battery-caution Xbox Controller battery very low Critical" "level is the body"
alert "$pad"; assert_eq "$(calls)" 1 "the same episode does not notify twice"
alert '[]'; alert "$pad"; assert_eq "$(calls)" 2 "leaving and re-entering critical notifies again"
alert "$mouse"; assert_eq "$(tail -n1 "$TMP/calls")" "-a Devices -i battery-caution G Pro battery very low 7%" "percent is the body"
alert '[{"id":"hidpp_battery_0","name":"G Pro","percent":20,"level":null,"alert":"low"}]'
alert "$mouse"; assert_eq "$(calls)" 4 "recovering to low re-arms"
alert '[{"id":"hidpp_battery_0","name":"G Pro","percent":35,"level":null,"alert":"none"}]'
alert "$mouse"; assert_eq "$(calls)" 5 "recovering to none re-arms"
if alert 'invalid JSON' 2>/dev/null; then fail "invalid input fails"; else pass "invalid input fails"; fi
alert "$mouse"; assert_eq "$(calls)" 5 "invalid input preserves the current episode"
alert '[{"id":"../pad/unsafe","name":"Pad","percent":3,"level":null,"alert":"critical"}]'
if [ -f "$TMP/state/.._pad_unsafe" ]; then pass "ids cannot escape the state directory"; else fail "ids cannot escape the state directory"; fi
alert '[{"id":".pad","name":"Pad","percent":3,"level":null,"alert":"critical"}]'
alert '[]'
if [ -e "$TMP/state/.pad" ]; then fail "hidden ids re-arm when absent"; else pass "hidden ids re-arm when absent"; fi
mkdir -p "$TMP/runtime"
printf '%s' "$mouse" | XDG_RUNTIME_DIR="$TMP/runtime" PATH="$TMP/bin:$PATH" bash "$TEST_DIR/battery-alert.sh"
if [ -f "$TMP/runtime/device-alerts/hidpp_battery_0" ]; then pass "default state uses XDG_RUNTIME_DIR"; else fail "default state uses XDG_RUNTIME_DIR"; fi
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/notify-send"
if alert "$mouse"; then fail "delivery failure is reported"; else pass "delivery failure is reported"; fi
if [ -e "$TMP/state/hidpp_battery_0" ]; then fail "failed delivery leaves no marker"; else pass "failed delivery leaves no marker"; fi

test_summary
