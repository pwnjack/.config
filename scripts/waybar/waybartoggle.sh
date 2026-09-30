#!/bin/bash

# Hiding Waybar in-process preserves its StatusNotifierWatcher and registered
# tray items. SIGUSR1 is Waybar's native visibility toggle.
# Starting one goes through waybar.sh, which renders its includes first.
if ! pkill -USR1 -x waybar 2>/dev/null; then
    bash "$(dirname -- "${BASH_SOURCE[0]}")/waybar.sh"
fi
