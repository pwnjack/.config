#!/bin/bash
#
# Render cava's config with the pywal palette substituted in.
#
# cava has a theme mechanism (`theme = '<name>'` reading ~/.config/cava/themes),
# which would have been the natural fit here. It is unusable: cava 0.10.7
# corrupts the heap and aborts with "free(): invalid next size" on any vertical
# `gradient`, in a theme file or in the main config, at every stop count.
# Its own bundled themes/solarized_dark crashes it the same way, so this is
# upstream. horizontal_gradient is unaffected and is what the template uses.
#
# So the whole config is templated instead: cava/config.in holds the real
# content with @colorN@ tokens, and cava/config is a symlink to the rendered
# copy in the cache. No tracked file changes at runtime.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
template="$config_dir/cava/config.in"
rendered="$cache_dir/cava-config"

[ -r "$template" ] || exit 0

declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
. "$config_dir/scripts/theming/palette.sh"
wal_load

mkdir -p "$cache_dir"

# Highest index first: substituting @color1@ before @color15@ would leave a
# stray "5" behind, since @color1@ is a prefix of @color15@.
sed_args=()
for i in 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0; do
    sed_args+=(-e "s|@color$i@|${wal[$i]}|g")
done

sed "${sed_args[@]}" "$template" > "$rendered"

# Colors-only reload for any running cava. SIGUSR1 would reload the whole
# config, which also reinitialises audio capture.
pkill -USR2 -x cava 2>/dev/null

exit 0
