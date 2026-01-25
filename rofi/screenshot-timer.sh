#!/usr/bin/env bash
#
# Screenshot Timer Selection
#

dir="$HOME/.config/rofi/themes/screenshot"

# Options
option_1="0s"
option_2="3s"
option_3="5s"
option_4="10s"
option_5="30s"

rofi_cmd() {
    rofi -dmenu \
        -theme ${dir}/timer.rasi \
        -p " $USER"
}

run_rofi() {
    echo -e "$option_1\n$option_2\n$option_3\n$option_4\n$option_5" | rofi_cmd
}

shot() {
    echo "sleep $seconds" > $HOME/.config/rofi/options/screenshot/timer
}

run_cmd() {
    if [[ "$1" == '--opt1' ]]; then
        seconds="0"
        shot
    elif [[ "$1" == '--opt2' ]]; then
        seconds="3"
        shot
    elif [[ "$1" == '--opt3' ]]; then
        seconds="5"
        shot
    elif [[ "$1" == '--opt4' ]]; then
        seconds="10"
        shot
    elif [[ "$1" == '--opt5' ]]; then
        seconds="30"
        shot
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
    $option_5)
        run_cmd --opt5
        ;;
esac
