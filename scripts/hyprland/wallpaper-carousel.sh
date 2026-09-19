#!/bin/bash
# Serialize startup/toggle requests. Quickshell owns the resident UI and IPC.
set -euo pipefail
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
mode=${1:-toggle}
case "$mode" in toggle|start) ;; *) echo 'Usage: wallpaper-carousel.sh [toggle|start]' >&2; exit 2 ;; esac
if ! command -v qs >/dev/null 2>&1; then
    if [[ $mode == toggle ]] && command -v waypaper >/dev/null 2>&1; then
        exec waypaper
    fi
    echo 'Install quickshell to use the wallpaper carousel.' >&2
    exit 1
fi
command -v flock >/dev/null || { echo 'flock is required' >&2; exit 1; }
mkdir -p "$cache_dir/wallpaper-carousel"
exec 9>"$cache_dir/wallpaper-carousel/launch.lock"
flock -w 10 9 || exit 1
entry="$config_dir/quickshell/wallpaper-carousel/shell.qml"
ipc() { qs -p "$entry" ipc call carousel "$1" 9>&-; }
if ! ipc ping >/dev/null 2>&1; then
    qs -p "$entry" --no-duplicate --daemonize >"$cache_dir/wallpaper-carousel/session.log" 2>&1 9>&- \
        || { echo "Carousel startup failed; see $cache_dir/wallpaper-carousel/session.log" >&2; exit 1; }
    ready=false
    for ((attempt = 0; attempt < 60; attempt++)); do
        if ipc ping >/dev/null 2>&1; then ready=true; break; fi
        sleep 0.05
    done
    "$ready" || { echo "Carousel IPC unavailable; see $cache_dir/wallpaper-carousel/session.log" >&2; exit 1; }
fi
if [[ $mode == toggle ]]; then ipc toggle; fi
