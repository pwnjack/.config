#!/bin/bash
#
# Battery status for waybar -- every battery on the machine, system or
# peripheral.
#
# waybar's own battery module counts only POWER_SUPPLY_SCOPE=System, which is
# why it logged "No batteries." on this desktop while a wireless mouse sat on
# the bus with a perfectly readable charge. This module reads sysfs directly.
#
# SCOPE selects behaviour rather than filtering:
#
#   Device            a peripheral. Silent until it drops below LOW, so it
#                     costs no permanent bar space. The module APPEARING is
#                     the warning -- that is what keeps this stateless, with
#                     nothing to remember and nothing to expire.
#   System or absent  the machine's own battery. Always shown, at every level,
#                     because a laptop battery is a status readout rather than
#                     an alert.
#
# A powered-off peripheral keeps its sysfs node AND its last capacity reading
# -- verified by switching the mouse off, which left CAPACITY=75 in place. The
# only field that told the truth was POWER_SUPPLY_ONLINE, which flipped 1 -> 0.
# The test is present-and-0 rather than "not 1": a laptop battery generally
# carries no ONLINE attribute at all (it lives on the Mains adapter) and must
# not be skipped by it.
#
# Charge state is honoured for system batteries only. This mouse reported
# Discharging and then Unknown minutes apart while sitting still, so a
# peripheral's STATUS is not evidence of anything. For a system battery it is
# reliable, and charging suppresses the alert classes -- which is what the old
# `#battery.critical:not(.charging)` rule encoded.
#
# BATTERY_SYSFS overrides the scan root; test-battery.sh points it at fixtures.
#

LOW=25
CRITICAL=10
SYSFS="${BATTERY_SYSFS:-/sys/class/power_supply}"

# Nerd Font, Material Design range.
ICON_SYSTEM=$'\U000f0079'    # battery
ICON_MOUSE=$'\U000f037d'     # mouse
ICON_KEYBOARD=$'\U000f030c'  # keyboard
ICON_HEADSET=$'\U000f02cb'   # headphones
ICON_DEVICE=$'\U000f0083'    # battery-alert, for a peripheral we cannot name

# Fields of the uevent currently being read.
u_type=""; u_cap=""; u_scope=""; u_online=""; u_model=""; u_status=""

# read_uevent <path> — parse one uevent into the u_* variables.
read_uevent() {
    local key val
    u_type=""; u_cap=""; u_scope=""; u_online=""; u_model=""; u_status=""
    while IFS='=' read -r key val; do
        case "$key" in
            # TYPE appears twice in a hidpp uevent. Keep the first.
            POWER_SUPPLY_TYPE)       [ -n "$u_type" ] || u_type="$val" ;;
            POWER_SUPPLY_CAPACITY)   u_cap="$val" ;;
            POWER_SUPPLY_SCOPE)      u_scope="$val" ;;
            POWER_SUPPLY_ONLINE)     u_online="$val" ;;
            POWER_SUPPLY_MODEL_NAME) u_model="$val" ;;
            POWER_SUPPLY_STATUS)     u_status="$val" ;;
        esac
    done < "$1"
}

# device_icon <model> — a glyph from the vendor string, which is all sysfs
# gives us. upower knows the real device type, but costs a daemon and a D-Bus
# round trip per device per poll; an unmatched device gets a generic battery
# glyph, which is unspecific rather than wrong.
device_icon() {
    case "${1,,}" in
        *mouse*)               printf '%s' "$ICON_MOUSE" ;;
        *keyboard*|*keypad*)   printf '%s' "$ICON_KEYBOARD" ;;
        *headset*|*headphone*) printf '%s' "$ICON_HEADSET" ;;
        *)                     printf '%s' "$ICON_DEVICE" ;;
    esac
}

# entry <icon> <capacity> — one rendered chunk of the bar text. The glyph is
# promoted a fifth to match the bar scale (13px base); see waybar/style.css.
# Two spaces, not one: like the volume glyph, a battery glyph carries ink to
# the right and the wider spacer is what makes it look equal to its neighbours.
entry() {
    printf '<span size="large">%s</span>  %s%%' "$1" "$2"
}

declare -a system_text=()
# capacity driving the class; empty means "not alerting" -- unlike a
# sentinel number, no value CAPACITY can take (even a malformed one out of
# sysfs's normal 0-100 range) can ever be mistaken for "nothing is alerting".
system_worst=""
low_worst=""
declare -a low_text=()
declare -a tips=()

shopt -s nullglob
for uevent in "$SYSFS"/*/uevent; do
    [ -r "$uevent" ] || continue
    read_uevent "$uevent"

    [ "$u_type" = "Battery" ] || continue

    # A missing or non-numeric capacity would make the arithmetic tests below
    # throw into waybar's log once every interval.
    case "$u_cap" in ''|*[!0-9]*) continue ;; esac

    # Present-and-0 only. See the header.
    [ "$u_online" = "0" ] && continue

    dir="${uevent%/uevent}"
    label="${u_model:-${dir##*/}}"

    if [ "$u_scope" = "Device" ]; then
        tips+=("$label  $u_cap%")
        if [ "$u_cap" -lt "$LOW" ]; then
            low_text+=("$(entry "$(device_icon "$u_model")" "$u_cap")")
            if [ -z "$low_worst" ] || [ "$u_cap" -lt "$low_worst" ]; then
                low_worst="$u_cap"
            fi
        fi
    else
        # Accumulate, don't overwrite: dual-battery laptops are a real target,
        # and a second, healthier battery must never hide a nearly-flat one.
        system_text+=("$(entry "$ICON_SYSTEM" "$u_cap")")
        case "$u_status" in
            # "Not charging" means AC is connected but something is inhibiting
            # the charge -- almost always a charge_control_end_threshold on a
            # ThinkPad or a Dell/ASUS platform module. The machine is on mains,
            # so however low the number is it is not an emergency, and treating
            # it as discharging would raise exactly the false alarm that
            # suppressing Charging exists to prevent.
            Charging|Full|"Not charging")
                tips+=("$label  $u_cap% ($u_status)")
                ;;
            *)
                tips+=("$label  $u_cap%")
                # Only a discharging system battery can raise an alert; take
                # the minimum across all of them so the worst one always wins.
                if [ -z "$system_worst" ] || [ "$u_cap" -lt "$system_worst" ]; then
                    system_worst="$u_cap"
                fi
                ;;
        esac
    fi
done
shopt -u nullglob

declare -a parts=()
[ "${#system_text[@]}" -gt 0 ] && parts+=("${system_text[@]}")
[ "${#low_text[@]}" -gt 0 ] && parts+=("${low_text[@]}")

# Nothing worth saying: print nothing and let waybar hide the module, the same
# idiom custom/media uses.
[ "${#parts[@]}" -eq 0 ] && exit 0

worst=""
[ -n "$system_worst" ] && worst="$system_worst"
if [ -n "$low_worst" ] && { [ -z "$worst" ] || [ "$low_worst" -lt "$worst" ]; }; then
    worst="$low_worst"
fi

# Empty worst means nothing discharging ever qualified as an alert -- a
# healthy or absent battery, or one that is charging/full.
class="ok"
if [ -n "$worst" ]; then
    if [ "$worst" -lt "$CRITICAL" ]; then
        class="critical"
    elif [ "$worst" -lt "$LOW" ]; then
        class="low"
    fi
fi

text=""
for part in "${parts[@]}"; do
    [ -n "$text" ] && text+="  "
    text+="$part"
done

tooltip=""
for tip in "${tips[@]}"; do
    [ -n "$tooltip" ] && tooltip+=$'\n'
    tooltip+="$tip"
done

# `text` is ours: glyphs and digits, no vendor string, so its markup is safe.
# `tooltip` carries model names, which are arbitrary vendor text -- "Corsair
# HS80 & Mouse" is malformed Pango and would blank the tooltip. Escape it.
jq -nc --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" '
    def pango: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    {text: $text, tooltip: ($tooltip | pango), class: $class}'
