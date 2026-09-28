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

if [ -n "${CLIPBOARD_PRINT_CLEAR:-}" ]; then
    printf '%s\n%s\n%s\n' "$clear" "$yes" "$no"
    exit 0
fi

chosen=$({ printf '%s\n' "$clear"; cliphist list; } | rofi -dmenu -p "Clipboard")
[ -n "$chosen" ] || exit 0

if [ "$chosen" = "$clear" ]; then
    answer=$(printf '%s\n' "$yes" "$no" | rofi -dmenu -p "Clear clipboard history?")
    [ "$answer" = "$yes" ] && cliphist wipe
    exit 0
fi

printf '%s\n' "$chosen" | cliphist decode | wl-copy
