#!/bin/bash
#
# SDDM Wallpaper Updater (root side)
# Runs as root via sudo (see setup-sudo.sh) or a systemd service.
# Converts the user's current wallpaper into the SDDM theme background.
#
# Usage: update_sddm_root.sh [username]
#   The user defaults to $SUDO_USER, then the first regular user (uid 1000).
#

TARGET_USER="${1:-${SUDO_USER:-$(id -un 1000 2>/dev/null)}}"
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

if [[ -z "$USER_HOME" ]] || [[ ! -d "$USER_HOME" ]]; then
    echo "Error: could not resolve home directory for user '$TARGET_USER'" >&2
    exit 1
fi

# Empty preference means "no preference": the newest cache entry for ANY
# monitor is taken. No connector name is guessed.
monitor=$(cat "$USER_HOME/.config/options/mainmonitor" 2>/dev/null)

# awww cache layout: ~/.cache/awww/<version>/<monitor>, line format: "<crop> <filter> <path>"
#
# This lookup is duplicated in scripts/hyprland/restore-wallpaper.sh and in
# sddm/watch_wallpaper.sh, deliberately. THIS script runs as root against
# another user's home, so sourcing a shared helper out of a user-writable
# $USER_HOME/.config/scripts/ would hand that user a root shell.
if [ -n "$monitor" ]; then
    cache_file=$(ls -t "$USER_HOME/.cache/awww/"*/"$monitor" 2>/dev/null | head -n1)
else
    cache_file=$(ls -t "$USER_HOME/.cache/awww/"*/* 2>/dev/null | head -n1)
fi
wallpaper=$(grep -oE '/.+$' "$cache_file" 2>/dev/null)

# Fallback: the current-wallpaper symlink maintained by wall.sh
if [[ -z "$wallpaper" ]] || [[ ! -f "$wallpaper" ]]; then
    wallpaper=$(readlink -f "$USER_HOME/.config/options/wallpaper" 2>/dev/null)
fi

if [[ -z "$wallpaper" ]] || [[ ! -f "$wallpaper" ]]; then
    exit 0
fi

if ! command -v ffmpeg &>/dev/null; then
    echo "Error: ffmpeg is required but not installed" >&2
    exit 1
fi

# Determine which SDDM theme is in use (default: sddm-astronaut-theme)
current_theme=""
if [[ -f /etc/sddm.conf ]]; then
    current_theme=$(grep -A2 "\[Theme\]" /etc/sddm.conf 2>/dev/null | grep "^Current=" | cut -d'=' -f2 | tr -d ' ')
fi
[[ -z "$current_theme" ]] && current_theme="sddm-astronaut-theme"

themes_to_update=("$current_theme")
[[ "$current_theme" != "sddm-astronaut-theme" ]] && themes_to_update+=("sddm-astronaut-theme")

updated=false
for theme in "${themes_to_update[@]}"; do
    theme_dir="/usr/share/sddm/themes/$theme"
    [[ -d "$theme_dir" ]] || continue
    mkdir -p "$theme_dir/Backgrounds"
    if ffmpeg -i "$wallpaper" -y "$theme_dir/Backgrounds/wallpaper.jpg" >/dev/null 2>&1; then
        updated=true
    fi
done

$updated || exit 1
exit 0
