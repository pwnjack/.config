#!/bin/bash
# Explicit, opt-in desktop check. Opens/closes the panel; does not edit settings.
set -euo pipefail
config_dir="$HOME/.config"
entry="$config_dir/quickshell/settings-panel/shell.qml"
ipc() { qs -p "$entry" ipc call settings "$1"; }
if ipc status >/dev/null 2>&1; then
    echo 'Close the settings panel before running this check.' >&2
    exit 1
fi
trap 'ipc close >/dev/null 2>&1 || true' EXIT
for run in 1 2 3; do
    bash "$config_dir/scripts/hyprland/settings-panel.sh"
    ready=false
    for ((attempt=0; attempt<100; attempt++)); do
        status=$(ipc status 2>/dev/null || true)
        if jq -e '.loading == false and .frameMs >= 0' <<< "$status" >/dev/null 2>&1; then ready=true; break; fi
        sleep 0.05
    done
    "$ready" || { echo 'Panel never became ready' >&2; exit 1; }
    jq -e '.error == "" and (.rowErrors | length) == 0 and .rows == 14' <<< "$status"
    printf 'Run %s: %s\n' "$run" "$status"
    instances=$(qs -p "$entry" list -j)
    printf '%s\n' "$instances"
    panel_pid=$(jq -r '.[0].pid' <<< "$instances")
    parent_pid=$(ps -o ppid= -p "$panel_pid" | tr -d ' ')
    panel_pids=("$panel_pid")
    if [[ $(cat "/proc/$parent_pid/comm") == qs ]]; then panel_pids+=("$parent_pid"); fi
    for process_pid in "${panel_pids[@]}"; do
        printf 'PID %s memory:\n' "$process_pid"
        awk '/^(Rss|Pss|Private_Clean|Private_Dirty):/' "/proc/$process_pid/smaps_rollup"
    done
    if [[ $run == 1 ]]; then grim /tmp/settings-panel-live.png; fi
    ipc close
    for ((attempt=0; attempt<50; attempt++)); do
        if ! ipc status >/dev/null 2>&1; then break; fi
        sleep 0.05
    done
    if ipc status >/dev/null 2>&1; then echo 'Panel stayed resident after close' >&2; exit 1; fi
    for process_pid in "${panel_pids[@]}"; do
        for ((attempt=0; attempt<50; attempt++)); do
            if [[ ! -e /proc/$process_pid/smaps_rollup ]]; then break; fi
            sleep 0.02
        done
        if [[ -e /proc/$process_pid/smaps_rollup ]]; then echo "Process $process_pid survived close" >&2; exit 1; fi
    done
done
# Query all categories through the actual native helper, without changing values.
request=$(jq -c '{op:"read", ids:[.rows[].id], monitors:true}' "$config_dir/quickshell/settings-panel/catalog.json")
response=$(bash "$config_dir/scripts/settings/panel-request.sh" "$request")
jq -e '.ok and ([.values[] | select(.error)] | length) == 0 and (.values | length) == 56' <<< "$response"
printf 'All 56 settings read successfully; no panel instance remains.\n'
