#!/bin/bash
#
# Every cache-rendering apply script must produce its output from the fallback
# palette when pywal has never run: the repo tracks symlinks to these files,
# and a dangling one is a doctor ERROR on a fresh checkout.
#
# swaync only reloads a live consumer and renders nothing, so it is not run.
# pkill and hyprctl are stubbed so no running cava or Hyprland is touched.
#

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/cache"
for stub in pkill hyprctl; do
    printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/$stub"
    chmod +x "$tmp/bin/$stub"
done

# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"

# component script -> the cache file its tracked symlink points at
declare -A outputs=(
    [rofi]=colors-rofi.rasi
    [ghostty]=ghostty-colors
    [Thunar]=thunar-gtk.css
    [cava]=cava-config
    [starship]=starship.toml
    [btop]=btop.theme
    [waybar]=colors-waybar.css
    [hypr]=colors-hyprland.lua
)

# shellcheck source=scripts/theming/palette.sh
. "$ROOT/scripts/theming/palette.sh"
declare -a wal=()
XDG_CACHE_HOME="$tmp/cache" wal_load   # empty cache: the fallback palette

uses_palette() {
    local color
    for color in "${wal[@]}"; do
        grep -qiF "${color#\#}" "$1" && return 0
    done
    return 1
}

for component in "${!outputs[@]}"; do
    out="$tmp/cache/wal/${outputs[$component]}"
    if ! PATH="$tmp/bin:$PATH" XDG_CONFIG_HOME="$ROOT" XDG_CACHE_HOME="$tmp/cache" \
        "$ROOT/$component/apply_wal_colors.sh" >/dev/null 2>&1; then
        fail "$component/apply_wal_colors.sh exits nonzero with no pywal cache"
    elif [ ! -s "$out" ]; then
        fail "$component/apply_wal_colors.sh leaves ${outputs[$component]} missing or empty"
    elif grep -q '@[a-z]*color[0-9]*@' "$out"; then
        fail "$component/apply_wal_colors.sh leaves unreplaced @color@ tokens"
    elif ! uses_palette "$out"; then
        fail "$component/apply_wal_colors.sh does not use the fallback palette"
    else
        pass "$component renders ${outputs[$component]} from the fallback palette"
    fi
done

# wal_render must substitute @color15@ before @color1@, which is its prefix.
printf '@color1@ @color15@ @oncolor0@\n' > "$tmp/template"
wal_render "$tmp/template" "$tmp/rendered"
expected="${wal[1]} ${wal[15]} $(wal_readable_on "${wal[0]}")"
if [ "$(cat "$tmp/rendered")" = "$expected" ]; then
    pass "wal_render substitutes prefix-overlapping tokens correctly"
else
    fail "wal_render produced '$(cat "$tmp/rendered")', expected '$expected'"
fi

test_summary
