#!/bin/bash
# Render Waybar's clock format from options/clock into the include that
# waybar/config.jsonc names. Always leaves the include in place (24 h unless the
# option says 12h), so a fresh checkout or a garbled option still shows a clock.
# The include path is fixed to match config.jsonc, which cannot expand variables.
set -euo pipefail
option=$HOME/.config/options/clock
include=$HOME/.local/state/waybar/clock.jsonc
option=${CLOCK_OPTION:-$option}
include=${CLOCK_INCLUDE:-$include}
format='{:%H:%M}'
if [[ -r $option && $(<"$option") == 12h ]]; then format='{:%I:%M %p}'; fi
mkdir -p "${include%/*}"
tmp=$(mktemp "$include.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf '{ "clock": { "format": "%s" } }\n' "$format" > "$tmp"
mv -f "$tmp" "$include"
if [[ ${1:-} != --no-reload ]]; then pkill -USR2 -x waybar 2>/dev/null || true; fi
