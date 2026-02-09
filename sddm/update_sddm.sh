#!/bin/bash

monitor=$(cat "$HOME/.config/options/mainmonitor" 2>/dev/null || echo "eDP-1")
cache_file="$HOME/.cache/swww/$monitor"
wallpaper=$(grep -v "^Lanczos3" "$cache_file" 2>/dev/null)

# If cache file doesn't have wallpaper, try querying swww directly
if [[ -z "$wallpaper" ]] || [[ ! -f "$wallpaper" ]]; then
    if command -v swww &>/dev/null; then
        wallpaper=$(swww query 2>/dev/null | grep "^: $monitor:" | sed 's/.*image: //' | head -n1)
    fi
fi

# Check if wallpaper file exists
if [[ -z "$wallpaper" ]] || [[ ! -f "$wallpaper" ]]; then
    exit 0
fi

genwal="$wallpaper"

# Check if running interactively (TTY attached)
if [[ -t 0 ]]; then
    echo "Updating SDDM wallpaper... "
fi

# Check if ffmpeg is installed
if ! command -v ffmpeg &>/dev/null; then
    if [[ -t 0 ]]; then
        echo "Warning: ffmpeg is not installed. Please install it manually."
    fi
    exit 1
fi

# Function to run command with sudo, checking if passwordless sudo is available
run_sudo() {
    if sudo -n true 2>/dev/null; then
        # Passwordless sudo is available
        sudo "$@"
    else
        # Try with password prompt (only works in interactive mode)
        if [[ -t 0 ]]; then
            sudo "$@"
        else
            # Non-interactive mode and no passwordless sudo
            if [[ -t 0 ]]; then
                echo "Error: Passwordless sudo is required for non-interactive execution."
                echo "Please configure passwordless sudo or run this script manually."
            fi
            return 1
        fi
    fi
}

# Determine which SDDM theme is actually being used
# Check system config first, then local config
current_theme=""
if [[ -f /etc/sddm.conf ]]; then
    current_theme=$(grep -A2 "\[Theme\]" /etc/sddm.conf 2>/dev/null | grep "^Current=" | cut -d'=' -f2 | tr -d ' ')
fi
if [[ -z "$current_theme" ]] && [[ -f "$HOME/.config/sddm/default.conf" ]]; then
    current_theme=$(grep -A2 "\[Theme\]" "$HOME/.config/sddm/default.conf" 2>/dev/null | grep "^Current=" | cut -d'=' -f2 | tr -d ' ')
fi

# Fallback to sddm-astronaut-theme if we can't determine
if [[ -z "$current_theme" ]]; then
    current_theme="sddm-astronaut-theme"
fi

# Find all themes that have Backgrounds directories or need them created
themes_to_update=()
if [[ -d "/usr/share/sddm/themes/$current_theme" ]]; then
    themes_to_update+=("$current_theme")
fi
# Also update sddm-astronaut-theme if it exists and is different
if [[ -d "/usr/share/sddm/themes/sddm-astronaut-theme" ]] && [[ "$current_theme" != "sddm-astronaut-theme" ]]; then
    themes_to_update+=("sddm-astronaut-theme")
fi

# If no themes found, try to create Backgrounds directory for current theme
if [[ ${#themes_to_update[@]} -eq 0 ]] && [[ -d "/usr/share/sddm/themes/$current_theme" ]]; then
    themes_to_update+=("$current_theme")
fi

# Convert wallpaper to JPG format for SDDM themes
success=false
for theme in "${themes_to_update[@]}"; do
    theme_dir="/usr/share/sddm/themes/$theme/Backgrounds"
    
    # Check if we can write to the directory without sudo
    needs_sudo=true
    if [[ -d "$theme_dir" ]] && [[ -w "$theme_dir" ]]; then
        # Check if wallpaper file exists and if we can write to it
        if [[ ! -f "$theme_dir/wallpaper.jpg" ]] || [[ -w "$theme_dir/wallpaper.jpg" ]] || [[ -w "$theme_dir" ]]; then
            needs_sudo=false
        fi
    fi
    
    # Create Backgrounds directory if it doesn't exist
    if [[ ! -d "$theme_dir" ]]; then
        if [[ -w "$(dirname "$theme_dir")" ]]; then
            mkdir -p "$theme_dir" 2>/dev/null && needs_sudo=false
        fi
        if [[ ! -d "$theme_dir" ]] && ! run_sudo mkdir -p "$theme_dir"; then
            if [[ -t 0 ]]; then
                echo "Warning: Failed to create $theme_dir (may need passwordless sudo)"
            fi
            continue
        fi
    fi
    
    # Remove old wallpaper
    if [[ "$needs_sudo" == "true" ]]; then
        run_sudo rm -f "$theme_dir/wallpaper.jpg"
    else
        rm -f "$theme_dir/wallpaper.jpg"
    fi
    
    # Use ffmpeg to convert (suppress output when run in background)
    if [[ "$needs_sudo" == "true" ]]; then
        if run_sudo ffmpeg -i "$genwal" -y "$theme_dir/wallpaper.jpg" >/dev/null 2>&1; then
            success=true
            if [[ -t 0 ]]; then
                echo "Updated wallpaper for theme: $theme (using sudo)"
            fi
        else
            if [[ -t 0 ]]; then
                echo "Warning: Failed to update $theme wallpaper (may need passwordless sudo)"
            fi
        fi
    else
        # Try without sudo first
        if ffmpeg -i "$genwal" -y "$theme_dir/wallpaper.jpg" >/dev/null 2>&1; then
            success=true
            if [[ -t 0 ]]; then
                echo "Updated wallpaper for theme: $theme (no sudo needed)"
            fi
        else
            # Fallback to sudo if direct write fails
            if run_sudo ffmpeg -i "$genwal" -y "$theme_dir/wallpaper.jpg" >/dev/null 2>&1; then
                success=true
                if [[ -t 0 ]]; then
                    echo "Updated wallpaper for theme: $theme (using sudo)"
                fi
            else
                if [[ -t 0 ]]; then
                    echo "Warning: Failed to update $theme wallpaper"
                fi
            fi
        fi
    fi
done

if [[ "$success" == "false" ]]; then
    if [[ -t 0 ]]; then
        echo "Error: Failed to update any SDDM theme wallpaper"
        echo "Please configure passwordless sudo: sudo cp $HOME/.config/sddm/sddm-wallpaper-sudoers /etc/sudoers.d/sddm-wallpaper"
    fi
    exit 1
fi

if [[ -t 0 ]]; then
    clear
    echo "The SDDM wallpaper has been updated to your current wallpaper"
fi
