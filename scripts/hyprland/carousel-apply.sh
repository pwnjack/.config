#!/bin/bash
# Waypaper persists and applies; verify awww before running the theme hook once.
set -euo pipefail
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
fail() {
    echo "$*" >&2
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -i preferences-desktop-wallpaper 'Wallpaper selection failed' "$*" 9>&- || true
    fi
    exit 1
}
for command in waypaper awww flock python3; do
    command -v "$command" >/dev/null || fail "$command is not installed"
done
[[ $# == 1 && $1 == /* && -f $1 && -r $1 ]] || fail 'The selected image is no longer readable.'
# The backend query and Waypaper INI format are line-oriented.
[[ $1 != *$'\n'* && $1 != *$'\r'* ]] || fail 'Wallpaper names containing line breaks are not supported.'
# Waypaper uses ConfigParser interpolation and cannot save a literal percent.
[[ $1 != *%* ]] || fail 'Waypaper cannot save names containing %. Rename this image first.'
mkdir -p "$cache_dir/wallpaper-carousel" || fail 'Cannot create the carousel cache.'
exec 9>"$cache_dir/wallpaper-carousel/apply.lock"
flock -n 9 || fail 'Another wallpaper selection is still being applied.'

# Suppress the asynchronous hook: a zero Waypaper exit status alone proves nothing.
waypaper --backend awww --monitor All --no-post-command --wallpaper "$1" 9>&- \
    || fail 'Waypaper could not submit this wallpaper.'
matched=false
for ((attempt = 0; attempt < 40; attempt++)); do
    if query=$(awww query 9>&-); then
        matched=true
        count=0
        while IFS= read -r line; do
            [[ -n $line ]] || continue
            ((count += 1))
            if [[ $line != *'image: '* || ${line#*image: } != "$1" ]]; then
                matched=false
            fi
        done <<< "$query"
        if "$matched" && ((count > 0)); then break; fi
        matched=false
    fi
    sleep 0.05
done
"$matched" || fail 'The wallpaper was not confirmed on all monitors. Try again or open Waypaper.'
if ! python3 - "$config_dir/waypaper/config.ini" "$1" 9>&- <<'PY'
import configparser
from pathlib import Path
import sys
try:
    config = configparser.ConfigParser()
    with open(sys.argv[1]) as stream:
        config.read_file(stream)
    saved = config.get('Settings', 'wallpaper')
    assert str(Path(saved).expanduser()) == sys.argv[2]
except (OSError, ValueError, configparser.Error, AssertionError):
    sys.exit(1)
PY
then
    fail 'The wallpaper changed, but Waypaper did not save it for login restoration.'
fi
# wall.sh owns the theme lock, reads the latest display state and reports failures.
# Keep this separate submission lock through completion; close it in all children.
"$config_dir/scripts/hyprland/wall.sh" 9>&-
