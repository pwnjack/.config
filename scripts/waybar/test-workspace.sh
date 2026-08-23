#!/bin/bash
# Tests for scripts/waybar/workspace.sh.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$TEST_DIR/workspace.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  ok   $1"; }
fail() {
    FAILED=$((FAILED + 1))
    echo "  FAIL $1"
    shift
    printf '       %s\n' "$@"
}

assert_field() {
    local output="$1" filter="$2" expected="$3" label="$4" actual
    actual=$(jq -r "$filter" <<< "$output" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        pass "$label"
    else
        fail "$label" "expected: $expected" "actual: $actual" "json: $output"
    fi
}

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

run_workspace() {
    WORKSPACE_DISPATCH_LOG="$TMP/dispatch" PATH="$TMP/bin:$PATH" \
        bash "$WORKSPACE" "$@"
}

echo "workspace.sh"

out=$(run_workspace status 2)
assert_field "$out" '.text' '●' "the active workspace is filled"
assert_field "$out" '.class' 'active' "the active workspace gets the highlight class"

out=$(run_workspace status 1)
assert_field "$out" '.text' '●' "an occupied inactive workspace is filled"
assert_field "$out" '.class' 'occupied' "an occupied inactive workspace is not highlighted"

out=$(run_workspace status 3)
assert_field "$out" '.text' '○' "an empty workspace is outlined"
assert_field "$out" '.class' 'empty' "an empty workspace gets the empty class"

out=$(run_workspace status 5)
assert_field "$out" '.text' '○' "a missing workspace safely renders empty"

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

echo
echo "$PASSED passed, $FAILED failed"
exit "$((FAILED > 0))"
