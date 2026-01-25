#!/usr/bin/env bash
#
# Application Launcher
# Uses rofi with vertical layout
#

launcher="$(cat $HOME/.config/options/launchertype)"
dir="$HOME/.config/rofi/themes/launcher"

rofi \
    -show drun \
    -theme ${dir}/${launcher}.rasi
