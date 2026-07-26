#!/bin/bash
#
# GPU usage + temperature for waybar.
#
# Emits JSON through jq rather than printf: the GPU name is vendor-supplied
# free text, and hand-built JSON breaks the module the day a name contains a
# quote. jq also lets the glyph stay an ASCII \u escape, so this file needs no
# Nerd Font installed to be edited safely.
#
# The glyph is wrapped in <span size='large'> to match the bar's scale: every
# module sits at 13px and promotes its glyph by 20%. See waybar/style.css.
#
# One nvidia-smi call, not five. The old version spawned the binary once per
# field, five times every 5s interval.
#

command -v nvidia-smi >/dev/null 2>&1 || exit 0

read -r usage temp used total name < <(
    nvidia-smi \
        --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,name \
        --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ','
)

# No reading means no GPU to report. Stay silent so waybar hides the module
# rather than rendering a bare percent sign with nothing in front of it.
[ -z "$usage" ] && exit 0

jq -nc \
    --arg usage "$usage" \
    --arg temp "$temp" \
    --arg name "$name" \
    --arg used "$used" \
    --arg total "$total" \
    '{
        text: ("<span size=\"large\">\ue266</span>  " + $usage + "%"),
        tooltip: ("GPU " + $usage + "% [" + $temp + "°C]\n\n" + $name
                  + "\nVRAM: " + $used + "MB / " + $total + "MB")
    }'
