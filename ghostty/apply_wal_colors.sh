#!/bin/bash

# Apply pywal colors to ghostty terminal
ghostty_config="$HOME/.config/ghostty/config"
wal_colors="$HOME/.cache/wal/colors-ghostty"

if [[ ! -f "$wal_colors" ]]; then
    exit 0
fi

# Build the complete new config atomically to avoid race conditions
# where ghostty reads a partial config (no colors) between sed and append
tmp_config=$(mktemp)

# Get everything before the pywal block (or entire file if no block exists)
if grep -q "# pywal colors start" "$ghostty_config" 2>/dev/null; then
    sed '/# pywal colors start/,/# pywal colors end/d' "$ghostty_config" > "$tmp_config"
else
    cp "$ghostty_config" "$tmp_config"
fi

# Append new colors
{
    echo "# pywal colors start"
    echo "# Automatically generated - do not edit manually"
    tail -n +3 "$wal_colors"
    echo "# pywal colors end"
} >> "$tmp_config"

# Atomic replace - single rename operation
mv "$tmp_config" "$ghostty_config"

