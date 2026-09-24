#!/bin/bash
#
# scripts/lib/wallpaper.sh decides which image wall.sh themes from, what the
# carousel marks as current, and what login restores. Pin its choices.
#

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"
# shellcheck source=scripts/lib/wallpaper.sh
. "$ROOT/scripts/lib/wallpaper.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/options" "$tmp/awww/0.12.1"
export XDG_CONFIG_HOME="$tmp"
prefer() { printf '%s\n' "$1" > "$tmp/options/mainmonitor"; }

query=": FIXTURE-L: 1920x1080, scale: 1, currently displaying: image: /walls/left.jpg
: FIXTURE-R: 2560x1440, scale: 1, currently displaying: image: /walls/with space.jpg"

prefer ""
assert_eq "$(wallpaper_from_query "$query")" "/walls/left.jpg" \
    "no preference: the first monitor awww reports"
prefer "FIXTURE-R"
assert_eq "$(wallpaper_from_query "$query")" "/walls/with space.jpg" \
    "the preferred monitor wins, spaces in the path intact"
prefer "FIXTURE-GONE"
assert_eq "$(wallpaper_from_query "$query")" "/walls/left.jpg" \
    "a preference that is not connected falls back to the first monitor"
assert_eq "$(wallpaper_from_query $': X: no image line\n: Y: image: /walls/y.jpg')" "/walls/y.jpg" \
    "lines without an image are skipped"
assert_eq "$(wallpaper_from_query "")" "" "no monitors: empty"

# awww 0.12 cache entries are NUL-separated with no trailing newline, and only
# entries naming an existing image count.
mkdir -p "$tmp/walls"
old="$tmp/walls/old.jpg" new="$tmp/walls/new one.jpg"
touch "$old" "$new"
printf '\0crop:center\0Lanczos3\0%s' "$old" > "$tmp/awww/0.12.1/FIXTURE-L"
touch -d '2 minutes ago' "$tmp/awww/0.12.1/FIXTURE-L"
printf '\0crop:center\0Lanczos3\0%s' "$new" > "$tmp/awww/0.12.1/FIXTURE-R"

prefer ""
assert_eq "$(wallpaper_from_cache "$tmp/awww")" "$new" \
    "no preference: the newest cache entry, read from awww's binary format"
prefer "FIXTURE-L"
assert_eq "$(wallpaper_from_cache "$tmp/awww")" "$old" \
    "the preferred monitor's entry wins even when older"

# An animated wallpaper's frame cache: newest, binary, not a path.
printf '\x01\x02/\xff\xfe garbage\n/more\0junk' > "$tmp/awww/0.12.1/animation-frames"
prefer ""
assert_eq "$(wallpaper_from_cache "$tmp/awww")" "$new" \
    "a newer non-wallpaper cache file is ignored"

prefer "FIXTURE-GONE"
assert_eq "$(wallpaper_from_cache "$tmp/awww")" "" "no entry for the preferred monitor: empty"
assert_eq "$(wallpaper_from_cache "$tmp/missing")" "" "no cache directory: empty"

rm "$tmp/options/mainmonitor"
status=$(bash -ec '. "$1"; x=$(wallpaper_from_cache "$2/missing"); y=$(wallpaper_from_query ""); echo survived' \
    _ "$ROOT/scripts/lib/wallpaper.sh" "$tmp")
assert_eq "$status" "survived" "empty answers do not abort a set -e caller"

test_summary
