#!/bin/bash

# Hiding Waybar in-process preserves its StatusNotifierWatcher and registered
# tray items. SIGUSR1 is Waybar's native visibility toggle.
if ! pkill -USR1 -x waybar 2>/dev/null; then
    waybar &
fi
