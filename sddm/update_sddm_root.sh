#!/bin/bash

# This version runs as root (via systemd service) and doesn't need sudo

monitor=$(cat /home/pwnjack/Dots/Options/mainmonitor 2>/dev/null || echo "eDP-1")
cache_file="/home/pwnjack/.cache/swww/$monitor"
wallpaper=$(grep -v "^Lanczos3" "$cache_file" 2>/dev/null)

# If cache file doesn't have wallpaper, try querying swww directly (if available)
if [[ -z "$wallpaper" ]] || [[ ! -f "$wallpaper" ]]; then
    if command -v swww &>/dev/null && [[ -n "$DISPLAY" ]] || [[ -n "$WAYLAND_DISPLAY" ]]; then
        # Try to get wallpaper from swww (requires XDG_RUNTIME_DIR)
        export XDG_RUNTIME_DIR="/run/user/$(id -u pwnjack 2>/dev/null || echo 1000)"
        wallpaper=$(runuser -l pwnjack -c "swww query 2>/dev/null" | grep "^: $monitor:" | sed 's/.*image: //' | head -n1)
    fi
fi

# Check if wallpaper file exists
if [[ -z "$wallpaper" ]] || [[ ! -f "$wallpaper" ]]; then
    exit 0
fi

genwal="$wallpaper"

# Check if ffmpeg is installed
if ! command -v ffmpeg &>/dev/null; then
    exit 1
fi

# Convert wallpaper to JPG format for SDDM themes (no sudo needed, running as root)
rm -f /usr/share/sddm/themes/win11-sddm-theme/Backgrounds/wallpaper.jpg
rm -f /usr/share/sddm/themes/sddm-astronaut-theme/Backgrounds/wallpaper.jpg

# Use ffmpeg to convert (suppress output when run in background)
ffmpeg -i "$genwal" -y /usr/share/sddm/themes/win11-sddm-theme/Backgrounds/wallpaper.jpg >/dev/null 2>&1
ffmpeg -i "$genwal" -y /usr/share/sddm/themes/sddm-astronaut-theme/Backgrounds/wallpaper.jpg >/dev/null 2>&1

