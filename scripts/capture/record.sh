#!/bin/bash
#
# Screen recording, and the only thing that talks to gpu-screen-recorder.
# The capture strip, Super+Shift+R, Waybar's custom/recording and lock.sh all
# come through here, so a recording has exactly one owner.
#
# Usage:
#   record.sh start [screen|window|region [WxH+X+Y]]
#   record.sh stop               stop and save (also cancels a countdown)
#   record.sh cancel             cancel a countdown; a running recording is left alone
#   record.sh toggle [target]
#   record.sh status [--json]    exit 0 while counting down or recording
#
# The target defaults to options/capture-rec-target. Delay, desktop audio and
# mic come from options/capture-delay, capture-audio and capture-mic: the
# strip writes them and this script reads them, so the keybind and the strip
# can never record differently.
#
# State: $XDG_RUNTIME_DIR/capture/recording.json, one line,
#   {"pid":…,"started":…,"output":"…","phase":"countdown|recording|stopping"}
# For a countdown, pid is this script and started is when recording begins;
# otherwise pid is the recorder and started is when it began. A pid that is
# gone, or now runs something else, means "not recording": status removes the
# file, so a crash never leaves the bar showing a timer.
#
# Waybar's module runs once and on signal 11. This script sends that signal on
# every change and, through a ticker child, once a second while recording, so
# an idle bar runs nothing at all.
#
# gpu-screen-recorder installs its own SIGINT handler, which is what lets
# `kill -INT` finalise the file even though a background job of a
# non-interactive shell starts with SIGINT ignored. A bash stand-in cannot
# undo that ignore, so the test's fake recorder is Python.
#
set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
options_dir="${CAPTURE_OPTIONS:-$config_dir/options}"
state_dir="${CAPTURE_STATE_DIR:-${XDG_RUNTIME_DIR:-/tmp}/capture}"
videos="${CAPTURE_VIDEOS:-$HOME/Videos/Recordings}"
recorder="${CAPTURE_RECORDER:-gpu-screen-recorder}"
stop_wait="${CAPTURE_STOP_WAIT:-10}"
state="$state_dir/recording.json"
log="$state_dir/gsr.log"
# KMS capture needs this helper to hold cap_sys_admin; doctor's binaries check
# reads the name from this line.
# shellcheck disable=SC2034
readonly KMS_SERVER=gsr-kms-server

# Nerd Font glyphs, escaped so no editor can drop them: timer, record dot.
glyph_timer=$'\U000F051B' glyph_rec=$'\U000F044A'

usage() {
    echo 'usage: record.sh start [screen|window|region [WxH+X+Y]] | stop | cancel | toggle [target] | status [--json]' >&2
    exit 2
}

# option <name> <default> -> the first line of options/<name>, or the default.
option() {
    local value=""
    { read -r value < "$options_dir/$1"; } 2>/dev/null
    printf '%s' "${value:-$2}"
}

signal_bar() { pkill -RTMIN+11 waybar 2>/dev/null || true; }
notify() { notify-send -a Capture -i "$1" "$2" "${3-}" 2>/dev/null || true; }
now() { printf '%(%s)T' -1; }

# alive <pid> <needle> -> 0 when pid runs a command line containing needle.
# A bare kill -0 would accept a recycled pid.
alive() {
    local -a args
    [ -n "$1" ] && [ -r "/proc/$1/cmdline" ] || return 1
    mapfile -d '' args < "/proc/$1/cmdline" 2>/dev/null || return 1
    [[ " ${args[*]} " == *"$2"* ]]
}

# read_state -> sets pid started output phase; 1, removing the file, when
# nothing is live.
read_state() {
    local line="" needle="${recorder##*/}"
    pid="" started="" output="" phase=""
    { read -r line < "$state"; } 2>/dev/null
    [ -n "$line" ] || return 1
    [[ $line =~ \"pid\":([0-9]+) ]] && pid=${BASH_REMATCH[1]}
    [[ $line =~ \"started\":([0-9]+) ]] && started=${BASH_REMATCH[1]}
    [[ $line =~ \"output\":\"([^\"]*)\" ]] && output=${BASH_REMATCH[1]}
    [[ $line =~ \"phase\":\"([a-z]+)\" ]] && phase=${BASH_REMATCH[1]}
    [ "$phase" = countdown ] && needle=record.sh
    if ! alive "$pid" "$needle"; then
        rm -f "$state"
        return 1
    fi
}

# write_state <pid> <phase> <output> <started>
write_state() {
    local out=${3//\\/\\\\}
    out=${out//\"/\\\"}
    mkdir -p "$state_dir" || return 1
    printf '{"pid":%s,"started":%s,"output":"%s","phase":"%s"}\n' "$1" "$4" "$out" "$2" > "$state.tmp" \
        && mv -f "$state.tmp" "$state"
}

# fmt <seconds> -> m:ss, or h:mm:ss from an hour on (model.mjs formatElapsed agrees).
fmt() {
    local s=$1
    if (( s >= 3600 )); then
        printf '%d:%02d:%02d' $((s / 3600)) $((s % 3600 / 60)) $((s % 60))
    else
        printf '%d:%02d' $((s / 60)) $((s % 60))
    fi
}

first_error() {
    local line
    line=$(grep -m1 -iE 'error|fail' "$log" 2>/dev/null) || line=$(head -n1 "$log" 2>/dev/null)
    printf '%s' "${line:-The recorder exited without a message. Log: $log}"
}

focused_monitor() {
    hyprctl monitors -j 2>/dev/null | jq -r 'first(.[] | select(.focused) | .name) // empty' 2>/dev/null
}

# window_rects -> one "X,Y WxH" box per window on a visible workspace, for slurp -r.
window_rects() {
    local visible
    visible=$(hyprctl monitors -j 2>/dev/null | jq -c '[.[].activeWorkspace.id]' 2>/dev/null) || return 1
    hyprctl clients -j 2>/dev/null | jq -r --argjson ws "$visible" '
        .[] | select(.mapped and (.hidden | not) and (.workspace.id as $w | any($ws[]; . == $w)))
        | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}

# saved <file> -- the toast. Open and Show in folder are handled by a detached
# notify-send --wait, so this script returns at once.
saved() {
    (
        exec </dev/null >/dev/null 2>&1
        choice=$(notify-send -a Capture -i video-x-generic --wait \
            -A open=Open -A folder='Show in folder' 'Recording saved' "${1##*/}") || exit 0
        case $choice in
            open) exec xdg-open "$1" ;;
            folder)
                gdbus call --session --dest org.freedesktop.FileManager1 \
                    --object-path /org/freedesktop/FileManager1 \
                    --method org.freedesktop.FileManager1.ShowItems "['file://$1']" '' \
                    || exec xdg-open "${1%/*}" ;;
        esac
    ) 7>&- &
}

# ticker <recorder-pid> -- one Waybar refresh a second while the recorder runs.
# If it dies while the state still says "recording" (not a stop), say so.
ticker() {
    local line=""
    while alive "$1" "${recorder##*/}"; do
        sleep 1
        signal_bar
    done
    { read -r line < "$state"; } 2>/dev/null
    if [[ $line == *"\"pid\":$1,"* && $line == *'"phase":"recording"'* ]]; then
        rm -f "$state"
        notify dialog-error 'Recording stopped' "$(first_error)"
    fi
    signal_bar
}

status() {
    local json=0 seconds t
    [ "${1-}" = --json ] && json=1
    if ! read_state; then
        if (( json )); then
            echo '{"text":"","tooltip":"","class":"idle","phase":"idle","seconds":0}'
            return 0
        fi
        echo idle
        return 1
    fi
    t=$(now)
    if [ "$phase" = countdown ]; then
        seconds=$(( started > t ? started - t : 0 ))
    else
        seconds=$(( t - started ))
    fi
    if (( ! json )); then
        echo "$phase $seconds $output"
        return 0
    fi
    case $phase in
        countdown)
            printf '{"text":"%s %d","tooltip":"Recording starts in %d s. Click to cancel.","class":"countdown","phase":"countdown","seconds":%d}\n' \
                "$glyph_timer" "$seconds" "$seconds" "$seconds" ;;
        stopping)
            printf '{"text":"%s saving","tooltip":"Saving the recording","class":"stopping","phase":"stopping","seconds":%d}\n' \
                "$glyph_rec" "$seconds" ;;
        *)
            printf '{"text":"%s %s","tooltip":"Recording. Click to stop and save.","class":"recording","phase":"recording","seconds":%d}\n' \
                "$glyph_rec" "$(fmt "$seconds")" "$seconds" ;;
    esac
}

stop() {
    local i
    read_state || return 0
    case $phase in
        countdown)
            kill -TERM "$pid" 2>/dev/null
            return 0 ;;
        stopping)
            # Another stop is saving it; wait, so a lock never beats the save.
            for ((i = 0; i < (stop_wait + 1) * 10; i++)); do
                read_state || return 0
                sleep 0.1
            done
            return 0 ;;
    esac
    write_state "$pid" stopping "$output" "$started"
    signal_bar
    kill -INT "$pid" 2>/dev/null
    for ((i = 0; i < stop_wait * 10; i++)); do
        alive "$pid" "${recorder##*/}" || break
        sleep 0.1
    done
    if alive "$pid" "${recorder##*/}"; then
        kill -KILL "$pid" 2>/dev/null
        rm -f "$state"
        signal_bar
        notify dialog-error 'Recording not saved' "The recorder did not finish within ${stop_wait} s. Log: $log"
        return 1
    fi
    rm -f "$state"
    signal_bar
    if [ -s "$output" ]; then
        saved "$output"
    else
        notify dialog-error 'Recording not saved' "$(first_error)"
        return 1
    fi
}

cancel() {
    read_state && [ "$phase" = countdown ] && kill -TERM "$pid" 2>/dev/null
    return 0
}

start() {
    local target=${1-} region=${2-} monitor delay file audio="" rec_pid
    local -a args
    if [ -z "$target" ]; then
        target=$(option capture-rec-target screen)
        case $target in screen|window|region) ;; *) target=screen ;; esac
    fi
    case $target in screen|window|region) ;; *) usage ;; esac
    if [ -n "$region" ]; then
        [ "$target" = region ] || usage
        [[ $region =~ ^[0-9]+x[0-9]+\+-?[0-9]+\+-?[0-9]+$ ]] || usage
    fi

    # A second start while one runs is the toggle: stop it.
    if read_state; then
        stop
        return
    fi
    if ! command -v "$recorder" >/dev/null 2>&1; then
        notify dialog-error 'Recording unavailable' 'Install the gpu-screen-recorder package to record the screen.'
        return 1
    fi
    mkdir -p "$state_dir" || return 1
    # One start at a time: a second press while selecting is dropped.
    exec 7>"$state_dir/start.lock"
    flock -n 7 || return 0

    case $target in
        screen)
            monitor=$(focused_monitor)
            if [ -z "$monitor" ]; then
                notify dialog-error 'Recording failed' 'Hyprland reported no focused monitor.'
                return 1
            fi
            args=(-w "$monitor") ;;
        region)
            # Esc in slurp cancels silently: no toast, nothing written.
            [ -n "$region" ] || region=$(slurp -f '%wx%h+%x+%y') || return 0
            [ -n "$region" ] || return 0
            args=(-w region -region "$region") ;;
        window)
            # The rectangle is fixed now: moving the window later is not followed.
            region=$(window_rects | slurp -r -f '%wx%h+%x+%y') || return 0
            [ -n "$region" ] || return 0
            args=(-w region -region "$region") ;;
    esac

    delay=$(option capture-delay 0)
    [[ $delay =~ ^[0-9]+$ ]] || delay=0
    # Task 2 adds: (( delay > 0 )) && countdown "$delay"

    args+=(-c mp4 -k h264 -ac aac -f 60 -q very_high -cursor yes)
    [ "$(option capture-audio false)" = true ] && audio=default_output
    [ "$(option capture-mic false)" = true ] && audio+="${audio:+|}default_input"
    [ -n "$audio" ] && args+=(-a "$audio")
    if ! mkdir -p "$videos"; then
        notify dialog-error 'Recording failed' "Cannot create $videos."
        return 1
    fi
    printf -v file '%s/Recording_%(%Y-%m-%d_%H-%M-%S)T.mp4' "$videos" -1
    args+=(-v no -o "$file")

    # setsid in a background job execs the recorder in place (the job is not a
    # process-group leader), so $! is the recorder's own pid.
    setsid "$recorder" "${args[@]}" </dev/null >"$log" 2>&1 7>&- &
    rec_pid=$!
    write_state "$rec_pid" recording "$file" "$(now)"
    signal_bar
    sleep 0.5
    if ! alive "$rec_pid" "${recorder##*/}"; then
        rm -f "$state"
        signal_bar
        notify dialog-error 'Recording failed' "$(first_error)"
        return 1
    fi
    ticker "$rec_pid" </dev/null >/dev/null 2>&1 7>&- &
    return 0
}

case "${1-}" in
    start) shift; start "$@" ;;
    stop) stop ;;
    cancel) cancel ;;
    toggle) shift; if read_state; then stop; else start "$@"; fi ;;
    status) status "${2-}" ;;
    *) usage ;;
esac
