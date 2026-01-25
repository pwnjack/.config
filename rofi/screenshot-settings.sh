#!/usr/bin/env bash
#
# Screenshot Settings
# Timer and freeze options
#

dir="$HOME/.config/rofi/themes/screenshot"

# Options
option_1=""
option_2="󱎫"
option_3="󱤳"

rofi_cmd() {
    rofi -dmenu \
        -theme ${dir}/settings.rasi \
        -p " $USER" \
        -mesg "Back | Toggle Timer | Toggle Freeze"
}

run_rofi() {
    echo -e "$option_1\n$option_2\n$option_3" | rofi_cmd
}

timer() {
    $HOME/.config/rofi/screenshot-timer.sh
    $HOME/.config/rofi/screenshot.sh
}

freeze() {
    if grep -q "true" "$HOME/.config/options/screenshot"; then
        notify-send -i applets-screenshooter-symbolic "Disabled Screenshot Freeze"
        echo "false" > $HOME/.config/options/screenshot
        echo "" > $HOME/.config/rofi/options/screenshot/freeze
    else
        notify-send -i applets-screenshooter-symbolic "Enabled Screenshot Freeze" "This may not work on virtual machines"
        echo "true" > $HOME/.config/options/screenshot
        echo "-z" > $HOME/.config/rofi/options/screenshot/freeze
    fi
    $HOME/.config/rofi/screenshot.sh
}

back() {
    $HOME/.config/rofi/screenshot.sh
}

run_cmd() {
    if [[ "$1" == '--opt1' ]]; then
        back
    elif [[ "$1" == '--opt2' ]]; then
        timer
    elif [[ "$1" == '--opt3' ]]; then
        freeze
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
esac
