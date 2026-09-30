#!/bin/bash
set -euo pipefail
script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/clock-format.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
run() { CLOCK_OPTION="$tmp/clock" CLOCK_INCLUDE="$tmp/out/clock.jsonc" bash "$script" --no-reload; cat "$tmp/out/clock.jsonc"; }
[[ $(run) == '{ "clock": { "format": "{:L%a %d  %H:%M}" } }' ]] || { echo 'missing option should render 24 h' >&2; exit 1; }
printf '12h\n' > "$tmp/clock"
[[ $(run) == '{ "clock": { "format": "{:L%a %d  %I:%M %p}" } }' ]] || { echo '12h not rendered' >&2; exit 1; }
echo 'ok: 12h renders the 12-hour format'
printf 'banana\n' > "$tmp/clock"
[[ $(run) == '{ "clock": { "format": "{:L%a %d  %H:%M}" } }' ]] || { echo 'garbage should fall back to 24 h' >&2; exit 1; }
echo 'ok: anything else falls back to 24 h'
[[ -z $(find "$tmp/out" -name 'clock.jsonc.*') ]] || { echo 'temporary file left behind' >&2; exit 1; }
echo 'ok: output always exists and no temporary file is left'

# The reload path: pkill runs exactly when --no-reload is absent.
mkdir -p "$tmp/bin"
printf '#!/bin/bash\necho "$*" >> "%s/pkill.log"\n' "$tmp" > "$tmp/bin/pkill"
chmod +x "$tmp/bin/pkill"
PATH="$tmp/bin:$PATH" CLOCK_OPTION="$tmp/clock" CLOCK_INCLUDE="$tmp/out/clock.jsonc" bash "$script" --no-reload
[[ ! -e $tmp/pkill.log ]] || { echo '--no-reload must not signal Waybar' >&2; exit 1; }
PATH="$tmp/bin:$PATH" CLOCK_OPTION="$tmp/clock" CLOCK_INCLUDE="$tmp/out/clock.jsonc" bash "$script"
[[ $(<"$tmp/pkill.log") == '-USR2 -x waybar' ]] || { echo 'a render must signal Waybar once' >&2; exit 1; }
echo 'ok: Waybar is signalled only without --no-reload'

# The main config must not set clock.format (it would win over the include key by
# key), and its include must be the path this script writes by default.
config="$(dirname "$script")/../../waybar/config.jsonc"
clock_block=$(sed -n '/^  "clock": {/,/^  },/p' "$config")
if grep -Eq '^    "format":' <<< "$clock_block"; then echo 'waybar/config.jsonc must not set clock.format' >&2; exit 1; fi
grep -Fq '"include": ["~/.local/state/waybar/clock.jsonc"]' "$config" || { echo 'waybar/config.jsonc must include ~/.local/state/waybar/clock.jsonc' >&2; exit 1; }
# shellcheck disable=SC2016 # the literal $HOME text is what is being checked
grep -Fq 'include=$HOME/.local/state/waybar/clock.jsonc' "$script" || { echo 'clock-format.sh must default to the include config.jsonc names' >&2; exit 1; }
echo 'ok: the main config leaves the format to the include it names'
