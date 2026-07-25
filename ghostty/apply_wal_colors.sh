#!/bin/bash

# Render pywal colors for ghostty into the cache.
# ghostty/config pulls them in via: config-file = ?colors
# (ghostty/colors is a symlink to the rendered file)
wal_colors="$HOME/.cache/wal/colors-ghostty"

mkdir -p "$HOME/.cache/wal"

# The output must exist even before pywal has ever run: ghostty/colors is a
# tracked symlink to it, and a tracked symlink with no target is an ERROR in
# doctor.sh. ghostty's `?colors` include tolerates an empty file.
{
    echo "# Automatically generated from the pywal palette - do not edit manually"
    [[ -f "$wal_colors" ]] && tail -n +3 "$wal_colors"
} > "$HOME/.cache/wal/ghostty-colors"
