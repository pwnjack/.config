#!/usr/bin/env bash
#
# Power Menu
# Lock, suspend, logout, reboot and shutdown. Logout, reboot and shutdown ask
# for confirmation, and the confirmation starts on No, so a double Enter is
# never destructive.
#
# Rows are Pango markup (the theme-sized glyph over a small label), so rofi reports
# the selected index (-format i) rather than the row text.
#

theme="$HOME/.config/rofi/themes/powermenu/main.rasi"

# Nerd Font glyphs, escaped so no editor can silently drop them.
lock=$'\U000F0341' suspend=$'\U000F0904' logout=$'\U000F0206' reboot=$'\uEAD2' shutdown=$'\U000F0425'
yes=$'\uF058' no=$'\uF52F'

# row GLYPH LABEL: one menu entry, glyph above its label.
row() {
    printf "%s\n<span font='11'>%s</span>|" "$1" "$2"
}

# confirmed QUESTION: true only if the user picks Yes.
confirmed() {
    local answer
    answer=$({ row "$no" No; row "$yes" Yes; } | rofi -dmenu -markup-rows -sep '|' -eh 2 -format i -no-custom \
        -theme-str 'window {width: 350px;}' \
        -theme-str 'mainbox {children: [ "message", "listview" ];}' \
        -theme-str 'listview {columns: 2; lines: 1;}' \
        -mesg "$1" \
        -theme "$theme")
    [[ "$answer" == 1 ]]
}

chosen=$({
    row "$lock" Lock
    row "$suspend" Suspend
    row "$logout" Logout
    row "$reboot" Reboot
    row "$shutdown" Shutdown
} | rofi -dmenu -markup-rows -sep '|' -eh 2 -format i -no-custom \
    -p $'\uF007'" $USER" \
    -mesg $'\U000F0954'" Uptime: $(uptime -p | sed 's/up //')" \
    -theme "$theme")

# Lock and suspend go the way hypridle does, so neither can start a second
# hyprlock; hypridle's before_sleep_cmd locks the session before suspending.
case "$chosen" in
    0) pidof hyprlock >/dev/null || hyprlock ;;
    1) systemctl suspend ;;
    2) confirmed "Log out of Hyprland?" && hyprctl dispatch 'hl.dsp.exit()' ;;
    3) confirmed "Reboot now?" && systemctl reboot ;;
    4) confirmed "Shut down now?" && systemctl poweroff ;;
esac
