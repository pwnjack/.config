#!/usr/bin/env bash

set -u

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$TEST_DIR/.." && pwd)

# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/rofi" <<'EOF'
#!/usr/bin/env bash
input=$(cat)
{
    printf 'rofi args:'
    printf ' [%s]' "$@"
    printf '\nrofi stdin: [%s]\n' "$input"
} >> "$CLIPBOARD_TEST_LOG"

count=0
[ ! -f "$CLIPBOARD_TEST_COUNT" ] || read -r count < "$CLIPBOARD_TEST_COUNT"
count=$((count + 1))
printf '%s\n' "$count" > "$CLIPBOARD_TEST_COUNT"
sed -n "${count}p" "$CLIPBOARD_TEST_ANSWERS"
EOF

cat > "$tmp/bin/cliphist" <<'EOF'
#!/usr/bin/env bash
input=$(cat)
{
    printf 'cliphist args:'
    printf ' [%s]' "$@"
    printf '\ncliphist stdin: [%s]\n' "$input"
} >> "$CLIPBOARD_TEST_LOG"

case "${1:-}" in
    list) printf '1\thello\n2\tworld\n' ;;
    decode) printf 'decoded:%s' "$input" ;;
esac
EOF

cat > "$tmp/bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
input=$(cat)
{
    printf 'wl-copy args:'
    printf ' [%s]' "$@"
    printf '\nwl-copy stdin: [%s]\n' "$input"
} >> "$CLIPBOARD_TEST_LOG"
EOF

chmod +x "$tmp/bin/rofi" "$tmp/bin/cliphist" "$tmp/bin/wl-copy"

export PATH="$tmp/bin:$PATH"
export CLIPBOARD_TEST_LOG="$tmp/log"
export CLIPBOARD_TEST_COUNT="$tmp/count"
export CLIPBOARD_TEST_ANSWERS="$tmp/answers"

entries=$(CLIPBOARD_PRINT_CLEAR=1 bash "$TEST_DIR/clipboard.sh")
clear_entry=$(printf '%s\n' "$entries" | sed -n '1p')
yes_entry=$(printf '%s\n' "$entries" | sed -n '2p')
no_entry=$(printf '%s\n' "$entries" | sed -n '3p')

run_case() {
    : > "$CLIPBOARD_TEST_LOG"
    rm -f -- "$CLIPBOARD_TEST_COUNT"
    printf '%s' "$1" > "$CLIPBOARD_TEST_ANSWERS"
    bash "$TEST_DIR/clipboard.sh"
}

history_line=$'1\thello'
run_case "$history_line"$'\n'
log=$(cat "$CLIPBOARD_TEST_LOG")
assert_contains "$log" "cliphist args: [decode]" "history selection is decoded"
assert_contains "$log" "cliphist stdin: [$history_line]" "decode receives the exact history line"
assert_contains "$log" "wl-copy args:" "decoded selection is copied"
assert_contains "$log" "wl-copy stdin: [decoded:$history_line]" "wl-copy receives the decoded selection"

run_case "$clear_entry"$'\n'"$yes_entry"$'\n'
log=$(cat "$CLIPBOARD_TEST_LOG")
assert_contains "$log" "cliphist args: [wipe]" "Yes clears clipboard history"
assert_not_contains "$log" "wl-copy args:" "clearing does not copy an entry"

run_case "$clear_entry"$'\n'"$no_entry"$'\n'
log=$(cat "$CLIPBOARD_TEST_LOG")
assert_not_contains "$log" "cliphist args: [wipe]" "No preserves clipboard history"
assert_not_contains "$log" "wl-copy args:" "No does not copy an entry"

run_case "$clear_entry"$'\n\n'
log=$(cat "$CLIPBOARD_TEST_LOG")
assert_not_contains "$log" "cliphist args: [wipe]" "confirmation Escape preserves clipboard history"
assert_not_contains "$log" "wl-copy args:" "confirmation Escape does not copy an entry"

run_case $'\n'
log=$(cat "$CLIPBOARD_TEST_LOG")
assert_contains "$log" "cliphist args: [list]" "opening the picker lists clipboard history"
assert_not_contains "$log" "cliphist args: [decode]" "Escape does not decode an entry"
assert_not_contains "$log" "cliphist args: [wipe]" "Escape does not clear history"
assert_not_contains "$log" "wl-copy args:" "Escape does not copy an entry"

test_summary "clipboard"
