#!/bin/bash
#
# Render the pywal palette as a ghostty color include.
#
# ghostty/config pulls it in with `config-file = ?colors` (the AI sidebar
# inherits it, since ghostty loads that file first), and ghostty/colors is a
# tracked symlink to the file written here. Rendering from the shared loader keeps it complete on a fresh
# checkout, before pywal has ever run.
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
    echo "# Automatically generated from the pywal palette - do not edit manually"
    echo
    echo "background = ${wal[0]}"
    echo "foreground = ${wal[7]}"
    echo "cursor-color = ${wal[7]}"
    echo
    for i in "${!wal[@]}"; do
        echo "palette = $i=${wal[$i]}"
    done
} > "$cache_dir/ghostty-colors"
