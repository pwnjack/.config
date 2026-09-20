#!/bin/bash
# Serialize requests across instances too, including apply/save and rollback.
set -euo pipefail
[[ $# == 1 ]] || { echo 'Expected one JSON request' >&2; exit 2; }
for binary in gjs flock; do
    command -v "$binary" >/dev/null || { echo "$binary is required" >&2; exit 1; }
done
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/settings-panel"
mkdir -p "$cache_dir"
exec 9>"$cache_dir/request.lock"
flock -w 30 9 || { echo 'Settings are busy; try again.' >&2; exit 1; }
gjs -m "$HOME/.config/quickshell/settings-panel/request.js" "$1"
