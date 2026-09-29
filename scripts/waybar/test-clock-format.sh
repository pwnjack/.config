#!/bin/bash
set -euo pipefail
script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/clock-format.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
run() { CLOCK_OPTION="$tmp/clock" CLOCK_INCLUDE="$tmp/out/clock.jsonc" bash "$script" --no-reload; cat "$tmp/out/clock.jsonc"; }
[[ $(run) == '{ "clock": { "format": "{:%H:%M}" } }' ]] || { echo 'missing option should render 24 h' >&2; exit 1; }
printf '12h\n' > "$tmp/clock"
[[ $(run) == '{ "clock": { "format": "{:%I:%M %p}" } }' ]] || { echo '12h not rendered' >&2; exit 1; }
echo 'ok: 12h renders the 12-hour format'
printf 'banana\n' > "$tmp/clock"
[[ $(run) == '{ "clock": { "format": "{:%H:%M}" } }' ]] || { echo 'garbage should fall back to 24 h' >&2; exit 1; }
echo 'ok: anything else falls back to 24 h'
[[ -z $(find "$tmp/out" -name 'clock.jsonc.*') ]] || { echo 'temporary file left behind' >&2; exit 1; }
echo 'ok: output always exists and no temporary file is left'
