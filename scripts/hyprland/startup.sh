#!/bin/bash
#
# Hyprland Startup Script
# Handles conditional startup actions based on configuration flags
#

# Use ghostty as preferred terminal (fallback to kitty if not available)
TERMINAL="${TERMINAL:-$(command -v ghostty || command -v kitty)}"

if [ -f "$HOME/.config/options/autologin" ] && grep -q "enabled" "$HOME/.config/options/autologin"; then
    # Lock screen on autologin to ensure security
    command -v hyprlock >/dev/null 2>&1 && hyprlock
elif [ -f "$HOME/.config/options/clock" ] && grep -q "enabled" "$HOME/.config/options/clock"; then
    # Open eww clock widget if enabled
    command -v eww >/dev/null 2>&1 && eww open clock
fi
