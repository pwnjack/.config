#!/bin/bash
#
# One Waybar workspace dot.
#
# The built-in hyprland/workspaces module knows occupancy, but its click path
# hard-codes the legacy positional workspace dispatcher that Hyprland's Lua
# config provider removed. ext/workspaces activates safely through Wayland but
# does not expose window counts. This small module keeps both properties:
#
#   active or occupied  ●
#   genuinely empty     ○
#
# Hyprland events signal Waybar for immediate updates; the module's interval is
# only a fallback. Workspaces 1-5 are always rendered, while `status-existing`
# lets the optional 6-10 modules disappear until their workspace exists.

set -uo pipefail

action="${1-}"
workspace="${2-}"

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
        if [ "$action" = "status-existing" ] && [ "$exists" != true ]; then
            printf '{"text":""}\n'
            exit 0
        fi
        active=$(hyprctl activeworkspace -j 2>/dev/null \
            | jq -r '.id // 0' 2>/dev/null) || active=0
        windows=$(jq -r --argjson id "$workspace" \
            '[.[] | select(.id == $id) | .windows][0] // 0' \
            <<< "$workspaces" 2>/dev/null) || windows=0

        if [ "$active" = "$workspace" ]; then
            printf '{"text":"●","class":"active"}\n'
        elif [ "$windows" -gt 0 ] 2>/dev/null; then
            printf '{"text":"●","class":"occupied"}\n'
        else
            printf '{"text":"○","class":"empty"}\n'
        fi
        ;;
    *)
        echo "usage: workspace.sh status|status-existing|switch WORKSPACE | previous | next" >&2
        exit 2
        ;;
esac
