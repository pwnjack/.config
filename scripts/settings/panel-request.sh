#!/bin/bash
# Serialize requests across instances too, including apply/save and rollback.
set -euo pipefail
[[ $# == 1 ]] || { echo 'Expected one JSON request' >&2; exit 2; }
for binary in gjs flock; do
    command -v "$binary" >/dev/null || { echo "$binary is required" >&2; exit 1; }
done
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
request_js="$repo_root/quickshell/settings-panel/request.js"
request_arg=$1
# Consume stdin before waiting for the cross-instance lock. A writer must never
# hold the lock while it is still waiting for its request, and the request must
# never be copied into argv or the environment.
if [[ $request_arg == - ]]; then
    request_line=
    if IFS= read -r -t 30 request_line; then
        :
    else
        read_status=$?
        if (( read_status > 128 )); then
            printf '%s\n' '{"ok":false,"error":"Expected one JSON request on stdin"}'
            exit 1
        fi
        # Preserve a final unterminated line, or pass an empty line to request.js.
    fi
fi
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/settings-panel"
mkdir -p "$cache_dir"
exec 9>"$cache_dir/request.lock"
flock -w 30 9 || { echo 'Settings are busy; try again.' >&2; exit 1; }
# `-` means the request arrives on stdin (the panel's writes: they can carry a Wi-Fi password).
if [[ $request_arg == - ]]; then
    exec gjs -m "$request_js" - <<<"$request_line"
else
    exec gjs -m "$request_js" "$request_arg"
fi
