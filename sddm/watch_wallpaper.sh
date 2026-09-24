#!/bin/bash
#
# SDDM Wallpaper Sync Script
# Watches for awww wallpaper changes and updates SDDM automatically
# awww cache layout: ~/.cache/awww/<version>/<monitor>
#

# Empty preference means "no preference". Unlike the other consumers this
# script FAILS rather than degrades on an empty value: the inotify guard below
# compares a filename against it, so an empty string matches nothing and SDDM
# sync stops with no error printed anywhere. Both use sites branch explicitly.
# shellcheck source=scripts/lib/wallpaper.sh
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib/wallpaper.sh"
monitor=$(wallpaper_main_monitor)
cache_dir="$HOME/.cache/awww"
update_script="$HOME/.config/sddm/update_sddm.sh"

# Ensure the cache dir exists
mkdir -p "$cache_dir"

# Function to update SDDM wallpaper
update_sddm() {
    if [[ -f "$update_script" ]]; then
        "$update_script" >/dev/null \
            2> >(logger -t sddm-wallpaper-sync) &
    fi
}

# Initial update
update_sddm

# Watch for changes to the monitor's cache file (recursive: version subdir may not exist yet)
if command -v inotifywait &>/dev/null; then
    inotifywait -m -r -e modify,close_write --format '%f' "$cache_dir" 2>/dev/null | while read -r file; do
        # With no preference set, any monitor's cache entry is a real change.
        [[ -z "$monitor" || "$file" == "$monitor" ]] || continue
        # Small delay to ensure file is fully written
        sleep 0.5
        update_sddm
    done
else
    # Fallback: poll every 5 seconds if inotifywait is not available
    while true; do
        sleep 5
        current_wallpaper=$(wallpaper_from_cache "$cache_dir")
        if [[ -n "$current_wallpaper" ]] && [[ "$current_wallpaper" != "$last_wallpaper" ]]; then
            last_wallpaper="$current_wallpaper"
            update_sddm
        fi
    done
fi
