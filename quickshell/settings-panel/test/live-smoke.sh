#!/bin/bash
# Explicit, opt-in desktop check. Opens/closes the panel; does not edit settings.
set -euo pipefail
config_dir="$HOME/.config"
entry="$config_dir/quickshell/settings-panel/shell.qml"
ipc() { qs -p "$entry" ipc call settings "$@"; }
if ipc status >/dev/null 2>&1; then
    echo 'Close the settings panel before running this check.' >&2
    exit 1
fi
trap 'ipc close >/dev/null 2>&1 || true' EXIT
appearance_rows=$(jq '[.rows[] | select(.category == "appearance")] | length' "$config_dir/quickshell/settings-panel/catalog.json")
for run in 1 2 3; do
    bash "$config_dir/scripts/hyprland/settings-panel.sh"
    ready=false
    for ((attempt=0; attempt<100; attempt++)); do
        status=$(ipc status 2>/dev/null || true)
        if jq -e '.loading == false and .frameMs >= 0' <<< "$status" >/dev/null 2>&1; then ready=true; break; fi
        sleep 0.05
    done
    "$ready" || { echo 'Panel never became ready' >&2; exit 1; }
    jq -e --argjson rows "$appearance_rows" '.error == "" and (.rowErrors | length) == 0 and .rows == $rows' <<< "$status"
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
# Network page: exactly one event source while visible, none after leaving or closing.
bash "$config_dir/scripts/hyprland/settings-panel.sh" network
for ((attempt=0; attempt<100; attempt++)); do
    status=$(ipc status 2>/dev/null || true)
    if jq -e '.loading == false and .category == "network"' <<< "$status" >/dev/null 2>&1; then break; fi
    sleep 0.05
done
sleep 0.5
monitors=$(pgrep -fc '^(/usr/bin/)?nmcli monitor$' || true)
[[ $monitors == 1 ]] || { echo "Expected one nmcli monitor on the Network page, found $monitors" >&2; exit 1; }
ps -o rss= -C nmcli | awk '{printf "nmcli monitor RSS: %s KiB\n", $1}'
ipc page appearance >/dev/null; sleep 0.5
[[ $(pgrep -fc '^(/usr/bin/)?nmcli monitor$' || true) == 0 ]] || { echo 'nmcli monitor kept running off the Network page' >&2; exit 1; }
ipc close >/dev/null; sleep 1
if pgrep -af '^(/usr/bin/)?nmcli monitor$|settings-panel/shell.qml'; then echo 'Something survived close' >&2; exit 1; fi
echo 'Network page: one monitor while visible, none after leaving or closing.'

# Page entry while another read is in flight must still load the network view
# (shell.qml readerNetwork/liveTimer path; SettingsView tests use a mock controller).
bash "$config_dir/scripts/hyprland/settings-panel.sh"
ipc page network >/dev/null
for ((attempt=0; attempt<60; attempt++)); do
    [[ $(ipc status | jq -r .network) == up ]] && break
    sleep 0.05
done
[[ $(ipc status | jq -r .network) == up ]] || { echo 'Network page entered during the first read never loaded' >&2; exit 1; }
ipc close >/dev/null; sleep 1

median() { sort -n | sed -n 3p; }
time_request() { for _ in 1 2 3 4 5; do s=$(date +%s%N); bash "$config_dir/scripts/settings/panel-request.sh" "$1" >/dev/null; echo $(( ($(date +%s%N)-s)/1000000 )); done | median; }
empty=$(time_request '{"op":"read","ids":[]}')
network=$(time_request '{"op":"read","ids":[],"network":true}')
startup=$(time_request '{"op":"read","ids":[],"startup":true}')
printf 'Empty %s ms, network %s ms, startup %s ms\n' "$empty" "$network" "$startup"
(( network - empty <= 30 )) || { echo 'network read over budget' >&2; exit 1; }
(( startup - empty <= 40 )) || { echo 'startup read over budget' >&2; exit 1; }

# Query all categories through the actual native helper, without changing values.
request=$(jq -c '{op:"read", ids:[.rows[].id], monitors:true}' "$config_dir/quickshell/settings-panel/catalog.json")
response=$(bash "$config_dir/scripts/settings/panel-request.sh" "$request")
expected=$(jq '.rows | length' "$config_dir/quickshell/settings-panel/catalog.json")
jq -e --argjson expected "$expected" '.ok and ([.values[] | select(.error)] | length) == 0 and (.values | length) == $expected' <<< "$response"
printf 'All %s settings read successfully; no panel instance remains.\n' "$expected"
