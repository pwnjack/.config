#!/bin/bash
#
# Tests for scripts/waybar/battery.sh.
#
# Standalone and runnable on its own, exit 1 on any failure. It executes the
# script under test as a subprocess, because that is exactly how waybar runs
# it -- unlike scripts/doctor/test/test-*.sh, which are sourced fragments
# sharing one shell so that severity counters survive. Both styles are kept:
# ../../test.sh runs each suite as a subprocess and asks nothing of it beyond
# an exit code, so neither had to be rewritten to fit the other.
#
# jq is used to read fields back out. That is not a new dependency: battery.sh
# already requires it to emit the JSON in the first place.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATTERY="$TEST_DIR/battery.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASSED=0
FAILED=0

# fixture — a fresh empty sysfs root
fixture() {
    mktemp -d "$TMP/sysfs.XXXXXX"
}

# supply <root> <name> <KEY=VALUE>...
supply() {
    local root=$1 name=$2
    shift 2
    mkdir -p "$root/$name"
    printf '%s\n' "$@" > "$root/$name/uevent"
}

# run <root> — stdout of the module under that sysfs root
run() {
    BATTERY_SYSFS="$1" bash "$BATTERY" 2>"$TMP/stderr"
}

pass() { PASSED=$((PASSED + 1)); echo "  ok   $1"; }
fail() {
    FAILED=$((FAILED + 1))
    echo "  FAIL $1"
    shift
    printf '       %s\n' "$@"
}

# assert_silent <output> <label>
assert_silent() {
    if [ -z "$1" ]; then pass "$2"; else fail "$2" "expected no output" "got: $1"; fi
}

# assert_field <output> <jq-filter> <expected> <label>
assert_field() {
    local actual
    actual=$(printf '%s' "$1" | jq -r "$2" 2>/dev/null)
    if [ "$actual" = "$3" ]; then
        pass "$4"
    else
        fail "$4" "filter:   $2" "expected: $3" "actual:   $actual" "json:     $1"
    fi
}

# assert_contains <output> <jq-filter> <needle> <label>
assert_contains() {
    local actual
    actual=$(printf '%s' "$1" | jq -r "$2" 2>/dev/null)
    if printf '%s' "$actual" | grep -qF -- "$3"; then
        pass "$4"
    else
        fail "$4" "expected to contain: $3" "actual: $actual"
    fi
}

echo "battery.sh"

# --- peripherals: the auto-hiding tier -------------------------------------

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=76" \
    "POWER_SUPPLY_MODEL_NAME=G Pro Wireless Gaming Mouse"
assert_silent "$(run "$r")" "peripheral at 76% is silent"

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=25" \
    "POWER_SUPPLY_MODEL_NAME=Mouse"
assert_silent "$(run "$r")" "peripheral at exactly 25% is silent (rule is < LOW)"

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=24" \
    "POWER_SUPPLY_MODEL_NAME=Mouse"
out=$(run "$r")
assert_field "$out" '.class' "low" "peripheral at 24% is low"
assert_contains "$out" '.text' "24%" "peripheral at 24% shows its level"

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=10" \
    "POWER_SUPPLY_MODEL_NAME=Mouse"
assert_field "$(run "$r")" '.class' "low" "peripheral at exactly 10% is low, not critical"

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=9" \
    "POWER_SUPPLY_MODEL_NAME=Mouse"
assert_field "$(run "$r")" '.class' "critical" "peripheral at 9% is critical"

# --- the powered-off case: the whole reason ONLINE is read -----------------

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=0" "POWER_SUPPLY_CAPACITY=9" \
    "POWER_SUPPLY_MODEL_NAME=Mouse"
assert_silent "$(run "$r")" "powered-off peripheral at 9% is ignored, not critical"

# --- system battery: the always-visible tier -------------------------------

r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=System" \
    "POWER_SUPPLY_CAPACITY=64" "POWER_SUPPLY_STATUS=Discharging" \
    "POWER_SUPPLY_MODEL_NAME=DELL ABC123"
out=$(run "$r")
assert_contains "$out" '.text' "64%" "system battery at 64% is shown"
assert_field "$out" '.class' "ok" "system battery at 64% is class ok"

r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_CAPACITY=100" \
    "POWER_SUPPLY_STATUS=Full" "POWER_SUPPLY_MODEL_NAME=DELL ABC123"
assert_contains "$(run "$r")" '.text' "100%" "system battery with no SCOPE and no ONLINE is shown"

r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=System" \
    "POWER_SUPPLY_CAPACITY=8" "POWER_SUPPLY_STATUS=Discharging" \
    "POWER_SUPPLY_MODEL_NAME=DELL ABC123"
assert_field "$(run "$r")" '.class' "critical" "system battery at 8% discharging is critical"

r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=System" \
    "POWER_SUPPLY_CAPACITY=8" "POWER_SUPPLY_STATUS=Charging" \
    "POWER_SUPPLY_MODEL_NAME=DELL ABC123"
out=$(run "$r")
assert_field "$out" '.class' "ok" "system battery at 8% charging is not an alert"
assert_contains "$out" '.text' "8%" "charging system battery still shows its level"

# "Not charging" is what a ThinkPad (and Dell/ASUS platform modules) report when
# AC is connected but a charge_control_end_threshold is inhibiting the charge.
# The machine is on mains, so it is not an emergency however low the number is.
r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=System" \
    "POWER_SUPPLY_CAPACITY=8" "POWER_SUPPLY_STATUS=Not charging" \
    "POWER_SUPPLY_MODEL_NAME=DELL ABC123"
out=$(run "$r")
assert_field "$out" '.class' "ok" "system battery at 8% 'Not charging' is on mains, not an alert"
assert_contains "$out" '.tooltip' "Not charging" "the tooltip says why it is not charging"

# --- both kinds present ----------------------------------------------------

r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=System" \
    "POWER_SUPPLY_CAPACITY=64" "POWER_SUPPLY_STATUS=Discharging" \
    "POWER_SUPPLY_MODEL_NAME=DELL ABC123"
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=18" \
    "POWER_SUPPLY_MODEL_NAME=G Pro Wireless Gaming Mouse"
out=$(run "$r")
assert_contains "$out" '.text' "64%" "system battery present in text"
assert_contains "$out" '.text' "18%" "low peripheral joins the text"
assert_field "$out" '.class' "low" "class comes from the most urgent entry"
assert_field "$out" '.text | test("64%.*18%")' "true" "system battery is rendered first"

r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=System" \
    "POWER_SUPPLY_CAPACITY=64" "POWER_SUPPLY_STATUS=Discharging" \
    "POWER_SUPPLY_MODEL_NAME=DELL ABC123"
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=80" \
    "POWER_SUPPLY_MODEL_NAME=G Pro Wireless Gaming Mouse"
out=$(run "$r")
assert_field "$out" '.text | test("80%")' "false" "healthy peripheral stays out of the text"
assert_contains "$out" '.tooltip' "80%" "healthy peripheral is still in the tooltip"

# --- two low peripherals at once -------------------------------------------

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=24" \
    "POWER_SUPPLY_MODEL_NAME=Mouse"
supply "$r" hidpp_battery_1 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=9" \
    "POWER_SUPPLY_MODEL_NAME=Keyboard"
out=$(run "$r")
assert_contains "$out" '.text' "24%" "first low peripheral joins the text"
assert_contains "$out" '.text' "9%" "second low peripheral joins the text"
assert_field "$out" '.class' "critical" "class comes from the lower of two low peripherals"

# --- two system batteries: dual-battery laptops are common, and the design
# names them as a target. system_text and system_worst must accumulate, not
# overwrite -- otherwise whichever battery the scan visits last wins outright,
# and a healthy second battery can hide a nearly-flat first one completely.

r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=System" \
    "POWER_SUPPLY_CAPACITY=5" "POWER_SUPPLY_STATUS=Discharging" \
    "POWER_SUPPLY_MODEL_NAME=BAT0 nearly flat"
supply "$r" BAT1 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=System" \
    "POWER_SUPPLY_CAPACITY=90" "POWER_SUPPLY_STATUS=Discharging" \
    "POWER_SUPPLY_MODEL_NAME=BAT1 healthy"
out=$(run "$r")
assert_contains "$out" '.text' "5%" "nearly-flat system battery appears in text"
assert_contains "$out" '.text' "90%" "healthy second system battery also appears in text"
assert_field "$out" '.class' "critical" "class comes from the lower of two system batteries"

# --- nothing to report -----------------------------------------------------

r=$(fixture)
assert_silent "$(run "$r")" "empty sysfs is silent"

r=$(fixture)
supply "$r" AC \
    "POWER_SUPPLY_TYPE=Mains" "POWER_SUPPLY_ONLINE=1"
assert_silent "$(run "$r")" "a Mains supply is not a battery"

# --- parsing robustness ----------------------------------------------------

r=$(fixture)
supply "$r" weird \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=" \
    "POWER_SUPPLY_MODEL_NAME=Broken"
out=$(run "$r")
assert_silent "$out" "empty capacity is skipped"
if [ -s "$TMP/stderr" ]; then
    fail "empty capacity produces no stderr" "stderr: $(cat "$TMP/stderr")"
else
    pass "empty capacity produces no stderr"
fi

r=$(fixture)
supply "$r" weird \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=unknown" \
    "POWER_SUPPLY_MODEL_NAME=Broken"
assert_silent "$(run "$r")" "non-numeric capacity is skipped"

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=18" \
    "POWER_SUPPLY_MODEL_NAME=Corsair HS80 & Mouse"
assert_contains "$(run "$r")" '.tooltip' "&amp;" "an ampersand in a model name is escaped"

# --- a real hidpp uevent, TYPE twice and all ------------------------------

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "DEVTYPE=power_supply" "POWER_SUPPLY_NAME=hidpp_battery_0" \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_STATUS=Unknown" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_VOLTAGE_NOW=3965000" \
    "POWER_SUPPLY_CAPACITY=18" "POWER_SUPPLY_TYPE=Battery" \
    "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_MODEL_NAME=G Pro Wireless Gaming Mouse" \
    "POWER_SUPPLY_MANUFACTURER=Logitech" "POWER_SUPPLY_SERIAL_NUMBER=5c-1c-d2-07"
out=$(run "$r")
assert_field "$out" '.class' "low" "a verbatim hidpp uevent parses"
assert_contains "$out" '.tooltip' "G Pro Wireless Gaming Mouse" "model name reaches the tooltip"

echo
echo "battery.sh: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
