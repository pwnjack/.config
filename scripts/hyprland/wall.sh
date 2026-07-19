#!/bin/bash
#
# Wallpaper Change Pipeline
# Reads the active wallpaper from awww, regenerates the pywal palette,
# and propagates colors to every themed component.
#

sleep 1

primary_monitor=$(cat "$HOME/.config/options/mainmonitor" 2>/dev/null)
wallpaper=$(awww query | grep "^: $primary_monitor:" | sed 's/.*image: //')

# Fallback: first monitor reported by awww
if [ -z "$wallpaper" ]; then
    wallpaper=$(awww query | head -n1 | sed 's/.*image: //')
fi

[ -f "$wallpaper" ] || exit 0

wallname=$(basename "$wallpaper")

# Record the current wallpaper and rofi background in the cache
mkdir -p "$HOME/.cache/wal"
ln -sfn "$wallpaper" "$HOME/.cache/current_wallpaper"
echo "* { wallpaper: url(\"$wallpaper\", width); }" > "$HOME/.cache/wal/rofi-wallpaper.rasi"

wal -q -i "$wallpaper"

# Wait for wal to finish generating colors
sleep 0.5

# Apply pywal colors to all components (each script is optional)
for script in \
    "$HOME/.config/ghostty/apply_wal_colors.sh" \
    "$HOME/.config/Thunar/apply_wal_colors.sh" \
    "$HOME/.config/mako/apply_wal_colors.sh" \
    "$HOME/.config/swaync/apply_wal_colors.sh" \
    "$HOME/.config/scripts/waybar/waybar.sh"; do
    [ -x "$script" ] && "$script" &
done

notify-send -i preferences-desktop-wallpaper-symbolic "Wallpaper Applied" "New color scheme generated from image:\n$wallname"

# Restart the AGS settings panel so it picks up the new palette
if command -v ags >/dev/null 2>&1; then
    astal -i settings-panel --quit 2>/dev/null
    ags run "$HOME/.config/ags/app.ts" &
fi
command -v eww >/dev/null 2>&1 && eww reload 2>/dev/null
