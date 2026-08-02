#!/bin/bash
#
# Wallpaper Restore (run at Hyprland startup, after awww-daemon)
# Re-applies the last wallpaper: waypaper config first, then awww cache.
#

sleep 0.5

# 0. Random wallpaper on startup (options/randomwallpaper = enabled)
#    waypaper --random also runs its post_command (wall.sh), so pywal colors follow
if grep -q "enabled" "$HOME/.config/options/randomwallpaper" 2>/dev/null \
    && command -v waypaper >/dev/null 2>&1; then
    waypaper --random
    exit 0
fi

# 1. Wallpaper saved by waypaper
wp=$(grep "^wallpaper = " "$HOME/.config/waypaper/config.ini" 2>/dev/null \
    | sed "s/^wallpaper = //" | sed "s|^~|$HOME|")
if [ -f "$wp" ]; then
    awww img "$wp"
    exit 0
fi

# 2. Last wallpaper recorded in the awww cache for the main monitor.
#    Empty preference means "no preference", so the newest entry for ANY
#    monitor is taken. Nothing is guessed: this used to hardcode a laptop
#    connector name, which is wrong on any machine that lacks one.
monitor=$(cat "$HOME/.config/options/mainmonitor" 2>/dev/null)
if [ -n "$monitor" ]; then
    cache=$(ls -t "$HOME/.cache/awww/"*/"$monitor" 2>/dev/null | head -n1)
else
    cache=$(ls -t "$HOME/.cache/awww/"*/* 2>/dev/null | head -n1)
fi
if [ -f "$cache" ]; then
    wp=$(grep -oE '/.+$' "$cache")
    [ -f "$wp" ] && awww img "$wp" && exit 0
fi

# 3. Fall back to the current-wallpaper symlink (fresh installs)
wp=$(readlink -f "$HOME/.config/options/wallpaper" 2>/dev/null)
[ -f "$wp" ] && awww img "$wp"
