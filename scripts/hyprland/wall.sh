#!/bin/bash
# Serialize wallpaper changes, reading the current selection after taking the
# lock so queued requests cannot restore an older palette.
set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -i preferences-desktop-wallpaper "$1" "$2" 9>&- || true
}
fail() {
    echo "wallpaper: $*" >&2
    notify "Wallpaper theme failed" "$*"
    exit 1
}

command -v flock >/dev/null 2>&1 || fail "flock is not installed"
mkdir -p "$cache_dir/wal" || fail "Cannot create the palette cache"
exec 9>"$cache_dir/wal/wallpaper.lock"
flock 9 || fail "Cannot lock the wallpaper pipeline"

# Children must not keep our lock alive (several renderers start daemons).
query=$(awww query 9>&-) || fail "Cannot read the current wallpaper"
primary_monitor=$(cat "$config_dir/options/mainmonitor" 2>/dev/null) || primary_monitor=""
wallpaper=""
if [ -n "$primary_monitor" ]; then
    while IFS= read -r line; do
        case "$line" in
            ": $primary_monitor:"*) wallpaper=${line#*image: }; break ;;
        esac
    done <<< "$query"
fi
if [ -z "$wallpaper" ]; then
    line=${query%%$'\n'*}
    wallpaper=${line#*image: }
fi
[ -f "$wallpaper" ] || fail "The selected wallpaper is unavailable"

# wal is synchronous. Do not publish new wallpaper state or reload consumers
# when generation failed; no fixed sleep can turn that failure into success.
# awww already owns the wallpaper. Keep pywal's diagnostics: -q suppresses
# even Python tracebacks, making a failed template impossible to identify.
if ! wal -n -i "$wallpaper" 9>&- > "$cache_dir/wal/generation.log" 2>&1; then
    cat "$cache_dir/wal/generation.log" >&2
    fail "Could not generate colors from $(basename "$wallpaper")"
fi
ln -sfn "$wallpaper" "$cache_dir/current_wallpaper" || fail "Cannot save the current wallpaper"
escaped=${wallpaper//\\/\\\\}
escaped=${escaped//\"/\\\"}
printf '* { wallpaper: url("%s", width); }\n' "$escaped" > "$cache_dir/wal/rofi-wallpaper.rasi" \
    || fail "Cannot save the launcher background"

failed=0
"$config_dir/scripts/theming/apply-wal.sh" 9>&- || failed=1

if [ -x "$config_dir/scripts/waybar/waybar.sh" ]; then
    "$config_dir/scripts/waybar/waybar.sh" 9>&- || failed=1
fi
# The settings panel reads the palette on demand; it has no resident consumer.

[ "$failed" -eq 0 ] || fail "Colors were generated, but some components failed to update. See the wallpaper command's stderr for details."
notify "Wallpaper Applied" "New color scheme generated from image: $(basename "$wallpaper")"
