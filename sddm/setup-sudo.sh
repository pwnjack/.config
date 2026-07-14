#!/bin/bash
#
# SDDM Wallpaper Sudo Setup
# Grants passwordless sudo for update_sddm_root.sh only, so the wallpaper
# watcher can sync the SDDM background automatically in the background.
#
# Note: this trusts ~/.config/sddm/update_sddm_root.sh to run as root.
# Anything that can write to that file gains root access, so keep your
# home directory permissions sane.
#

SUDOERS_FILE="/etc/sudoers.d/sddm-wallpaper"
ROOT_SCRIPT="$HOME/.config/sddm/update_sddm_root.sh"

echo "Setting up passwordless sudo for SDDM wallpaper updates..."
echo ""

if [[ ! -f "$ROOT_SCRIPT" ]]; then
    echo "✗ $ROOT_SCRIPT not found"
    exit 1
fi

if [[ -f "$SUDOERS_FILE" ]] && sudo -n "$ROOT_SCRIPT" "$USER" 2>/dev/null; then
    echo "Passwordless sudo is already configured!"
    exit 0
fi

# Build the sudoers rule for the current user
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT
printf '%s ALL=(root) NOPASSWD: %s\n' "$USER" "$ROOT_SCRIPT" > "$tmpfile"

# Verify syntax before installing
if ! sudo visudo -c -f "$tmpfile" >/dev/null; then
    echo "✗ Generated sudoers rule failed validation"
    exit 1
fi

if sudo install -m 0440 -o root -g root "$tmpfile" "$SUDOERS_FILE"; then
    echo "✓ Installed $SUDOERS_FILE"
else
    echo "✗ Failed to install sudoers file"
    exit 1
fi

# Test it
if sudo -n "$ROOT_SCRIPT" "$USER" 2>/dev/null; then
    echo "✓ Passwordless sudo is now working!"
    echo ""
    echo "The SDDM wallpaper has been updated to your current wallpaper."
else
    echo "⚠ Passwordless sudo may not be working yet. Try running:"
    echo "  sudo $ROOT_SCRIPT $USER"
fi
