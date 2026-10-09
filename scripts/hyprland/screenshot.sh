#!/bin/bash
#
# Capture a screenshot.
#
# Usage: screenshot.sh screen|window|region|output [--annotate] [--delay N]
#
# The one capture command: Super+S, Super+Alt+S and the capture strip all call
# it, so all of them honour options/capture-freeze ("true" freezes the screen
# while selecting).
#
#   screen     the focused monitor, no selection
#   window     click a window (hyprshot's own picker)
#   region     drag a rectangle
#   output     pick a monitor (the rofi menu's entry, until that menu goes)
#   --annotate open the shot in swappy instead of writing it; where it lands
#              is then swappy's decision, from swappy/config
#   --delay N  wait N seconds first (the strip's delay; Super+S has none)
#
# Without --annotate the file goes to ~/Pictures/Screenshots.
#
# --annotate uses hyprshot's LONG --raw, and never -s. Both rules come from
# reading /usr/bin/hyprshot rather than its --help:
#
#   * -s is a no-op here. save_geometry() does
#     `if [ $RAW -eq 1 ]; then grim -g "$geometry" -; return 0; fi`, returning
#     before send_notification(). In raw mode there is no notification to silence.
#   * `-r -s` only works by accident. hyprshot's short spec is `hf:o:m:dszr:t:`
#     -- `r:` declares a REQUIRED argument, though the long `raw` declares
#     none. getopt binds -s as -r's argument and it survives only because
#     hyprshot's -r arm shifts by one and re-parses. Reverse the two flags and
#     getopt fails; hyprshot never checks getopt's exit status, so it would
#     carry on with RAW=0, WRITE A FILE, and pipe nothing to swappy. `--raw`
#     takes no argument and cannot be reordered into that trap.
#

usage() {
    echo "usage: ${0##*/} screen|window|region|output [--annotate] [--delay N]" >&2
    exit 2
}

mode="${1:-region}"
[ $# -gt 0 ] && shift
annotate=0 delay=0
while [ $# -gt 0 ]; do
    case "$1" in
        --annotate) annotate=1 ;;
        --delay) delay="${2-}"; shift ;;
        *) usage ;;
    esac
    shift
done
case "$mode" in
    screen|window|region|output) ;;
    *) usage ;;
esac
[[ "$delay" =~ ^[0-9]+$ ]] || usage
delay=$((10#$delay))

command -v hyprshot >/dev/null 2>&1 || exit 0
(( annotate )) && ! command -v swappy >/dev/null 2>&1 && exit 0

if [ "$mode" = screen ]; then
    monitor=$(hyprctl monitors -j 2>/dev/null | jq -r 'first(.[] | select(.focused) | .name) // empty' 2>/dev/null)
    [ -n "$monitor" ] || exit 1
    args=(-m output -m "$monitor")
else
    args=(-m "$mode")
fi
[ "$mode" != screen ] && grep -qx true "$HOME/.config/options/capture-freeze" 2>/dev/null && args+=(-z)

(( delay > 0 )) && sleep "$delay"

if (( annotate )); then
    hyprshot "${args[@]}" --raw | swappy -f -
else
    exec hyprshot "${args[@]}" -o "$HOME/Pictures/Screenshots" -f "Screenshot_$(date '+%Y-%m-%d_%H:%M:%S').png"
fi
