#!/usr/bin/env bash
#
# Clipboard History
# Pick an entry to copy it again, or clear the whole history.
#
# cliphist lines always start with a numeric id and a tab, so the clear entry
# can never collide with one.
#

# Nerd Font glyphs, escaped so no editor can silently drop them.
clear=$'\uf1f8'"  Clear history"
yes=$'\uf058'" Yes"
no=$'\uf52f'" No"

chosen=$({ cliphist list; printf '%s\n' "$clear"; } | rofi -dmenu -no-custom -p "Clipboard")
[ -n "$chosen" ] || exit 0

if [ "$chosen" = "$clear" ]; then
    answer=$(printf '%s\n' "$no" "$yes" | rofi -dmenu -no-custom -p "Clear clipboard history?")
    if [ "$answer" = "$yes" ] && ! cliphist wipe; then
        command -v notify-send >/dev/null 2>&1 && \
            notify-send "Clipboard history" "Failed to clear clipboard history"
    fi
    exit 0
fi

printf '%s\n' "$chosen" | cliphist decode | wl-copy
