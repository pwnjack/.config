#!/bin/bash
#
# Tests for scripts/hyprland/screenshot.sh. hyprshot, swappy, sleep and
# hyprctl are fakes on PATH that append to one event log, so the order of
# delay and capture is visible and no real screenshot is ever taken.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHOT="$TEST_DIR/screenshot.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

mkdir -p "$TMP/bin" "$TMP/home/.config/options"
export EVENTS="$TMP/events"
cat > "$TMP/bin/hyprshot" <<'EOF'
#!/bin/bash
printf 'hyprshot %s\n' "$*" >> "$EVENTS"
[[ " $* " == *" --raw "* ]] && printf 'PNG'
exit 0
EOF
cat > "$TMP/bin/swappy" <<'EOF'
#!/bin/bash
printf 'swappy %s stdin=%s\n' "$*" "$(cat)" >> "$EVENTS"
EOF
cat > "$TMP/bin/sleep" <<'EOF'
#!/bin/bash
printf 'sleep %s\n' "$*" >> "$EVENTS"
EOF
cat > "$TMP/bin/hyprctl" <<'EOF'
#!/bin/bash
[ "$*" = 'monitors -j' ] && echo '[{"name":"TEST-2","focused":false},{"name":"TEST-1","focused":true}]'
EOF
chmod +x "$TMP/bin/"*

shot() {
    : > "$EVENTS"
    HOME="$TMP/home" PATH="$TMP/bin:$PATH" bash "$SHOT" "$@"
}
freeze() { printf '%s\n' "$1" > "$TMP/home/.config/options/capture-freeze"; }

freeze false
shot region
if [[ $(cat "$EVENTS") =~ ^hyprshot\ -m\ region\ -o\ $TMP/home/Pictures/Screenshots\ -f\ Screenshot_[0-9-]+_[0-9:]+\.png$ ]]; then
    pass "region writes to ~/Pictures/Screenshots"
else
    fail "region argv" "$(cat "$EVENTS")"
fi

freeze true
shot region
assert_contains "$(cat "$EVENTS")" " -z" "capture-freeze true freezes"

freeze false
old=screenshot   # the pre-rename option file
printf 'true\n' > "$TMP/home/.config/options/$old"
shot region
case "$(cat "$EVENTS")" in *" -z"*) fail "the pre-rename option file is ignored" ;; *) pass "the pre-rename option file is ignored" ;; esac

shot screen
assert_contains "$(cat "$EVENTS")" "hyprshot -m output -m TEST-1 " "screen is the focused monitor"
freeze true
shot screen
case "$(cat "$EVENTS")" in *" -z"*) fail "screen never freezes" ;; *) pass "screen never freezes" ;; esac
freeze false
shot region --delay 08
assert_eq "$(head -n1 "$EVENTS")" "sleep 8" "a zero-padded delay is decimal"
shot region --delay 0
case "$(cat "$EVENTS")" in sleep*) fail "delay 0 does not sleep" ;; *) pass "delay 0 does not sleep" ;; esac
shot window
assert_contains "$(cat "$EVENTS")" "hyprshot -m window " "window target"

shot region --annotate
assert_eq "$(cat "$EVENTS")" $'hyprshot -m region --raw\nswappy -f - stdin=PNG' "annotate pipes the raw PNG to swappy"

shot screen --annotate --delay 3
assert_eq "$(head -n1 "$EVENTS")" "sleep 3" "the delay runs first"
assert_contains "$(sed -n 2p "$EVENTS")" "hyprshot -m output -m TEST-1 --raw" "then the capture"

shot region
case "$(cat "$EVENTS")" in sleep*) fail "no delay by default" ;; *) pass "no delay by default" ;; esac

for bad in "bogus" "region --delay x" "region --frobnicate"; do
    # shellcheck disable=SC2086
    shot $bad 2>/dev/null; rc=$?
    assert_eq "$rc" 2 "usage error: $bad"
done

test_summary screenshot
