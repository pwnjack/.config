#!/bin/bash
# Tests for scripts/devices/devices.sh against a fake /sys and /run/udev/data.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICES="$TEST_DIR/devices.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck disable=SC1091 # Shared assertions are checked by their own suite.
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

root() { local r; r=$(mktemp -d "$TMP/root.XXXXXX"); mkdir -p "$r/sys/class/power_supply" "$r/sys/class/input" "$r/udev"; printf '%s' "$r"; }
# usb <root> <usbpath> <product> — a USB device dir (has idVendor)
usb() { mkdir -p "$1/sys/devices/$2"; echo 1234 > "$1/sys/devices/$2/idVendor"; echo "$3" > "$1/sys/devices/$2/product"; }
# input <root> <devpath> <n> <TAG>... — input device n under devpath, udev tags ID_INPUT_<TAG>=1
input() {
    local r=$1 dev=$2 n=$3; shift 3
    mkdir -p "$r/sys/devices/$dev/input/input$n"
    ln -s "../../devices/$dev/input/input$n" "$r/sys/class/input/input$n"
    { echo "E:ID_INPUT=1"; for t in "$@"; do echo "E:ID_INPUT_$t=1"; done; } > "$r/udev/+input:input$n"
}
# supply <root> <name> <devpath|-> <KEY=VALUE>... — a power_supply node, linked to devpath unless "-"
supply() {
    local r=$1 name=$2 dev=$3; shift 3
    mkdir -p "$r/sys/class/power_supply/$name"
    printf 'POWER_SUPPLY_%s\n' "$@" > "$r/sys/class/power_supply/$name/uevent"
    [ "$dev" = - ] || ln -s "../../../devices/$dev" "$r/sys/class/power_supply/$name/device"
}
run() { DEVICES_SYSFS="$1/sys" DEVICES_UDEV="$1/udev" bash "$DEVICES"; }
field() { jq -r --arg id "$2" ".[] | select(.id == \$id) | .$3" <<<"$1"; }

echo "devices.sh"

r=$(root)
usb "$r" usb1/1-14 "Lightspeed Receiver"
input "$r" usb1/1-14/1-14:1.2/hid.1/hid.2 19 MOUSE KEY KEYBOARD
supply "$r" hidpp_battery_0 usb1/1-14/1-14:1.2/hid.1/hid.2 TYPE=Battery SCOPE=Device ONLINE=1 CAPACITY=36 "MODEL_NAME=G Pro Wireless Gaming Mouse"
out=$(run "$r")
assert_eq "$(field "$out" hidpp_battery_0 kind)" mouse "a mouse with a keyboard interface is a mouse"
assert_eq "$(field "$out" hidpp_battery_0 percent)" 36 "percent is read"
assert_eq "$(field "$out" hidpp_battery_0 state)" connected "online battery is connected"
assert_eq "$(field "$out" hidpp_battery_0 alert)" none "36% does not alert"
assert_eq "$(jq length <<<"$out")" 1 "the receiver holding a battery is not listed again"

r=$(root)
supply "$r" m - TYPE=Battery SCOPE=Device ONLINE=0 CAPACITY=5 MODEL_NAME=Mouse
out=$(run "$r")
assert_eq "$(field "$out" m state)" asleep "ONLINE=0 is asleep"
assert_eq "$(field "$out" m alert)" none "a stale reading never alerts"
assert_eq "$(field "$out" m kind)" other "no device link means kind other"

r=$(root)
usb "$r" usb1/1-13 "Xbox Wireless Adapter"
input "$r" usb1/1-13/1-13:1.0/gip0/gip0.0 34 JOYSTICK KEY
supply "$r" gip0.0 usb1/1-13/1-13:1.0/gip0/gip0.0 TYPE=Battery SCOPE=Device STATUS=Discharging CAPACITY_LEVEL=Critical "MODEL_NAME=Microsoft Xbox Controller"
out=$(run "$r")
assert_eq "$(field "$out" gip0.0 kind)" gamepad "a joystick is a gamepad"
assert_eq "$(field "$out" gip0.0 percent)" null "level-only device has no percent"
assert_eq "$(field "$out" gip0.0 level)" critical "level is lowercased"
assert_eq "$(field "$out" gip0.0 alert)" critical "level Critical alerts critical"

for case in "18 low" "9 critical" "10 low" "25 none"; do
    read -r pct want <<<"$case"
    r=$(root); supply "$r" b - TYPE=Battery SCOPE=Device CAPACITY="$pct"
    assert_eq "$(field "$(run "$r")" b alert)" "$want" "$pct% alerts $want"
done
r=$(root); supply "$r" b - TYPE=Battery SCOPE=Device CAPACITY_LEVEL=Low
assert_eq "$(field "$(run "$r")" b alert)" low "level Low alerts low"
r=$(root); supply "$r" b - TYPE=Battery SCOPE=Device STATUS=Charging CAPACITY=50
assert_eq "$(field "$(run "$r")" b charging)" true "Charging is reported"

r=$(root)
usb "$r" usb1/1-8 "CX 2.4G Wireless Receiver"
input "$r" usb1/1-8/1-8:1.0/hid.1 3 KEY KEYBOARD
input "$r" usb1/1-8/1-8:1.1/hid.2 8 MOUSE
input "$r" usb1/1-8/1-8:1.1/hid.2 7 KEY
out=$(run "$r")
assert_eq "$(field "$out" 1-8 kind)" keyboard "a keyboard receiver with a mouse interface is a keyboard"
assert_eq "$(field "$out" 1-8 state)" receiver "no battery means receiver"
assert_eq "$(field "$out" 1-8 name)" "CX 2.4G Wireless Receiver" "receiver name is the USB product"
assert_eq "$(jq length <<<"$out")" 1 "one row per USB device"

r=$(root)
mkdir -p "$r/sys/devices/platform/btn"
input "$r" platform/btn 1 KEY KEYBOARD
usb "$r" usb1/1-4 "NZXT Kraken"
supply "$r" BAT0 - TYPE=Battery SCOPE=System CAPACITY=80
assert_eq "$(run "$r")" "[]" "non-USB inputs, input-less USB devices and system batteries are not listed"

r=$(root); supply "$r" b - TYPE=Battery SCOPE=Device CAPACITY=80 CAPACITY_LEVEL=Critical
assert_eq "$(field "$(run "$r")" b alert)" critical "critical level overrides a healthy percent"
r=$(root); supply "$r" b - TYPE=Battery SCOPE=Device CAPACITY=18 CAPACITY_LEVEL=Critical
assert_eq "$(field "$(run "$r")" b alert)" critical "critical level overrides a low percent"

test_summary
