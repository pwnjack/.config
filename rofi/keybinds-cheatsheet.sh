#!/usr/bin/env bash
#
# Keybinds Cheatsheet
# Shows all keyboard shortcuts in a searchable rofi menu
#

dir="$HOME/.config/rofi/themes/keybinds"

printf '%-32s %s\n' \
    "BASE APPS" "" \
    "  Super + Enter" "Terminal (Ghostty)" \
    "  Super + E" "File Manager (Thunar)" \
    "  Super + N" "Text Editor (Neovim TUI)" \
    "  Super + B" "Web Browser (Zen)" \
    "  Super + T" "Text Editor (KWrite GUI)" \
    "  Super + S" "Screenshot (region)" \
    "  Super + G" "Code Editor (Zed)" \
    "  Super + A" "AI Assistant sidebar" \
    "" "" \
    "WINDOW MANAGEMENT" "" \
    "  Super + Q" "Close window" \
    "  Super + W" "Close window (alt)" \
    "  Super + Shift + Q" "Exit Hyprland" \
    "  Alt + F4" "Close window (alt)" \
    "  Super + V" "Toggle floating" \
    "  Super + F" "Toggle fullscreen" \
    "  Super + Shift + F" "Fullscreen (no gaps)" \
    "  Super + O" "Toggle split" \
    "  Super + P" "Pseudo tiling" \
    "  Super + Shift + V" "Pin window (PiP)" \
    "  Super + L" "Lock screen" \
    "" "" \
    "WAYBAR CONTROLS" "" \
    "  Super + Shift + B" "Toggle Waybar" \
    "  Super + Alt + B" "Hide Waybar" \
    "  Super + Ctrl + B" "Waybar options" \
    "" "" \
    "ROFI LAUNCHERS" "" \
    "  Super + Space" "App launcher (Spotlight)" \
    "  Super + Shift + L" "Power menu" \
    "  Super + Shift + S" "Screenshot menu" \
    "  Super + C" "Clipboard history" \
    "  Super + ." "Emoji picker" \
    "" "" \
    "WORKSPACES" "" \
    "  Super + 1-9,0" "Switch to workspace" \
    "  Super + Shift + 1-9,0" "Move window to workspace" \
    "  Super + Left/Right" "Previous/Next workspace" \
    "  Super + Shift + Left/Right" "Move window & follow" \
    "  Super + Mouse Scroll" "Cycle workspaces" \
    "" "" \
    "WINDOW NAVIGATION" "" \
    "  Alt + Arrows" "Move focus" \
    "  Super + Tab" "Cycle next window" \
    "  Super + Shift + Tab" "Cycle previous" \
    "  Alt + Ctrl + Arrows" "Resize window" \
    "  Alt + Shift + Arrows" "Move floating window" \
    "  Super + Mouse1 Drag" "Move window" \
    "  Super + Mouse2 Drag" "Resize window" \
    "" "" \
    "NOTIFICATIONS" "" \
    "  Super + Shift + N" "Toggle notification sidebar" \
    "" "" \
    "UTILITIES" "" \
    "  Super + K" "Calculator" \
    "  Super + H" "Keybinds cheatsheet" \
    "  Super + I" "Settings menu" \
    "  Super + Shift + W" "Random wallpaper" \
    "  Super + Ctrl + W" "Waypaper GUI" \
    "  Ctrl + Shift + Esc" "System monitor" \
    "" "" \
    "MULTIMEDIA" "" \
    "  XF86AudioRaiseVolume" "Volume up" \
    "  XF86AudioLowerVolume" "Volume down" \
    "  XF86AudioMute" "Mute toggle" \
    "  XF86MonBrightnessUp" "Brightness up" \
    "  XF86MonBrightnessDown" "Brightness down" \
    "  XF86AudioNext" "Next track" \
    "  XF86AudioPrev" "Previous track" \
    "  XF86AudioPlay" "Play/Pause" | \
rofi -dmenu \
    -p "Keybinds" \
    -theme ${dir}/main.rasi \
    -i \
    -no-custom \
    -select "" \
    -kb-custom-1 "" \
    -kb-accept-entry "" \
    -kb-accept-alt "" \
    -kb-row-select ""
