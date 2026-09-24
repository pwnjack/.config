#!/usr/bin/env bash
#
# Screenshot Timer Selection
# Stores the capture delay, in whole seconds, for rofi/screenshot.sh.
#

chosen=$(printf '%s\n' 0s 3s 5s 10s 30s | rofi -dmenu \
    -theme "$HOME/.config/rofi/themes/screenshot/timer.rasi" \
    -p $'\uF007'" $USER")

[[ "$chosen" =~ ^[0-9]+s$ ]] || exit 0

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$cache_dir"
echo "${chosen%s}" > "$cache_dir/screenshot-delay"
