#!/bin/bash
#
# SDDM Wallpaper Sync Script
# Watches for swww wallpaper changes and updates SDDM automatically
#

monitor=$(cat "$HOME/.config/options/mainmonitor" 2>/dev/null || echo "eDP-1")
cache_file="$HOME/.cache/swww/$monitor"
update_script="$HOME/.config/sddm/update_sddm.sh"

# Ensure the cache file exists
mkdir -p "$(dirname "$cache_file")"
touch "$cache_file"

# Function to update SDDM wallpaper
update_sddm() {
    if [[ -f "$update_script" ]]; then
        "$update_script" >/dev/null 2>&1 &
    fi
}

# Initial update
update_sddm

# Watch for changes to the cache file
if command -v inotifywait &>/dev/null; then
    inotifywait -m -e modify,close_write --format '%e' "$cache_file" 2>/dev/null | while read -r event; do
        # Small delay to ensure file is fully written
        sleep 0.5
        update_sddm
    done
else
    # Fallback: poll every 5 seconds if inotifywait is not available
    while true; do
        sleep 5
        current_wallpaper=$(grep -v "^Lanczos3" "$cache_file" 2>/dev/null)
        if [[ -n "$current_wallpaper" ]] && [[ "$current_wallpaper" != "$last_wallpaper" ]]; then
            last_wallpaper="$current_wallpaper"
            update_sddm
        fi
    done
fi

