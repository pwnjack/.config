#!/bin/bash
#
# Pending updates for waybar -- repo and AUR, one count.
#
# There is no update notifier on this machine. The arch-update tray entry in
# ~/.config/autostart names a binary that is not installed, and Discover's
# notifier carries OnlyShowIn=KDE so it never starts under Hyprland. This
# module is the replacement, and it does not duplicate the updater:
# scripts/settings/update.sh already exists and is what the click opens.
#
# THE EXIT-STATUS TRAP. Both count commands use exit status to mean "nothing
# found", with different codes:
#
#   checkupdates   exit 2   no updates          (exit 0 with updates)
#   paru -Qua      exit 1   no AUR updates
#
# So this script must ignore exit status entirely and count lines. Any `&&`
# chain, any `set -e`, any `if cmd; then count; fi` reports zero forever and
# looks perfectly healthy doing it -- the failure mode is silence, which is
# why test-updates.sh pins all four combinations of status and output.
#
# The AUR helper is DERIVED from options/aurhelper (first word of e.g.
# "paru -Syu"), never hardcoded. A hardcoded name would be a second source of
# truth beside the file the settings panel and update.sh already read.
#
# UPDATES_REPO_CMD, UPDATES_AUR_CMD and UPDATES_AURHELPER are the test seam;
# test-updates.sh drives them the way test-battery.sh drives BATTERY_SYSFS.
#

REPO_CMD="${UPDATES_REPO_CMD:-checkupdates}"

# Written as two statements rather than as one :- default holding the path, on
# purpose. doctor.sh's literal-reference pattern allows braces inside a path, so
# the brace closing such a default is captured as part of the filename and the
# check then reports a path that does not exist. The brace-free form says the
# same thing and keeps ./doctor.sh at zero warnings.
AURHELPER_FILE="${UPDATES_AURHELPER-}"
[ -n "$AURHELPER_FILE" ] || AURHELPER_FILE="$HOME/.config/options/aurhelper"

ICON=$'\U000f06b0'   # Nerd Font, Material Design: update (󰚰)

# `update` verb: open the updater that already exists, then refresh the module
# the moment it exits instead of waiting out the 30-minute interval. Signal 9
# is this module's; custom/nightlight uses 8 for the same purpose.
#
# The signal is raised from INSIDE the launched command, not after the
# launcher returns. Measured: `ghostty -e sleep 4` does block for 4s, so
# signalling outside would work for the terminal configured today -- but
# options/terminal is a user preference, and a single-instance or client-style
# terminal returns the moment it hands the window off, which would fire the
# refresh before the update had even started and then leave a stale count
# until the next interval. Tying it to update.sh's own exit removes the
# dependency on how the terminal behaves.
if [ "${1-}" = "update" ]; then
    term=$(cat "$HOME/.config/options/terminal" 2>/dev/null)
    [ -n "$term" ] || term=ghostty
    # shellcheck disable=SC2016  # $0 must expand in the INNER bash, not here
    "$term" -e bash -c '"$0"; pkill -RTMIN+9 waybar' \
        "$HOME/.config/scripts/settings/update.sh"
    exit 0
fi

# count <command> [args...] — lines of output, exit status ignored on purpose.
count() {
    local out
    out=$("$@" 2>/dev/null)
    [ -n "$out" ] || { printf '0'; return; }
    printf '%s' "$out" | grep -c ''
}

# repo count
if command -v "$REPO_CMD" >/dev/null 2>&1; then
    repo=$(count "$REPO_CMD")
else
    repo=0
fi

# AUR count. UPDATES_AUR_CMD overrides the derivation for the tests; otherwise
# take the first word of options/aurhelper, which holds a full command line.
aur_cmd="${UPDATES_AUR_CMD-}"
if [ -z "${UPDATES_AUR_CMD+set}" ]; then
    aur_cmd=$(awk 'NR==1 {print $1}' "$AURHELPER_FILE" 2>/dev/null)
fi

aur=""
if [ -n "$aur_cmd" ] && command -v "$aur_cmd" >/dev/null 2>&1; then
    aur=$(count "$aur_cmd" -Qua)
fi

total=$((repo + ${aur:-0}))

# Nothing pending: print nothing and let waybar hide the module -- the idiom
# battery.sh and custom/media already use. The module APPEARING is the signal,
# which is what keeps this stateless with nothing to remember or expire.
[ "$total" -gt 0 ] || exit 0

# Only non-zero sides are named. "0 repo · 1 AUR" reads as a fault report
# rather than a count, and the zero carries nothing the total does not.
# `total > 0` above guarantees at least one side survives, so this is never
# empty.
tooltip=""
[ "$repo" -gt 0 ] && tooltip="$repo repo"
if [ -n "$aur" ] && [ "$aur" -gt 0 ]; then
    [ -n "$tooltip" ] && tooltip+=" · "
    tooltip+="$aur AUR"
fi

text="<span size=\"large\">$ICON</span>  $total"

# Both fields are ours -- a glyph and digits, no package names, no vendor
# strings -- so unlike battery.sh's tooltip there is no arbitrary text to
# escape for Pango here.
jq -nc --arg text "$text" --arg tooltip "$tooltip" \
    '{text: $text, tooltip: $tooltip}'
