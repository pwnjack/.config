#!/bin/bash
# Render Waybar's clock format from options/clock into the include that
# waybar/config.jsonc names. Always leaves the include in place (24 h unless the
# option says 12h), so a fresh checkout or a garbled option still shows a clock.
set -euo pipefail
option="${CLOCK_OPTION:-$HOME/.config/options/clock}"
include="${CLOCK_INCLUDE:-${XDG_STATE_HOME:-$HOME/.local/state}/waybar/clock.jsonc}"
format='{:%H:%M}'
if [[ -r $option && $(<"$option") == 12h ]]; then format='{:%I:%M %p}'; fi
mkdir -p "${include%/*}"
tmp=$(mktemp "$include.XXXXXX")
printf '{ "clock": { "format": "%s" } }\n' "$format" > "$tmp"
mv -f "$tmp" "$include"
if [[ ${1:-} != --no-reload ]]; then pkill -USR2 -x waybar 2>/dev/null || true; fi
