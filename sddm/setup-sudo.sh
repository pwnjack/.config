#!/bin/bash

echo "Setting up passwordless sudo for SDDM wallpaper updates..."
echo ""

# Check if already configured
if sudo -n true 2>/dev/null; then
    echo "Passwordless sudo is already configured!"
    exit 0
fi

# Copy sudoers file
if sudo cp /home/pwnjack/.config/sddm/sddm-wallpaper-sudoers /etc/sudoers.d/sddm-wallpaper; then
    echo "✓ Copied sudoers file"
else
    echo "✗ Failed to copy sudoers file"
    exit 1
fi

# Verify syntax
if sudo visudo -c -f /etc/sudoers.d/sddm-wallpaper; then
    echo "✓ Sudoers syntax is valid"
else
    echo "✗ Sudoers syntax error! Removing file..."
    sudo rm -f /etc/sudoers.d/sddm-wallpaper
    exit 1
fi

# Test passwordless sudo
if sudo -n true 2>/dev/null; then
    echo "✓ Passwordless sudo is now working!"
    echo ""
    echo "Testing wallpaper update..."
    /home/pwnjack/.config/sddm/update_sddm.sh
else
    echo "⚠ Passwordless sudo may not be working yet. Try running the update script manually."
fi

