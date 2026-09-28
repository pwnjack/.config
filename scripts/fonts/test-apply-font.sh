#!/bin/bash
# apply-font.sh writes the GTK font to gsettings as well as settings.ini.
set -euo pipefail
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/assert.sh"

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/apply-font.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.config/options" "$tmp/.config/rofi/options" "$tmp/.config/gtk-3.0" "$tmp/bin"
echo "Main Font" > "$tmp/.config/options/font"
echo "Gtk Font" > "$tmp/.config/options/font-gtk"
printf '[Settings]\ngtk-font-name=Old 12 @wght=600\n' > "$tmp/.config/gtk-3.0/settings.ini"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gsettings.log"\n' "$tmp" > "$tmp/bin/gsettings"
chmod +x "$tmp/bin/gsettings"

HOME="$tmp" PATH="$tmp/bin:$PATH" bash "$script" >/dev/null
assert_eq "$(cat "$tmp/gsettings.log")" "set org.gnome.desktop.interface font-name Gtk Font 12 @wght=600" \
    "the GTK font, size and weight reach gsettings"

printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/gsettings"
if HOME="$tmp" PATH="$tmp/bin:$PATH" bash "$script" >/dev/null 2>&1; then
    fail "a failed gsettings write must fail the script"
else
    pass "a failed gsettings write fails the script"
fi
test_summary
