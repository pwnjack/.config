#!/usr/bin/env bash

##
## Original Author : Aditya Shakya (adi1090x)
## Original Github : @adi1090x
## Adapted by : @GeodeArc
##

stlconf="$(cat $HOME/.config/options/style)"
thmconf="$(cat $HOME/.config/options/theme)"
launcher="$(cat $HOME/.config/options/launchertype)"

config="$stlconf"
theme="$thmconf"

dir="$HOME/.config/rofi/$config/$theme/launcher"
mode="$launcher"

## Run
rofi \
    -show drun \
    -theme ${dir}/${mode}.rasi
