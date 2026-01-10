#!/bin/bash

thmconf="$(cat $HOME/.config/options/theme)"
theme="$thmconf"

echo "modern" > $HOME/.config/options/style
cp -a $HOME/.config/waybar/modern/$theme/. $HOME/.config/waybar/
cp -a $HOME/.config/swaync/modern/$theme/. $HOME/.config/swaync/
cp -a $HOME/.config/rofi/modern/$theme/config.rasi $HOME/.config/rofi/
cp -a $HOME/.config/hypr/themes/modern/hyprland.conf $HOME/.config/hypr/
cp -a $HOME/.config/hypr/themes/modern/hyprlock.conf $HOME/.config/hypr/

sleep 0.5 

killall waybar
waybar &

swaync-client -R
swaync-client -rs

hyprctl reload

sleep 0.5
