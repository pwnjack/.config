#!/usr/bin/env bash

stlconf="$(cat $HOME/Dots/Options/style)"
thmconf="$(cat $HOME/Dots/Options/theme)"

config="$stlconf"
theme="$thmconf"

dir="$HOME/.config/rofi/$config/$theme/keybinds"
mode='main'

printf '%-28s %s\n' \
    "BASE APPS" "" \
    "  Super + Enter" "Terminal" \
    "  Super + E" "File Manager" \
    "  Super + T" "Text Editor" \
    "  Super + B" "Browser" \
    "  Super + S" "Screenshot" \
    "  Super + G" "Cursor" \
    "" "" \
    "WINDOW MANAGEMENT" "" \
    "  Super + Q" "Close window" \
    "  Super + W" "Close window" \
    "  Super + Shift + Q" "Exit Hyprland" \
    "  Super + V" "Toggle floating" \
    "  Super + F" "Toggle fullscreen" \
    "  Super + Shift + F" "Fullscreen (all)" \
    "  Super + O" "Toggle split" \
    "  Super + P" "Pseudo" \
    "  Super + Shift + V" "Pin window" \
    "  Super + L" "Lock screen" \
    "" "" \
    "ROFI LAUNCHERS" "" \
    "  Super + Space" "App launcher" \
    "  Super + M" "Mode menu" \
    "  Super + Shift + L" "Power menu" \
    "  Super + Shift + S" "Screenshot menu" \
    "  Super + C" "Clipboard" \
    "  Super + ." "Emoji picker" \
    "" "" \
    "WORKSPACES" "" \
    "  Super + 1-0,=" "Switch workspace" \
    "  Super + Shift + 1-0,=" "Move window" \
    "  Super + Left/Right" "Switch workspace" \
    "  Super + Shift + Left/Right" "Move window" \
    "" "" \
    "NAVIGATION" "" \
    "  Alt + Arrows" "Move focus" \
    "  Super + Tab" "Cycle next" \
    "  Super + Shift + Tab" "Cycle prev" \
    "  Alt + Ctrl + Arrows" "Resize" \
    "  Alt + Shift + Arrows" "Move window" \
    "" "" \
    "UTILITIES" "" \
    "  Super + K" "Calculator" \
    "  Super + H" "This cheatsheet" \
    "  Super + I" "Settings" \
    "  Super + Shift + W" "Waypaper (random)" \
    "  Super + Ctrl + W" "Waypaper" \
    "" "" \
    "MULTIMEDIA" "" \
    "  XF86Audio*" "Volume controls" \
    "  XF86MonBrightness*" "Brightness" \
    "  XF86AudioNext/Prev" "Media" \
    "  XF86AudioPlay/Pause" "Play/Pause" | \
rofi -dmenu \
    -p "Keybinds" \
    -theme ${dir}/${mode}.rasi \
    -i \
    -no-custom \
    -select "" \
    -kb-custom-1 "" \
    -kb-accept-entry "" \
    -kb-accept-alt "" \
    -kb-row-select ""

