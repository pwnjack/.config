#!/bin/bash
# Render the settings panel's Bar page for Waybar's built-in resource modules
# into the include waybar/config.jsonc names. Only cpu, memory and disk are
# handled here: they are Waybar built-ins and can only be hidden through
# config. custom/gpu, custom/network and custom/updates read their own
# options/bar-* file, so a hidden script skips its own work.
#
# Each mode blanks per-state formats. config.jsonc gives these modules a
# "normal" state below "warning", and a module whose format renders empty is
# hidden:
#   always  nothing rendered
#   high    format-normal ""                  (shows from warning up)
#   hidden  format-normal/-warning/-critical ""
# config.jsonc must never set those three keys itself: the main file wins
# over an include key by key, so a mode would silently stop working.
#
# Always leaves the include in place ({} when every module is "always"), so a
# fresh checkout or a missing option still shows every module.
set -euo pipefail
options=$HOME/.config/options
include=$HOME/.local/state/waybar/bar.jsonc
options=${BAR_OPTIONS:-$options}
include=${BAR_INCLUDE:-$include}

entries=()
for module in cpu memory disk; do
    mode=''
    read -r mode 2>/dev/null < "$options/bar-$module" || true
    case $mode in
        high) entries+=("\"$module\": { \"format-normal\": \"\" }") ;;
        hidden) entries+=("\"$module\": { \"format-normal\": \"\", \"format-warning\": \"\", \"format-critical\": \"\" }") ;;
    esac
done

mkdir -p "${include%/*}"
tmp=$(mktemp "$include.XXXXXX")
trap 'rm -f "$tmp"' EXIT
{
    printf '{'
    sep=''
    for entry in "${entries[@]}"; do
        printf '%s\n  %s' "$sep" "$entry"
        sep=','
    done
    printf '\n}\n'
} > "$tmp"
mv -f "$tmp" "$include"
if [[ ${1:-} != --no-reload ]]; then pkill -USR2 -x waybar 2>/dev/null || true; fi
