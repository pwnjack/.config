#!/usr/bin/env bash

##
## Original Author : Aditya Shakya (adi1090x)
## Original Github : @adi1090x
## Adapted by : @GeodeArc
##

stlconf="$(cat $HOME/.config/options/style)"
thmconf="$(cat $HOME/.config/options/theme)"

config="$stlconf"
theme="$thmconf"

dir="$HOME/.config/rofi/$config/$theme/mode"
mode='main'

# Options
lmode='☀️'
dmode='🌙'
style='🎨'

# Rofi CMD
rofi_cmd() {
	rofi -dmenu \
		-p " $USER" \
		-mesg "Light | Dark | Change Style" \
		-theme ${dir}/${mode}.rasi
}

# Pass variables to rofi dmenu
run_rofi() {
	echo -e "$lmode\n$dmode\n$style" | rofi_cmd
}

# Actions
chosen="$(run_rofi)"
case ${chosen} in
    $lmode)
    	$HOME/.config/scripts/Themes/t-light.sh
    	notify-send -i view-reveal-symbolic "Light Mode Active" "You will need to log out to see cursor theme changes."
        ;;
    $dmode)
    	$HOME/.config/scripts/Themes/t-dark.sh
    	notify-send -i view-reveal-symbolic "Dark Mode Active" "You will need to log out to see cursor theme changes."
        ;;
    $style)
		$HOME/.config/rofi/mode-style.sh
        ;;
esac
