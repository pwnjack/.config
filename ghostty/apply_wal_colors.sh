#!/bin/bash

# Apply pywal colors to ghostty terminal
ghostty_config="$HOME/.config/ghostty/config"
wal_colors="$HOME/.cache/wal/colors-ghostty"

if [[ ! -f "$wal_colors" ]]; then
    exit 0
fi

# Remove old pywal-generated colors from config (lines between "# pywal colors start" and "# pywal colors end")
if grep -q "# pywal colors start" "$ghostty_config" 2>/dev/null; then
    sed -i '/# pywal colors start/,/# pywal colors end/d' "$ghostty_config"
fi

# Append new colors to config
{
    echo "# pywal colors start"
    echo "# Automatically generated - do not edit manually"
    # Skip the header comments from pywal's generated file (first 2 lines)
    tail -n +3 "$wal_colors"
    echo "# pywal colors end"
} >> "$ghostty_config"

# Reload ghostty configuration for all running instances
# Ghostty supports reloading via signal or config file change
# New windows will automatically use the new colors

