#!/bin/bash
#
# One Waybar workspace dot.
#
# The built-in hyprland/workspaces module knows occupancy, but its click path
# hard-codes the legacy positional workspace dispatcher that Hyprland's Lua
# config provider removed. ext/workspaces activates safely through Wayland but
# does not expose window counts. This small module keeps both properties.
#
# The dot itself is drawn by waybar/style.css, not by a glyph, so it can morph:
# the text is a single space and the state is the class.
#
#   active     the pill (current workspace)
#   occupied   filled (has windows)
#   empty      ring
#   absent     zero width (status-existing only: workspace does not exist)
#
# The text is never empty in dots mode because Waybar hides a custom module
# whose text is empty, and a hidden module cannot animate in or out.
#
# The Bar page's mode (options/bar-workspaces) swaps the dots for the workspace
# number; anything but `numbers` keeps the dots. A number cannot be hollow, so
# that mode adds a `numbers` class and style.css dims the empty ones instead;
# a missing optional workspace prints empty text there and hides at once,
# since a digit cannot shrink below its own width.
# A save reloads Waybar, which re-runs every instance, so the option is read on
# each status call rather than cached.
#
# Hyprland events signal Waybar for immediate updates; the module's interval is
# only a fallback. Workspaces 1-5 are always rendered with `status`; the
# optional 6-10 use `status-existing`.

set -uo pipefail

action="${1-}"
workspace="${2-}"

BAR_OPTIONS="${BAR_OPTIONS-}"
[ -n "$BAR_OPTIONS" ] || BAR_OPTIONS="$HOME/.config/options"

case "$action" in
    previous)
        hyprctl dispatch 'hl.dsp.focus({ workspace = "r-1" })'
        ;;
    next)
        hyprctl dispatch 'hl.dsp.focus({ workspace = "r+1" })'
        ;;
    switch)
        if ! [[ "$workspace" =~ ^[1-9][0-9]*$ ]]; then
            echo "workspace: expected a positive numeric workspace ID" >&2
            exit 2
        fi
        hyprctl dispatch "hl.dsp.focus({ workspace = $workspace })"
        ;;
    status|status-existing)
        if ! [[ "$workspace" =~ ^[1-9][0-9]*$ ]]; then
            echo "workspace: expected a positive numeric workspace ID" >&2
            exit 2
        fi
        workspaces=$(hyprctl workspaces -j 2>/dev/null) || workspaces='[]'
        exists=$(jq -r --argjson id "$workspace" \
            'any(.[]; .id == $id)' <<< "$workspaces" 2>/dev/null) || exists=false
        mode=''
        read -r mode 2>/dev/null < "$BAR_OPTIONS/bar-workspaces"

        if [ "$action" = "status-existing" ] && [ "$exists" != true ]; then
            if [ "$mode" = numbers ]; then
                printf '{"text":""}\n'
            else
                printf '{"text":" ","class":"absent"}\n'
            fi
            exit 0
        fi
        active=$(hyprctl activeworkspace -j 2>/dev/null \
            | jq -r '.id // 0' 2>/dev/null) || active=0
        windows=$(jq -r --argjson id "$workspace" \
            '[.[] | select(.id == $id) | .windows][0] // 0' \
            <<< "$workspaces" 2>/dev/null) || windows=0

        if [ "$active" = "$workspace" ]; then
            state=active
        elif [ "$windows" -gt 0 ] 2>/dev/null; then
            state=occupied
        else
            state=empty
        fi

        if [ "$mode" = numbers ]; then
            printf '{"text":"%s","class":["%s","numbers"]}\n' "$workspace" "$state"
        else
            printf '{"text":" ","class":"%s"}\n' "$state"
        fi
        ;;
    *)
        echo "usage: workspace.sh status|status-existing|switch WORKSPACE | previous | next" >&2
        exit 2
        ;;
esac
