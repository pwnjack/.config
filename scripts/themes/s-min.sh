#!/bin/bash

thmconf="$(cat $HOME/.config/options/theme)"
theme="$thmconf"

echo "minimal" > $HOME/.config/options/style
cp -a $HOME/.config/waybar/minimal/$theme/. $HOME/.config/waybar/
cp -a $HOME/.config/swaync/minimal/$theme/. $HOME/.config/swaync/
cp -a $HOME/.config/rofi/minimal/$theme/config.rasi $HOME/.config/rofi/
cp -a $HOME/.config/hypr/themes/minimal/hyprland.conf $HOME/.config/hypr/
cp -a $HOME/.config/hypr/themes/minimal/hyprlock.conf $HOME/.config/hypr/

sleep 0.5 

killall waybar
waybar &

swaync-client -R
swaync-client -rs

hyprctl reload

sleep 0.5
