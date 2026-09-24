#!/bin/bash
#
# Toggle the AI sidebar (Super+A): aichat in a ghostty window on the special
# workspace "aichat".
#
# Placement, float, opacity and workspace all come from the "ai-sidebar" window
# rule in hypr/config/software/rules.lua, which matches the class set here.
#
# ghostty is started from this script rather than through `hyprctl dispatch
# exec`, so it inherits the API keys loaded from .env below; an exec would run
# with Hyprland's environment instead.
#

class="aichat.sidebar"

if hyprctl clients -j | jq -e --arg class "$class" 'any(.[]; .class == $class)' >/dev/null; then
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("aichat")'
    exit 0
fi

if [ -f "$HOME/.config/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$HOME/.config/.env"
    set +a
fi

setsid -f ghostty --class="$class" --config-file="$HOME/.config/ghostty/ai-sidebar" \
    -e aichat -s assistant >/dev/null 2>&1
