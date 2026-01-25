#!/usr/bin/env bash
#
# Screenshot Menu
# Full screen, window, or region capture
#

dir="$HOME/.config/rofi/themes/screenshot"

timer="$(cat "$HOME/.config/rofi/options/screenshot/timer")"
freeze="$(cat "$HOME/.config/rofi/options/screenshot/freeze")"

# Options
option_1="󰹑"
option_2=""
option_3="󱊅"
option_4=""

rofi_cmd() {
    rofi -dmenu \
        -theme ${dir}/main.rasi \
        -p " $USER" \
        -mesg "Monitor | Window | Selection | Settings"
}

run_rofi() {
    echo -e "$option_1\n$option_2\n$option_3\n$option_4" | rofi_cmd
}

shotscreen() {
    $timer
    hyprshot -m output -o ~/Pictures/Screenshots -f Screenshot_$(date "+%Y-%m-%d_%H:%M:%S").png $freeze
}

shotwin() {
    $timer
    hyprshot -m window -o ~/Pictures/Screenshots -f Screenshot_$(date "+%Y-%m-%d_%H:%M:%S").png $freeze
}

shotarea() {
    $timer
    hyprshot -m region -o ~/Pictures/Screenshots -f Screenshot_$(date "+%Y-%m-%d_%H:%M:%S").png $freeze
}

settings() {
    $HOME/.config/rofi/screenshot-settings.sh
}

run_cmd() {
    if [[ "$1" == '--opt1' ]]; then
        sleep 0.5
        shotscreen
    elif [[ "$1" == '--opt2' ]]; then
        sleep 0.5
        shotwin
    elif [[ "$1" == '--opt3' ]]; then
        sleep 0.5
        shotarea
    elif [[ "$1" == '--opt4' ]]; then
        settings
    fi
}

chosen="$(run_rofi)"
case ${chosen} in
    $option_1)
        run_cmd --opt1
        ;;
    $option_2)
        run_cmd --opt2
        ;;
    $option_3)
        run_cmd --opt3
        ;;
    $option_4)
        run_cmd --opt4
        ;;
esac
