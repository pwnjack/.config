#!/bin/bash

sleep 1

primary_monitor=$(cat "$HOME/.config/options/mainmonitor")
wallpaper=$(swww query | grep "^: $primary_monitor:" | sed 's/.*image: //')

genwal=$wallpaper
wallname=$(echo $genwal | sed 's/.*\///')

rm $HOME/.config/options/wallpaper
ln -s $genwal $HOME/.config/options/wallpaper
echo "* { wallpaper: url(\"$genwal\", width); }" > "$HOME/.config/rofi/options/wallpaper.rasi"

wal -q -i $genwal

# Wait for wal to finish generating colors
sleep 0.5

# Apply pywal colors to all components
$HOME/.config/ghostty/apply_wal_colors.sh &
$HOME/.config/Thunar/apply_wal_colors.sh &
$HOME/.config/mako/apply_wal_colors.sh &
$HOME/.config/scripts/waybar/waybar.sh &

notify-send -i preferences-desktop-wallpaper-symbolic "Wallpaper Applied" "New color scheme generated from image:\n$wallname"


eww reload 2>/dev/null
