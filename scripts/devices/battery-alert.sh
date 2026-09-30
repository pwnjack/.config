#!/bin/bash
#
# Very-low-battery notification: reads devices.sh JSON on stdin and sends one
# toast per critical episode per device. The marker file is the episode; it is
# removed when connected and no longer critical (or gone), which re-arms
# it. Sleeping devices retain their episode. XDG_RUNTIME_DIR is tmpfs, so a
# reboot re-arms everything.
#
# The icon is the non-symbolic battery-caution: swaync draws nothing for
# Papirus-Dark's symbolic names.

command -v jq >/dev/null 2>&1 || exit 1
command -v notify-send >/dev/null 2>&1 || exit 1
command -v flock >/dev/null 2>&1 || exit 1
command -v timeout >/dev/null 2>&1 || exit 1

devices=$(cat)
# An unreadable snapshot must not re-arm devices whose episode is ongoing.
jq -e 'type == "array"' >/dev/null 2>&1 <<<"$devices" || exit 1
rows=$(jq -c '.[] | select(.state == "connected" and .alert == "critical")' <<<"$devices") || exit 1
state="${DEVICE_ALERT_STATE:-${XDG_RUNTIME_DIR:-/tmp}/device-alerts}"
mkdir -p "$state" || exit 1
# Serialize overlapping polls without introducing a lock file among markers.
exec 9< "$state" || exit 1
flock -x -w 2 9 || exit 1

# Retain asleep devices as well as ongoing critical episodes. Only a
# connected, recovered device or an absent device can re-arm a marker.
retained=$(jq -r '.[] | select(.state != "connected" or .alert == "critical") | .id' <<<"$devices") || exit 1
declare -A keep=()
while IFS= read -r id; do
    [ -n "$id" ] || continue
    key=${id//[^A-Za-z0-9._-]/_}
    case "$key" in .|..) key="_$key" ;; esac
    keep[$key]=1
done <<<"$retained"
result=0
while IFS= read -r device; do
    [ -n "$device" ] || continue
    id=$(jq -r '.id' <<<"$device")
    [ -n "$id" ] || continue
    name=$(jq -r '.name' <<<"$device")
    value=$(jq -r 'if .percent != null then "\(.percent)%"
        else ((.level[0:1] | ascii_upcase) + .level[1:]) end' <<<"$device")
    key=${id//[^A-Za-z0-9._-]/_}
    case "$key" in .|..) key="_$key" ;; esac
    [ -e "$state/$key" ] && continue
    if timeout 5 notify-send -a Devices -i battery-caution "$name battery very low" "$value"; then
        : > "$state/$key" || result=1
    else
        result=1
    fi
done <<<"$rows"
# Dot-prefixed ids are valid too; directories are never episode markers.
shopt -s nullglob dotglob
for marker in "$state"/*; do
    [ -f "$marker" ] || continue
    [ -n "${keep[${marker##*/}]:-}" ] || rm -f -- "$marker" || result=1
done
exit "$result"
