#!/bin/bash
#
# SDDM Wallpaper Sync Script
# Watches for awww wallpaper changes and updates SDDM automatically
# awww cache layout: ~/.cache/awww/<version>/<monitor>
#

monitor=$(cat "$HOME/.config/options/mainmonitor" 2>/dev/null || echo "eDP-1")
cache_dir="$HOME/.cache/awww"
update_script="$HOME/.config/sddm/update_sddm.sh"

# Ensure the cache dir exists
mkdir -p "$cache_dir"

# Function to update SDDM wallpaper
update_sddm() {
    if [[ -f "$update_script" ]]; then
        "$update_script" >/dev/null 2>&1 &
    fi
}

# Initial update
update_sddm

# Watch for changes to the monitor's cache file (recursive: version subdir may not exist yet)
if command -v inotifywait &>/dev/null; then
    inotifywait -m -r -e modify,close_write --format '%f' "$cache_dir" 2>/dev/null | while read -r file; do
        [[ "$file" == "$monitor" ]] || continue
        # Small delay to ensure file is fully written
        sleep 0.5
        update_sddm
    done
else
    # Fallback: poll every 5 seconds if inotifywait is not available
    while true; do
        sleep 5
        cache_file=$(ls -t "$cache_dir"/*/"$monitor" 2>/dev/null | head -n1)
        current_wallpaper=$(grep -oE '/.+$' "$cache_file" 2>/dev/null)
        if [[ -n "$current_wallpaper" ]] && [[ "$current_wallpaper" != "$last_wallpaper" ]]; then
            last_wallpaper="$current_wallpaper"
            update_sddm
        fi
    done
fi

