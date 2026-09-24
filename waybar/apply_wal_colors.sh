#!/bin/bash
#
# Render the pywal palette as GTK CSS color definitions.
#
# waybar/colors.css is a tracked symlink to the file written here, and
# swaync/style.css imports the same file. pywal also writes it from its built-in
# template; rendering it here as well keeps it existing on a fresh checkout
# where pywal has never run. The content matches pywal's own.
#
# Waybar itself is reloaded by wall.sh (scripts/waybar/waybar.sh).
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"

declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
. "$config_dir/scripts/theming/palette.sh"
wal_load

mkdir -p "$cache_dir"

{
    echo "@define-color foreground ${wal[7]};"
    echo "@define-color background ${wal[0]};"
    echo "@define-color cursor ${wal[7]};"
    echo
    for i in "${!wal[@]}"; do
        echo "@define-color color$i ${wal[$i]};"
    done
} > "$cache_dir/colors-waybar.css"
