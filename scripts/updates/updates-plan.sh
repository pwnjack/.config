#!/bin/bash
#
# The update card's plan: pending repo and AUR updates, how much needs
# downloading, and whether the running kernel is replaced. No root.
#
# checkupdates syncs a private copy of the sync DBs; `pacman -Sup --dbpath`
# against that copy then lists every package the upgrade would fetch,
# including new dependencies (measured: works unprivileged). A package whose
# file is already in the cache downloads nothing and counts as 0.
#
# Exit status: checkupdates is accepted only as 0 (updates) or 2 (none); any
# other status, a missing checkupdates, a lock timeout, or a failing
# `pacman -Sup` prints one reason line on stderr and exits 1 with no JSON, so
# the card shows an error instead of a false "Up to date". (scripts/waybar/
# updates.sh keeps its own rule of ignoring the status.) The AUR helper's
# status stays ignored: `paru -Qua` exits unreliably, and the AUR list is
# derived from options/aurhelper the same way updates.sh derives it.
#
# checkupdates runs under `flock -w` on "$DB.lock" (LOCK below), because the
# private sync DB is shared. scripts/waybar/updates.sh must take the same lock
# around its own checkupdates call (Task 5).
#
# Test seams: UPDATES_REPO_CMD, UPDATES_AURHELPER, UPDATES_AUR_CMD,
# UPDATES_CACHE_DIR, UPDATES_KERNEL, UPDATES_MODULES_DIR, UPDATES_DB,
# UPDATES_LOCK_TIMEOUT.
#
set -uo pipefail

REPO_CMD="${UPDATES_REPO_CMD:-checkupdates}"
KERNEL="${UPDATES_KERNEL:-$(uname -r)}"
MODULES="${UPDATES_MODULES_DIR:-/usr/lib/modules}"
DB="${UPDATES_DB:-${TMPDIR:-/tmp}/checkup-db-${UID}}"
AURHELPER_FILE="${UPDATES_AURHELPER-}"
[ -n "$AURHELPER_FILE" ] || AURHELPER_FILE="$HOME/.config/options/aurhelper"
CACHE="${UPDATES_CACHE_DIR-}"
[ -n "$CACHE" ] || CACHE=$(pacman-conf CacheDir 2>/dev/null | head -n1)
CACHE="${CACHE%/}"
LOCK="$DB.lock"
LOCK_TIMEOUT="${UPDATES_LOCK_TIMEOUT:-120}"

fail() { echo "$1" >&2; exit 1; }

command -v "$REPO_CMD" >/dev/null 2>&1 || fail "Could not check for updates (checkupdates is not installed)"
repo=$(CHECKUPDATES_DB="$DB" flock -w "$LOCK_TIMEOUT" -E 200 "$LOCK" "$REPO_CMD" 2>/dev/null)
case $? in
    0|2) ;;
    200) fail "Could not check for updates (another check is still running)" ;;
    *) fail "Could not sync package databases (offline?)" ;;
esac

sizes=""
if [ -n "$repo" ]; then
    plist=$(LC_ALL=C pacman -Sup --dbpath "$DB" --print-format '%n %s %l' 2>/dev/null) ||
        fail "pacman cannot resolve this upgrade; update in a terminal"
    while read -r name size location; do
        [ -n "$name" ] || continue
        [[ "$size" =~ ^[0-9]+$ ]] || continue
        [ -n "$CACHE" ] && [ -e "$CACHE/${location##*/}" ] && size=0
        sizes+="$name $size"$'\n'
    done <<< "$plist"
fi

owners=""
[ -n "$repo" ] && owners=$(pacman -Qqo "$MODULES/$KERNEL" 2>/dev/null)

aur_cmd="${UPDATES_AUR_CMD-}"
if [ -z "${UPDATES_AUR_CMD+set}" ]; then
    aur_cmd=$(awk 'NR==1 {print $1}' "$AURHELPER_FILE" 2>/dev/null)
fi
aur=""
if [ -n "$aur_cmd" ] && command -v "$aur_cmd" >/dev/null 2>&1; then
    aur=$("$aur_cmd" -Qua 2>/dev/null)
fi

jq -nc --arg repo "$repo" --arg sizes "$sizes" --arg owners "$owners" --arg aur "$aur" '
    def rows($text): $text | split("\n") | map(select(length > 0));
    def updates($text): [rows($text)[] | capture("^(?<name>\\S+) (?<old>\\S+) -> (?<new>\\S+)")?];
    (rows($sizes) | map(split(" ") | {key: .[0], value: (.[1] | tonumber)}) | from_entries) as $size
    | rows($owners) as $kernel
    | (updates($repo) | map(. + {bytes: ($size[.name] // 0), kernel: (.name as $n | $kernel | index([$n]) != null)})) as $rows
    | {repo: $rows, aur: updates($aur), bytes: ([$size[]] | add // 0), kernel: ($rows | any(.kernel))}'
