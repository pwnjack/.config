#!/bin/bash
#
# Pending updates for waybar -- repo and AUR, one count.
#
# There is no update notifier on this machine. The arch-update tray entry in
# ~/.config/autostart names a binary that is not installed, and Discover's
# notifier carries OnlyShowIn=KDE so it never starts under Hyprland. This
# module is the replacement, and it does not duplicate the updater: a click
# opens the update card (scripts/hyprland/updates-popover.sh), and the terminal
# path for AUR updates is scripts/updates/terminal.sh.
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
# UPDATES_REPO_CMD, UPDATES_AUR_CMD, UPDATES_AURHELPER, UPDATES_STATE_DIR,
# UPDATES_DB and UPDATES_LOCK_TIMEOUT are the test seam; test-updates.sh drives them the way test-battery.sh drives BATTERY_SYSFS.
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

# The Bar page's mode (options/bar-updates): pending, or hidden. Hidden
# returns before checkupdates, which syncs a pacman DB over the network.
BAR_OPTIONS="${BAR_OPTIONS-}"
[ -n "$BAR_OPTIONS" ] || BAR_OPTIONS="$HOME/.config/options"
mode=''
read -r mode 2>/dev/null < "$BAR_OPTIONS/bar-updates"
[ "$mode" = hidden ] && exit 0

# The update card's run state (scripts/updates/updates-run.sh writes it).
# While a run is active, show its progress and return BEFORE checkupdates.
# A finished run the card has not shown yet (ack != finishedAt) keeps a
# class so the result is not missed: restart replaces the module, attention
# marks the normal count.
STATE_DIR="${UPDATES_STATE_DIR-}"
[ -n "$STATE_DIR" ] || STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}/updates"
run_status='' run_progress=0 run_finished=0
if [ -r "$STATE_DIR/state.json" ]; then
    IFS=$'\t' read -r run_status run_progress run_finished < <(
        jq -r '[.status // "", (.progress // 0), (.finishedAt // 0)] | @tsv' "$STATE_DIR/state.json" 2>/dev/null)
fi
# Liveness comes from run.lock, not from state.json: the runner deletes the
# state right after taking the lock and the first snapshot follows a moment
# later, and after a SIGKILL the file still says running with the lock free.
# So a held lock means running (0% until a snapshot exists), and a "running"
# file with a free lock is stale.
# The probe reads /proc/locks (as quickshell/updates/shell.qml does) instead of
# trying the lock: a momentary flock -n here could make a starting runner find
# the lock taken and exit as busy.
lock_held() {
    local f=$1 maj min ino
    [ -e "$f" ] || return 1
    read -r maj min ino < <(stat -L -c '%Hd %Ld %i' -- "$f") || return 1
    grep -q " $(printf '%02x:%02x:%s' "$maj" "$min" "$ino") " /proc/locks 2>/dev/null
}
if lock_held "$STATE_DIR/run.lock"; then
    run_status=running
elif [ "$run_status" = running ]; then
    run_status=''
fi
run_seen=false
[ "$(cat "$STATE_DIR/ack" 2>/dev/null)" = "$run_finished" ] && run_seen=true

# Nerd Font Material circle-slice-1..8, one per eighth of the run.
SLICES=($'\U000f0a9e' $'\U000f0a9f' $'\U000f0aa0' $'\U000f0aa1'
        $'\U000f0aa2' $'\U000f0aa3' $'\U000f0aa4' $'\U000f0aa5')
RESTART_ICON=$'\U000f0709'   # restart

if [ "$run_status" = running ]; then
    pct=$(awk -v p="$run_progress" 'BEGIN { v = int(p * 100); if (v < 0) v = 0; if (v > 99) v = 99; print v }')
    slice=${SLICES[$(( pct * 8 / 100 ))]}
    jq -nc --arg text "<span size=\"large\">$slice</span> $pct%" --arg tooltip "Updating · $pct%" \
        '{text: $text, tooltip: $tooltip, class: "running"}'
    exit 0
fi
if [ "$run_status" = restart ] && ! $run_seen; then
    jq -nc --arg text "<span size=\"large\">$RESTART_ICON</span>" \
        '{text: $text, tooltip: "Restart to finish the update", class: "restart"}'
    exit 0
fi
class=""
case "$run_status" in attention | failed) $run_seen || class=attention ;; esac

# checkupdates shares one private sync DB with scripts/updates/updates-plan.sh;
# concurrent runs race on db.lck and one silently returns nothing, so both take
# the same flock.
DB="${UPDATES_DB:-${TMPDIR:-/tmp}/checkup-db-${UID}}"
LOCK="$DB.lock"
LOCK_TIMEOUT="${UPDATES_LOCK_TIMEOUT:-120}"

# count <command> [args...] — lines of output, exit status ignored on purpose.
count() {
    local out
    out=$("$@" 2>/dev/null)
    [ -n "$out" ] || { printf '0'; return; }
    printf '%s' "$out" | grep -c ''
}

# repo count
if command -v "$REPO_CMD" >/dev/null 2>&1; then
    repo=$(CHECKUPDATES_DB="$DB" count flock -w "$LOCK_TIMEOUT" "$LOCK" "$REPO_CMD")
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
if [ "$total" -eq 0 ]; then
    # An unseen failed run stays visible even with nothing pending (pacman
    # fine, Flatpak failed): the alert class is the only trace of it.
    if [ -n "$class" ]; then
        jq -nc --arg text "<span size=\"large\">$ICON</span>" \
            '{text: $text, tooltip: "The last update needs attention", class: "attention"}'
    fi
    exit 0
fi

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

# The gap between glyph and count is set HERE, not in style.css: a waybar
# module is a single Pango label, so the stylesheet owns the gaps BETWEEN
# modules and the format string owns the one INSIDE.
#
# One plain space, and deliberately NOT the telemetry modules'
# letter_spacing='4096' + space. That attribute is what CREATES their gap
# rather than tightening it, so copying it verbatim moved the count further
# out. This glyph is a circular arrow with little ink on its right edge, where
# the cpu/disk glyphs are dense square blocks, so an equal metric gap reads
# wider here -- the same effect battery.sh documents in reverse when it takes
# two spaces to look equal.
text="<span size=\"large\">$ICON</span> $total"

# Both fields are ours -- a glyph and digits, no package names, no vendor
# strings -- so unlike battery.sh's tooltip there is no arbitrary text to
# escape for Pango here.
jq -nc --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" \
    '{text: $text, tooltip: $tooltip} + (if $class == "" then {} else {class: $class} end)'
