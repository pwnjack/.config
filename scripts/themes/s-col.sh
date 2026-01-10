#!/bin/bash

thmconf="$(cat $HOME/.config/options/theme)"
theme="$thmconf"

echo "colorful" > $HOME/.config/options/style
cp -a $HOME/.config/waybar/colorful/$theme/. $HOME/.config/waybar/
cp -a $HOME/.config/swaync/colorful/$theme/. $HOME/.config/swaync/
cp -a $HOME/.config/rofi/colorful/$theme/config.rasi $HOME/.config/rofi/
cp -a $HOME/.config/hypr/themes/colorful/hyprland.conf $HOME/.config/hypr/
cp -a $HOME/.config/hypr/themes/colorful/hyprlock.conf $HOME/.config/hypr/

sleep 0.5 

killall waybar
waybar &

swaync-client -R
swaync-client -rs

hyprctl reload

sleep 0.5
