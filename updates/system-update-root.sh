#!/bin/bash -p
# -p: privileged mode, ignores BASH_ENV/ENV/SHELLOPTS/BASHOPTS and imported functions.
#
# System update helper. The tracked source of /usr/local/bin/system-update,
# which runs as root through one NOPASSWD sudoers rule written by
# updates/setup-sudo.sh. The installed copy is what runs; this file is only
# its source and upgrade path.
#
# It takes NO input: no arguments (the sudoers rule pins an empty argument
# list, and this script refuses any), no environment it trusts (sudo resets
# it; PATH and the locale are set below), no files from the user. pacman.conf,
# the keyring and repo signatures are root-owned, so the most this can do for
# anyone running as the user is upgrade the system to correctly signed repo
# packages. It never runs paru, flatpak or anything else, and never reboots.
#
# Output is pacman's own text plus markers the unprivileged runner folds
# (scripts/updates/fold.mjs via quickshell/updates/model.mjs):
#   @@phase download   before `pacman -Syuw` (sync + download only)
#   @@bytes <n>        every 0.5 s during it: bytes added to the package cache
#   @@phase install    before `pacman -Su` (install from the complete cache)
#   @@busy             another update holds this helper's lock (exit 75)
# All interpretation happens unprivileged; keep this file small.

set -u
export LC_ALL=C
export PATH=/usr/bin

if [ "$#" -ne 0 ]; then
    echo 'Usage: system-update (takes no arguments)' >&2
    exit 2
fi

exec 9>/run/system-update.lock
if ! flock -n 9; then
    echo '@@busy'
    exit 75
fi

cache=$(pacman-conf CacheDir 2>/dev/null | head -n1)
cache=${cache%/}
[ -d "$cache" ] || cache=/var/cache/pacman/pkg

# pacman 7 downloads as DownloadUser into a download-XXXXXX directory inside
# the cache, then moves finished packages into the cache itself. Growth of the
# whole cache directory counts both, each byte once.
cache_bytes() {
    du -sb -- "$cache" 2>/dev/null | cut -f1
}
base=$(cache_bytes)
base=${base:-0}

# If this shell is terminated mid-download the traps run only once the
# foreground pacman returns: bash defers them, which is intended, because a
# transaction must never be interrupted. The sampler then goes with us.
sampler=
trap 'kill "$sampler" 2>/dev/null' EXIT
trap 'exit 143' TERM INT HUP

echo '@@phase download'
# fd 9 is closed for the sampler so it can never hold the lock; $$ is still
# this shell's pid inside the subshell, so it ends when we do.
(
    while kill -0 "$$" 2>/dev/null && sleep 0.5; do
        now=$(cache_bytes)
        echo "@@bytes $(( ${now:-$base} - base ))"
    done
) 9>&- &
sampler=$!
# stdbuf: pacman's stdout is block-buffered into a pipe, which would deliver
# a whole phase's lines at once and make the progress bar jump.
# 9>&-: pacman's hooks and children must not inherit the lock.
stdbuf -oL -eL pacman -Syuw --noconfirm 2>&1 9>&-
status=$?
kill "$sampler" 2>/dev/null
wait "$sampler" 2>/dev/null
[ "$status" -eq 0 ] || exit "$status"

echo '@@phase install'
stdbuf -oL -eL pacman -Su --noconfirm 2>&1 9>&-
exit $?
