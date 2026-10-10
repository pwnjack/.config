#!/bin/bash
#
# Render the pywal palette as GTK CSS color definitions.
#
# waybar/style.css and swaync/style.css both import the file written here. pywal also writes it from its built-in
# template; rendering it here as well keeps it existing on a fresh checkout
# where pywal has never run. The content matches pywal's own.
#
# Waybar restyles itself when this file changes (reload_style_on_change in
# waybar/config.jsonc); no reload is sent, because a full one rebuilds the bar
# and briefly resizes every tiled window.
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
