#!/bin/bash
#
# SDDM Wallpaper Updater (user side)
# Delegates the privileged work to update_sddm_root.sh via sudo.
# Run setup-sudo.sh once to allow this to happen without a password
# (required for automatic updates from watch_wallpaper.sh).
#

root_script="$HOME/.config/sddm/update_sddm_root.sh"

if [[ ! -f "$root_script" ]]; then
    exit 1
fi

# Passwordless sudo (configured by setup-sudo.sh)
if sudo -n "$root_script" "$USER" 2>/dev/null; then
    if [[ -t 0 ]]; then
        echo "The SDDM wallpaper has been updated to your current wallpaper"
    fi
    exit 0
fi

# Interactive fallback: prompt for the sudo password
if [[ -t 0 ]]; then
    echo "Updating SDDM wallpaper (sudo password may be required)..."
    echo "Tip: run ~/.config/sddm/setup-sudo.sh once to make this automatic."
    if sudo "$root_script" "$USER"; then
        echo "The SDDM wallpaper has been updated to your current wallpaper"
        exit 0
    fi
    echo "Error: failed to update the SDDM wallpaper" >&2
    exit 1
fi

# Non-interactive without passwordless sudo: nothing we can do
exit 0
