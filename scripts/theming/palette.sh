#!/bin/bash
#
# Shared pywal palette loader, sourced by each component's apply_wal_colors.sh.
#
# Defines wal_load(), which fills the caller's `wal` array with 16 hex colors,
# wal[0] (background) through wal[15]. pywal writes color0 and color7 as the
# same values it reports for `background` and `foreground`, so no separate
# parse is needed for those.
#
# It reads ~/.cache/wal/colors — 16 lines of plain hex — rather than
# colors.sh, so loading the palette never evaluates a generated file as shell.
#
# When pywal has not run yet the fallback palette below is used instead of
# failing. Every apply script must still produce output on a fresh checkout,
# because the repo tracks a symlink to that output and a dangling tracked
# symlink is an ERROR in doctor.sh.
#

# Neutral dark palette, used only until the first `wal -i` run.
_WAL_FALLBACK=(
    '#05090C' '#2A7789' '#4D7D85' '#318A9B'
    '#6097A1' '#8DAFB4' '#9ABBC2' '#cfddde'
    '#909a9b' '#2A7789' '#4D7D85' '#318A9B'
    '#6097A1' '#8DAFB4' '#9ABBC2' '#cfddde'
)

# Fills `wal` in the caller's scope. Callers declare it first so that the
# variable is visibly assigned at the call site.
# shellcheck disable=SC2034  # `wal` is the output, read by the sourcing script.
wal_load() {
    local colors_file="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors"
    local -a loaded=()
    local line

    if [ -r "$colors_file" ]; then
        while IFS= read -r line; do
            # Tolerate stray blank lines. Anything that is not a hex triplet
            # means the file is not what we expect: stop reading, so the count
            # below falls short of 16 and the fallback is used. Returning here
            # instead would leave `wal` unset and break the contract that this
            # function always yields a usable palette.
            [ -n "$line" ] || continue
            [[ "$line" == \#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F] ]] || break
            loaded+=("$line")
        done < "$colors_file"
    fi

    if [ "${#loaded[@]}" -eq 16 ]; then
        wal=("${loaded[@]}")
    else
        wal=("${_WAL_FALLBACK[@]}")
    fi
}

# Echoes whichever of wal[0] / wal[15] stays legible as text on the given
# background color.
#
# A wallpaper palette is not designed for contrast: color1 can come out nearly
# black on one image and near-white on the next, so any fixed text color is
# unreadable half the time. This picks per background instead.
#
# The threshold is ITU-R BT.601 perceived brightness, the same weighting most
# terminal themes use. It is integer math on purpose — bash has no floats and
# pulling in bc for a light/dark decision is not worth it.
wal_readable_on() {
    local hex="${1#\#}"
    local r g b brightness

    r=$((16#${hex:0:2}))
    g=$((16#${hex:2:2}))
    b=$((16#${hex:4:2}))
    brightness=$(( (299 * r + 587 * g + 114 * b) / 1000 ))

    if [ "$brightness" -gt 128 ]; then
        printf '%s' "${wal[0]}"
    else
        printf '%s' "${wal[15]}"
    fi
}
