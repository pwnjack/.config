#!/bin/bash

sleep 1

primary_monitor=$(cat "$HOME/Dots/Options/mainmonitor")
wallpaper=$(swww query | grep "^: $primary_monitor:" | sed 's/.*image: //')

genwal=$wallpaper
wallname=$(echo $genwal | sed 's/.*\///')

rm $HOME/Dots/Options/wallpaper
ln -s $genwal $HOME/Dots/Options/wallpaper
echo "* { wallpaper: url(\"$genwal\", width); }" > "$HOME/.config/rofi/options/wallpaper.rasi"

wal -q -i $genwal

# Wait for wal to finish generating colors
sleep 0.5

# Apply colors to ghostty terminal
$HOME/.config/ghostty/apply_wal_colors.sh &

# Apply colors to Thunar (GTK 3)
$HOME/.config/Thunar/apply_wal_colors.sh &

# Refresh Waybar themes
$HOME/Dots/Scripts/Waybar/waybar.sh &

notify-send -i preferences-desktop-wallpaper-symbolic "Wallpaper Applied" "New color scheme generated from image:\n$wallname"

swaync-client -R
swaync-client -rs

eww reload
