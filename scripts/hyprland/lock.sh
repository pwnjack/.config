#!/bin/bash
#
# Lock the session. The one lock path: Super+L, the power menu and hypridle's
# lock_cmd (so idle and before-sleep too, which go through loginctl
# lock-session) all run this.
#
# A recording is stopped and saved first: otherwise it would record the lock
# screen, and a suspend right after could leave the file without its index.
# record.sh stop does nothing when nothing records, and cancels a countdown.
# The stop is bounded (timeout 6; record.sh may wait up to stop_wait+2 s on a
# serialised stop) and its result ignored: a slow or failed save must never
# delay the lock, which is a security boundary.
# Arguments go to hyprlock (the live check uses --grace 30).
#
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
timeout 6 "$config_dir/scripts/capture/record.sh" stop >/dev/null 2>&1
pidof hyprlock >/dev/null || exec hyprlock "$@"
