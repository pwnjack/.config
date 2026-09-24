#!/usr/bin/env bash
#
# Power Menu
# Lock, logout, reboot and shutdown. Everything but lock asks for confirmation.
#

theme="$HOME/.config/rofi/themes/powermenu/main.rasi"

# Nerd Font glyphs, escaped so no editor can silently drop them.
shutdown=$'\U000F0425' reboot=$'\uEAD2' lock=$'\U000F0341' logout=$'\U000F0206'
yes=$'\uF058' no=$'\uF52F'

confirmed() {
    local answer
    answer=$(printf '%s\n' "$yes" "$no" | rofi -dmenu \
        -theme-str 'window {location: center; anchor: center; fullscreen: false; width: 350px;}' \
        -theme-str 'mainbox {children: [ "message", "listview" ];}' \
        -theme-str 'listview {columns: 2; lines: 1;}' \
        -theme-str 'element-text {horizontal-align: 0.5;}' \
        -theme-str 'textbox {horizontal-align: 0.5;}' \
        -p 'Confirmation' \
        -mesg 'Are you Sure?' \
        -theme "$theme")
    [[ "$answer" == "$yes" ]]
}

chosen=$(printf '%s\n' "$lock" "$logout" "$reboot" "$shutdown" | rofi -dmenu \
    -p $'\uF007'" $USER" \
    -mesg $'\U000F0954'" Uptime: $(uptime -p | sed 's/up //')" \
    -theme "$theme")

case "$chosen" in
    "$lock")     hyprlock ;;
    "$logout")   confirmed && hyprctl dispatch 'hl.dsp.exit()' ;;
    "$reboot")   confirmed && systemctl reboot ;;
    "$shutdown") confirmed && systemctl poweroff ;;
esac
