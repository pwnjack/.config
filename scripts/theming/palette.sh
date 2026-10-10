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

# wal_render <template> <output>
#
# Copies a template with every @colorN@ replaced by wal[N] and every
# @oncolorN@ by the text color readable on it. Call wal_load first.
#
# Highest index first: @color1@ is a prefix of @color15@, so substituting it
# first would leave a stray "5" behind.
wal_render() {
    local -a sed_args=()
    local i
    for ((i = 15; i >= 0; i--)); do
        sed_args+=(-e "s|@color$i@|${wal[$i]}|g")
        sed_args+=(-e "s|@oncolor$i@|$(wal_readable_on "${wal[$i]}")|g")
    done
    sed "${sed_args[@]}" "$1" > "$2"
}

# wal_oklch <hex> <lmin> <lmax> <cmax> [dl]
#
# Echoes <hex> with its OKLCH lightness clamped to [lmin, lmax], its chroma
# capped at cmax, and dl then added to the lightness; hue is kept. This is the
# CSS themes' `oklch(from X clamp(lmin, l, lmax) min(c, cmax) h)` for
# consumers that accept only hex, so every component can keep surfaces and
# accents in the same readable range whatever the wallpaper gives.
#
# awk because bash has no floats. A result outside sRGB is clipped per
# channel, which only happens for strong accents and shifts them slightly.
wal_oklch() {
    awk -v hex="${1#\#}" -v lmin="$2" -v lmax="$3" -v cmax="$4" -v dl="${5:-0}" '
        function byte(i) {
            return (index("0123456789abcdef", substr(hex, i, 1)) - 1) * 16 \
                 + index("0123456789abcdef", substr(hex, i + 1, 1)) - 1
        }
        function lin(c) { c /= 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4 }
        function cbrt(x) { return x <= 0 ? 0 : exp(log(x) / 3) }
        function enc(c) {
            c = c <= 0.0031308 ? 12.92 * c : 1.055 * c ^ (1 / 2.4) - 0.055
            c = c < 0 ? 0 : (c > 1 ? 1 : c)
            return int(c * 255 + 0.5)
        }
        BEGIN {
            hex = tolower(hex)
            r = lin(byte(1)); g = lin(byte(3)); b = lin(byte(5))
            l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
            A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
            B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
            C = sqrt(A * A + B * B)
            if (C > cmax) { A *= cmax / C; B *= cmax / C }
            L = (L < lmin ? lmin : (L > lmax ? lmax : L)) + dl
            L = L < 0 ? 0 : (L > 1 ? 1 : L)
            l = (L + 0.3963377774 * A + 0.2158037573 * B) ^ 3
            m = (L - 0.1055613458 * A - 0.0638541728 * B) ^ 3
            s = (L - 0.0894841775 * A - 1.2914855480 * B) ^ 3
            printf "#%02x%02x%02x\n",
                enc( 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                enc(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                enc(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        }'
}
