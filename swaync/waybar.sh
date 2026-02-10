#!/bin/bash
#
# SwayNC Waybar integration
# Subscribes to swaync and outputs JSON for waybar,
# hiding the count text when there are 0 notifications
#

swaync-client -swb | while IFS= read -r line; do
    count=$(echo "$line" | sed 's/.*"text"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    if [ "$count" = "0" ]; then
        echo "$line" | sed 's/"text"[[:space:]]*:[[:space:]]*"[^"]*"/"text":""/'
    else
        echo "$line"
    fi
done
