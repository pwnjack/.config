#!/bin/bash
#
# Render the pywal palette as a btop theme.
#
# btop reads themes from ~/.config/btop/themes/, and btop.conf selects this one
# with color_theme = "pywal". The tracked btop/themes/pywal.theme is a symlink
# to the file written here, so no tracked file changes at runtime.
#
# btop reads its theme once at startup and offers no reload signal, so a
# running instance keeps the old colors until it is restarted. Nothing to
# trigger here.
#
# main_bg is emitted empty on purpose. btop treats an empty value as "use the
# terminal default", which is what btop.conf's theme_background = false relies
# on to let ghostty's transparency through.
#
# The gradient triples are start -> mid -> end. pywal orders color1..color7 by
# ascending lightness, so every meter reads low-to-high as dim-to-bright. The
# four memory meters are offset against each other so they stay distinguishable
# on a near-monochrome palette, where a single ramp would make them identical.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
theme_file="$cache_dir/btop.theme"

declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
. "$config_dir/scripts/theming/palette.sh"
wal_load

mkdir -p "$cache_dir"

# start mid end, one triple per meter.
_btop_gradient() {
    printf 'theme[%s_start]="%s"\ntheme[%s_mid]="%s"\ntheme[%s_end]="%s"\n' \
        "$1" "$2" "$1" "$3" "$1" "$4"
}

{
    echo "# Automatically generated from the pywal palette - do not edit manually"
    echo

    echo "theme[main_bg]=\"\""
    echo "theme[main_fg]=\"${wal[7]}\""
    echo "theme[title]=\"${wal[7]}\""
    echo "theme[hi_fg]=\"${wal[4]}\""
    echo "theme[selected_bg]=\"${wal[1]}\""
    echo "theme[selected_fg]=\"${wal[7]}\""
    echo "theme[inactive_fg]=\"${wal[8]}\""
    echo "theme[graph_text]=\"${wal[6]}\""
    echo "theme[meter_bg]=\"${wal[8]}\""
    echo "theme[proc_misc]=\"${wal[5]}\""
    echo

    # Newer btop keys, absent from most bundled themes. Without them btop 1.4.7
    # logs "Missing color value" and falls back to its built-in defaults, which
    # are off-palette. Highlight backgrounds take the dark background as their
    # text color so they stay legible on any wallpaper.
    echo "theme[followed_bg]=\"${wal[4]}\""
    echo "theme[followed_fg]=\"${wal[0]}\""
    echo "theme[proc_banner_bg]=\"${wal[3]}\""
    echo "theme[proc_banner_fg]=\"${wal[0]}\""
    echo "theme[proc_follow_bg]=\"${wal[2]}\""
    echo "theme[proc_pause_bg]=\"${wal[1]}\""
    echo

    # Box outlines, one palette step apart so the four boxes stay readable.
    echo "theme[cpu_box]=\"${wal[4]}\""
    echo "theme[mem_box]=\"${wal[2]}\""
    echo "theme[net_box]=\"${wal[5]}\""
    echo "theme[proc_box]=\"${wal[3]}\""
    echo "theme[div_line]=\"${wal[8]}\""
    echo

    _btop_gradient temp      "${wal[2]}" "${wal[4]}" "${wal[6]}"
    _btop_gradient cpu       "${wal[1]}" "${wal[4]}" "${wal[7]}"
    _btop_gradient free      "${wal[2]}" "${wal[5]}" "${wal[7]}"
    _btop_gradient cached    "${wal[3]}" "${wal[5]}" "${wal[7]}"
    _btop_gradient available "${wal[4]}" "${wal[6]}" "${wal[7]}"
    _btop_gradient used      "${wal[1]}" "${wal[4]}" "${wal[7]}"
    _btop_gradient download  "${wal[2]}" "${wal[4]}" "${wal[6]}"
    _btop_gradient upload    "${wal[3]}" "${wal[5]}" "${wal[7]}"
    _btop_gradient process   "${wal[1]}" "${wal[4]}" "${wal[7]}"
} > "$theme_file"

exit 0
