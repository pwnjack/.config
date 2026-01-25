#!/usr/bin/env bash
#
# Power Menu
# Shutdown, reboot, lock, logout options
#

dir="$HOME/.config/rofi/themes/powermenu"

# System info
uptime="$(uptime -p | sed -e 's/up //g')"

# Options
shutdown='󰐥'
reboot=''
lock='󰍁'
logout='󰈆'
yes=''
no=''

rofi_cmd() {
    rofi -dmenu \
        -p " $USER" \
        -mesg "󰥔 Uptime: $uptime" \
        -theme ${dir}/main.rasi
}

confirm_cmd() {
    rofi -theme-str 'window {location: center; anchor: center; fullscreen: false; width: 350px;}' \
        -theme-str 'mainbox {children: [ "message", "listview" ];}' \
        -theme-str 'listview {columns: 2; lines: 1;}' \
        -theme-str 'element-text {horizontal-align: 0.5;}' \
        -theme-str 'textbox {horizontal-align: 0.5;}' \
        -dmenu \
        -p 'Confirmation' \
        -mesg 'Are you Sure?' \
        -theme ${dir}/main.rasi
}

confirm_exit() {
    echo -e "$yes\n$no" | confirm_cmd
}

run_rofi() {
    echo -e "$lock\n$logout\n$reboot\n$shutdown" | rofi_cmd
}

run_cmd() {
    selected="$(confirm_exit)"
    if [[ "$selected" == "$yes" ]]; then
        if [[ $1 == '--shutdown' ]]; then
            systemctl poweroff
        elif [[ $1 == '--reboot' ]]; then
            systemctl reboot
        elif [[ $1 == '--logout' ]]; then
            hyprctl dispatch exit
        fi
    else
        exit 0
    fi
}

chosen="$(run_rofi)"
case ${chosen} in
    $shutdown)
        run_cmd --shutdown
        ;;
    $reboot)
        run_cmd --reboot
        ;;
    $logout)
        run_cmd --logout
        ;;
    $lock)
        hyprlock
        ;;
esac
