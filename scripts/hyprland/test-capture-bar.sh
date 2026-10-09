#!/bin/bash
#
# Tests for scripts/hyprland/capture-bar.sh: Super+Shift+R stops a running
# recording instead of opening the strip, and otherwise the launcher asks a
# running strip over IPC before starting one. qs, notify-send and record.sh
# are fakes; XDG_CONFIG_HOME is a fixture tree.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TEST_DIR/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"

config="$TMP/config"
mkdir -p "$config/scripts/capture" "$config/scripts/theming" "$config/quickshell/capture" "$config/options" "$TMP/bin"
ln -s "$ROOT/scripts/theming/palette.sh" "$config/scripts/theming/palette.sh"
: > "$config/quickshell/capture/shell.qml"
export LOG="$TMP/log"
cat > "$config/scripts/capture/record.sh" <<'EOF'
#!/bin/bash
printf 'record %s\n' "$*" >> "$LOG"
[ "$1" = status ] && [ -e "$LOG.recording" ] && exit 0
[ "$1" = status ] && exit 1
exit 0
EOF
cat > "$TMP/bin/qs" <<'EOF'
#!/bin/bash
printf 'qs %s mode=%s\n' "$*" "${CAPTURE_MODE-}" >> "$LOG"
case "$*" in
    *"ipc call capture toggle"*) exit 1 ;;   # nothing running yet
    *"ipc call capture ping"*) exit 0 ;;
esac
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' > "$TMP/bin/notify-send"
printf '#!/bin/bash\necho "{\\"x\\":0}"\n' > "$TMP/bin/hyprctl"
chmod +x "$config/scripts/capture/record.sh" "$TMP/bin/"*

launch() {
    : > "$LOG"
    XDG_CONFIG_HOME="$config" XDG_CACHE_HOME="$TMP/cache" PATH="$TMP/bin:$PATH" \
        bash "$TEST_DIR/capture-bar.sh" "$@"
}

touch "$LOG.recording"
launch record
assert_contains "$(cat "$LOG")" "record stop" "record while recording stops it"
case "$(cat "$LOG")" in *"qs "*) fail "record while recording never opens the strip" ;; *) pass "record while recording never opens the strip" ;; esac

launch screenshot
assert_contains "$(cat "$LOG")" "ipc call capture toggle screenshot" "screenshot while recording opens the strip"

rm -f "$LOG.recording"
launch record
assert_contains "$(cat "$LOG")" "ipc call capture toggle record" "asks a running strip first"
assert_contains "$(cat "$LOG")" "--daemonize mode=record" "starts the strip on the Record tab"

launch bogus 2>/dev/null; rc=$?
assert_eq "$rc" 2 "a bad mode is a usage error"

test_summary capture-bar
