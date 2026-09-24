#!/usr/bin/env bash
#
# Screenshot Menu
# Full screen, window, or region capture, annotation, and settings.
#

delay=$(cat "${XDG_CACHE_HOME:-$HOME/.cache}/screenshot-delay" 2>/dev/null)
[[ "$delay" =~ ^[0-9]+$ ]] || delay=0

# Nerd Font glyphs, escaped so no editor can silently drop them.
monitor=$'\U000F0E51' window=$'\uEB23' region=$'\U000F1285' annotate=$'\U000F03EB' settings=$'\uE690'

chosen=$(printf '%s\n' "$monitor" "$window" "$region" "$annotate" "$settings" | rofi -dmenu \
    -theme "$HOME/.config/rofi/themes/screenshot/main.rasi" \
    -p $'\uF007'" $USER" \
    -mesg "Monitor | Window | Selection | Annotate | Settings")

# Let rofi's window close before capturing, then wait out the chosen delay.
shoot() {
    sleep 0.5
    sleep "$delay"
    "$HOME/.config/scripts/hyprland/screenshot.sh" "$1"
}

case "$chosen" in
    "$monitor")  shoot output ;;
    "$window")   shoot window ;;
    "$region")   shoot region ;;
    "$annotate") sleep 0.5; "$HOME/.config/scripts/hyprland/screenshot-annotate.sh" ;;
    "$settings") "$HOME/.config/rofi/screenshot-settings.sh" ;;
esac
