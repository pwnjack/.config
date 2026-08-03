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
RUNUSER=/usr/bin/runuser

if [[ -z "$USER_HOME" ]]; then
    echo "Error: could not resolve home directory for user '$TARGET_USER'" >&2
    exit 1
fi

if [[ ! -x "$RUNUSER" ]]; then
    echo "Error: runuser is required to decode the SDDM wallpaper without root privileges" >&2
    exit 1
fi

# awww cache layout: ~/.cache/awww/<version>/<monitor>, line format: "<crop> <filter> <path>"
#
# This lookup is duplicated in scripts/hyprland/restore-wallpaper.sh and in
# sddm/watch_wallpaper.sh, deliberately. THIS script runs as root against
# another user's home, so sourcing a shared helper out of a user-writable
# $USER_HOME/.config/scripts/ would hand that user a root shell.
if ! wallpaper=$("$RUNUSER" -u "$TARGET_USER" -- /bin/bash -c '
    user_home=$1
    [[ -d "$user_home" ]] || exit 10

    # Empty preference means "no preference": use the newest entry for any
    # monitor instead of guessing a connector name.
    monitor=$(cat "$user_home/.config/options/mainmonitor" 2>/dev/null)
    if [[ -n "$monitor" ]]; then
        cache_file=$(ls -t "$user_home/.cache/awww/"*/"$monitor" 2>/dev/null | head -n1)
    else
        cache_file=$(ls -t "$user_home/.cache/awww/"*/* 2>/dev/null | head -n1)
    fi
    wallpaper=$(grep -oE '/.+$' "$cache_file" 2>/dev/null)

    # Fallback: the current-wallpaper symlink maintained by wall.sh.
    if [[ -z "$wallpaper" ]] || [[ ! -f "$wallpaper" ]]; then
        wallpaper=$(readlink -f "$user_home/.config/options/wallpaper" 2>/dev/null)
    fi
    [[ -n "$wallpaper" ]] && [[ -f "$wallpaper" ]] && printf "%s\n" "$wallpaper"
' _ "$USER_HOME"); then
    echo "Error: could not resolve home directory for user '$TARGET_USER'" >&2
    exit 1
fi

if [[ -z "$wallpaper" ]]; then
    exit 0
fi

if ! "$RUNUSER" -u "$TARGET_USER" -- \
     /bin/bash -c 'command -v ffmpeg >/dev/null'; then
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

temporary=""
cleanup_temporary() {
    if [[ -n "$temporary" ]]; then
        rm -f -- "$temporary"
        temporary=""
    fi
}

updated=false
for theme in "${themes_to_update[@]}"; do
    theme_dir="/usr/share/sddm/themes/$theme"
    resolved_theme_dir=$(readlink -f -- "$theme_dir" 2>/dev/null)
    [[ -n "$resolved_theme_dir" ]] && [[ -d "$resolved_theme_dir" ]] || continue
    if [[ "$(stat -c %u -- "$resolved_theme_dir" 2>/dev/null)" != "0" ]]; then
        echo "Error: refusing SDDM theme '$theme': resolved theme directory is not root-owned" >&2
        continue
    fi

    backgrounds_path="$resolved_theme_dir/Backgrounds"
    if [[ -e "$backgrounds_path" ]] || [[ -L "$backgrounds_path" ]]; then
        backgrounds_dir=$(readlink -f -- "$backgrounds_path" 2>/dev/null)
    else
        if ! mkdir -- "$backgrounds_path"; then
            echo "Error: could not create the Backgrounds directory for SDDM theme '$theme'" >&2
            continue
        fi
        backgrounds_dir=$(readlink -f -- "$backgrounds_path" 2>/dev/null)
    fi
    if [[ -z "$backgrounds_dir" ]] || [[ ! -d "$backgrounds_dir" ]] ||
       [[ "$(stat -c %u -- "$backgrounds_dir" 2>/dev/null)" != "0" ]]; then
        echo "Error: refusing SDDM theme '$theme': resolved Backgrounds directory is not root-owned" >&2
        continue
    fi

    destination="$backgrounds_dir/wallpaper.jpg"
    for stale_temporary in "$backgrounds_dir"/.wallpaper.jpg.*; do
        [[ -e "$stale_temporary" ]] || [[ -L "$stale_temporary" ]] || continue
        rm -f -- "$stale_temporary"
    done

    temporary=$(mktemp "$backgrounds_dir/.wallpaper.jpg.XXXXXX") || continue
    trap cleanup_temporary EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if "$RUNUSER" -u "$TARGET_USER" -- \
       ffmpeg -i "$wallpaper" -frames:v 1 -f mjpeg - > "$temporary" 2>/dev/null &&
       [[ -s "$temporary" ]] && chmod 0644 -- "$temporary"; then
        if mv -f -- "$temporary" "$destination"; then
            temporary=""
            updated=true
        fi
    fi
    cleanup_temporary
    trap - EXIT INT TERM
done

$updated || exit 1
exit 0
