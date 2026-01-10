#!/bin/bash
#
# Media Player Status Display
# Shows currently playing media with playerctl integration
#

# Read configuration
CURRENT_PLAYER=$(cat "$HOME/.config/options/player" 2>/dev/null || echo "all")
USER_ICON=$(cat "$HOME/.config/options/mediaicon" 2>/dev/null || echo "󰝚")

if [[ "$CURRENT_PLAYER" == "all" ]]; then
    PLAYER_ARG=()
    ICON="󰝚"
        MESSAGE=""
else
    PLAYER_ARG=(--player="$CURRENT_PLAYER")
    ICON="${USER_ICON}"
    MESSAGE="Player '$CURRENT_PLAYER' isn't open"
fi

truncate() {
    local input="$1"
    local maxlen=38 # feel free to change this
    if (( ${#input} > maxlen )); then
        echo "${input:0:maxlen}…"
    else
        echo "$input"
    fi
}

currentsong=$(playerctl "${PLAYER_ARG[@]}" metadata --format "$ICON  {{title}}" 2>/dev/null)
currentsong=$(truncate "$currentsong")

if [[ -z "$currentsong" ]]; then
    currentsong="$MESSAGE"
fi

echo "$currentsong"
