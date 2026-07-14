#!/bin/bash
#
# Toggle waybar media module between "all players" and the preferred player
#

PLAYER_PATH="$HOME/.config/options/player"
CURRENT_PLAYER="$(cat "$PLAYER_PATH" 2>/dev/null || echo "all")"
DEFINED_PLAYER="$(cat "$HOME/.config/options/mediaplayer" 2>/dev/null)"

[ -z "$DEFINED_PLAYER" ] && exit 0

if [[ "$CURRENT_PLAYER" == "$DEFINED_PLAYER" ]]; then
    notify-send -i folder-music-symbolic "Media Mode Changed" "Media type is now set to 'All'"
    echo "all" > "$PLAYER_PATH"
else
    notify-send -i folder-music-symbolic "Media Mode Changed" "Media type is now set to '$DEFINED_PLAYER'"
    echo "$DEFINED_PLAYER" > "$PLAYER_PATH"
fi
