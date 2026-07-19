#!/bin/bash

# Render pywal colors for ghostty into the cache.
# ghostty/config pulls them in via: config-file = ?colors
# (ghostty/colors is a symlink to the rendered file)
wal_colors="$HOME/.cache/wal/colors-ghostty"

if [[ ! -f "$wal_colors" ]]; then
    exit 0
fi

mkdir -p "$HOME/.cache/wal"
{
    echo "# Automatically generated from the pywal palette - do not edit manually"
    tail -n +3 "$wal_colors"
} > "$HOME/.cache/wal/ghostty-colors"
