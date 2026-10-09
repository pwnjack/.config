#!/bin/bash
#
# Lock the session. The one lock path: Super+L, the power menu and hypridle's
# lock_cmd (so idle and before-sleep too, which go through loginctl
# lock-session) all run this.
#
# The lock comes first and the save second. Locking is the security boundary,
# and on suspend logind waits only InhibitDelayMaxSec (5 s) for the lock before
# sleeping anyway, so nothing may stand in front of hyprlock. A running
# recording is saved by a detached record.sh stop started just before hyprlock
# is exec'd: it runs its own escalation and toasts to completion, and if it is
# missing or fails the lock still happens. The clip may therefore end with about
# a second of the lock screen. record.sh stop does nothing when nothing
# records, and cancels a countdown.
#
# Never a second hyprlock: a flock on a descriptor the exec'd hyprlock inherits
# is held exactly while it runs, and a hyprlock of this user already running
# counts as locked. That includes a stale one that no longer holds the session
# lock; this script does not look further than the process.
# Arguments go to hyprlock (the live check uses --grace 30).
#
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/lock.sh.lock"
flock -n 9 || exit 0
pgrep -xu "$(id -u)" hyprlock >/dev/null && exit 0
setsid -f "$config_dir/scripts/capture/record.sh" stop </dev/null >/dev/null 2>&1 9>&-
exec hyprlock "$@"
