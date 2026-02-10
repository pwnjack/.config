#!/bin/bash
#
# SwayNC Pywal Color Integration
# Reloads SwayNC styles after pywal regenerates colors
#
# SwayNC's style.css imports ~/.cache/wal/colors-waybar.css directly,
# so we just need to trigger a style reload after pywal updates that file.
#

# Reload SwayNC styles to pick up new pywal colors
if pgrep -x swaync > /dev/null; then
    swaync-client -rs
fi
