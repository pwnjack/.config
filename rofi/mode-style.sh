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
modstl='✨️'
colstl='🌈'
minstl='👾'

# Rofi CMD
rofi_cmd() {
	rofi -dmenu \
		-p " $USER" \
		-mesg "Modern | Colorful | Minimal" \
		-theme ${dir}/${mode}.rasi
}

# Pass variables to rofi dmenu
run_rofi() {
	echo -e "$modstl\n$colstl\n$minstl" | rofi_cmd
}

# Actions
chosen="$(run_rofi)"
case ${chosen} in
    $modstl)
    	$HOME/.config/scripts/Themes/s-mod.sh
    	notify-send -i preferences-color-symbolic "Modern Theme Active" "You may need to log out for all settings to apply."
        ;;
    $colstl)
    	$HOME/.config/scripts/Themes/s-col.sh
    	notify-send -i preferences-color-symbolic "Colorful Theme Active" "You may need to log out for all settings to apply."
        ;;
    $minstl)
    	$HOME/.config/scripts/Themes/s-min.sh
    	notify-send -i preferences-color-symbolic "Minimal Theme Active" "You may need to log out for all settings to apply."
        ;;
esac
