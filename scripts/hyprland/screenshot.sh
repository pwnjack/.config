#!/bin/bash
#
# Capture a screenshot to ~/Pictures/Screenshots.
#
# Usage: screenshot.sh output|window|region
#
# The one capture command shared by the Super+S keybind and the rofi screenshot
# menu, so both honour options/screenshot ("true" freezes the screen while
# selecting). The rofi menu applies its own delay before calling this.
#

mode="${1:-region}"
case "$mode" in
    output|window|region) ;;
    *) echo "usage: ${0##*/} output|window|region" >&2; exit 2 ;;
esac

command -v hyprshot >/dev/null 2>&1 || exit 0

args=(-m "$mode" -o "$HOME/Pictures/Screenshots" -f "Screenshot_$(date '+%Y-%m-%d_%H:%M:%S').png")
grep -qx true "$HOME/.config/options/screenshot" 2>/dev/null && args+=(-z)

exec hyprshot "${args[@]}"
