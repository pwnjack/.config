#!/bin/bash
#
# Render the starship prompt config with the pywal palette substituted in.
#
# starship has no include mechanism and no way to point one config at another,
# so the whole file is templated: starship/starship.toml.in holds the real
# content with @colorN@ / @oncolorN@ tokens, and ~/.config/starship.toml is a
# symlink to the copy rendered here. No tracked file changes at runtime.
#
# There is nothing to reload — starship re-reads its config on every prompt,
# so an open shell picks up a new wallpaper's colors at the next prompt.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
template="$config_dir/starship/starship.toml.in"
rendered="$cache_dir/starship.toml"

[ -r "$template" ] || exit 0

declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
. "$config_dir/scripts/theming/palette.sh"
wal_load

mkdir -p "$cache_dir"

# Highest index first: @color1@ is a prefix of @color15@, so substituting it
# first would leave a stray "5" behind.
sed_args=()
for i in 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0; do
    sed_args+=(-e "s|@color$i@|${wal[$i]}|g")
    sed_args+=(-e "s|@oncolor$i@|$(wal_readable_on "${wal[$i]}")|g")
done

sed "${sed_args[@]}" "$template" > "$rendered"

exit 0
