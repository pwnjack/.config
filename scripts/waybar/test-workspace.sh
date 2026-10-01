#!/bin/bash
# Tests for scripts/waybar/workspace.sh.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$TEST_DIR/workspace.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/hyprctl" <<'EOF'
#!/bin/bash
case "$1" in
    workspaces)
        printf '%s\n' '[{"id":1,"windows":2},{"id":2,"windows":1},{"id":3,"windows":0}]'
        ;;
    activeworkspace)
        printf '%s\n' '{"id":2}'
        ;;
    dispatch)
        printf '%s\n' "$2" > "$WORKSPACE_DISPATCH_LOG"
        printf 'ok\n'
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/hyprctl"

mkdir -p "$TMP/opt"
run_workspace() {
    BAR_OPTIONS="$TMP/opt" WORKSPACE_DISPATCH_LOG="$TMP/dispatch" \
        PATH="$TMP/bin:$PATH" bash "$WORKSPACE" "$@"
}

echo "workspace.sh"

out=$(run_workspace status 2)
assert_json_field "$out" '.text' '●' "the active workspace is filled"
assert_json_field "$out" '.class' 'active' "the active workspace gets the highlight class"

out=$(run_workspace status 1)
assert_json_field "$out" '.text' '●' "an occupied inactive workspace is filled"
assert_json_field "$out" '.class' 'occupied' "an occupied inactive workspace is not highlighted"

out=$(run_workspace status 3)
assert_json_field "$out" '.text' '○' "an empty workspace is outlined"
assert_json_field "$out" '.class' 'empty' "an empty workspace gets the empty class"

out=$(run_workspace status 5)
assert_json_field "$out" '.text' '○' "a missing workspace safely renders empty"

out=$(run_workspace status-existing 3)
assert_json_field "$out" '.text' '○' "an existing optional workspace is rendered"

out=$(run_workspace status-existing 5)
assert_json_field "$out" '.text' '' "a missing optional workspace is hidden"

# options/bar-workspaces: numbers swaps the glyph and adds the numbers class;
# anything else keeps the dots with a single state class.
printf 'numbers\n' > "$TMP/opt/bar-workspaces"
out=$(run_workspace status 2)
assert_json_field "$out" '.text' '2' "numbers mode shows the workspace number"
assert_json_field "$out" '.class | join(" ")' 'active numbers' "numbers mode keeps the state class and adds numbers"
out=$(run_workspace status 3)
assert_json_field "$out" '.text' '3' "an empty workspace still shows its number"
assert_json_field "$out" '.class | join(" ")' 'empty numbers' "an empty number keeps the empty class for dimming"
out=$(run_workspace status-existing 5)
assert_json_field "$out" '.text' '' "numbers mode still hides a missing optional workspace"

printf 'banana\n' > "$TMP/opt/bar-workspaces"
out=$(run_workspace status 1)
assert_json_field "$out" '.text' '●' "an unknown mode falls back to dots"
assert_json_field "$out" '.class' 'occupied' "the dots keep a single state class"
rm -f "$TMP/opt/bar-workspaces"

run_workspace switch 4 >/dev/null
if [ "$(<"$TMP/dispatch")" = 'hl.dsp.focus({ workspace = 4 })' ]; then
    pass "clicks use the Lua-compatible workspace dispatcher"
else
    fail "clicks use the Lua-compatible workspace dispatcher" \
        "got: $(<"$TMP/dispatch")"
fi

run_workspace previous >/dev/null
if [ "$(<"$TMP/dispatch")" = 'hl.dsp.focus({ workspace = "r-1" })' ]; then
    pass "scroll up uses the Lua-compatible previous-workspace dispatcher"
else
    fail "scroll up uses the Lua-compatible previous-workspace dispatcher" \
        "got: $(<"$TMP/dispatch")"
fi

run_workspace next >/dev/null
if [ "$(<"$TMP/dispatch")" = 'hl.dsp.focus({ workspace = "r+1" })' ]; then
    pass "scroll down uses the Lua-compatible next-workspace dispatcher"
else
    fail "scroll down uses the Lua-compatible next-workspace dispatcher" \
        "got: $(<"$TMP/dispatch")"
fi

if run_workspace status '4); os.execute("false")' >/dev/null 2>&1; then
    fail "non-numeric workspace IDs are rejected"
else
    pass "non-numeric workspace IDs are rejected"
fi

test_summary
