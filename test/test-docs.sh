#!/bin/bash
#
# Tests for the generated documentation.
#
# docs/keybindings.md is rendered from hypr/config/software/keybinds.conf. That
# only helps if a stale copy cannot be committed, which is what this suite is
# for: it lives in test/, whose owning directory is the repo root, so the
# pre-commit hook runs it on every commit -- including the commit that changes
# keybinds.conf and forgets to regenerate.
#
# Standalone and dependency-free, exit 1 on any failure, the same style as
# scripts/waybar/test-updates.sh.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TEST_DIR")"

GENERATOR="$ROOT/scripts/docs/generate-keybindings.sh"
CHEATSHEET="$ROOT/rofi/keybinds-cheatsheet.sh"
DOC="$ROOT/docs/keybindings.md"
CONF="$ROOT/hypr/config/software/keybinds.conf"

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  ok   $1"; }
fail() {
    FAILED=$((FAILED + 1))
    echo "  FAIL $1"
    shift
    printf '       %s\n' "$@"
}

# --- the generated file is current ------------------------------------------

if out=$("$GENERATOR" --check 2>&1); then
    pass "docs/keybindings.md is up to date"
else
    fail "docs/keybindings.md is out of date" \
        "run ./scripts/docs/generate-keybindings.sh and commit the result" \
        "$out"
fi

# --- the check would actually catch a stale file -----------------------------
#
# A checker that always passes is worse than none, so prove it fails. The doc is
# restored from a copy rather than regenerated, so a bug in the generator cannot
# quietly rewrite the tracked file while the suite runs.

BACKUP="$(mktemp)"
trap 'rm -f "$BACKUP"' EXIT
cp "$DOC" "$BACKUP"

printf '\n| `Super + Nonexistent` | Not a real binding |\n' >> "$DOC"
if "$GENERATOR" --check >/dev/null 2>&1; then
    fail "--check accepts a doctored file" \
        "the staleness gate does not actually gate anything"
else
    pass "--check rejects a doctored file"
fi
cp "$BACKUP" "$DOC"

# --- every binding reaches the document --------------------------------------
#
# The generator could regenerate a file that is internally consistent and still
# wrong, if the markdown renderer dropped rows. Count the bind lines the config
# declares and the key cells the document carries, and require the document to
# account for all of them. Folded rows (`Super + 1-9, 0, =`) mean the two counts
# are not equal, so this compares reachable sections instead: every `## Heading`
# in keybinds.conf that carries at least one bind must appear in the document.

missing=()
section=""
has_bind=0
# Not `cmd | while read`: the loop assigns to `missing`, which a subshell would
# discard -- the same trap the doctor's check modules document.
while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^##[[:space:]]+(.*)$ ]]; then
        if [ "$has_bind" -eq 1 ] && [ -n "$section" ]; then
            grep -qF "## $section" "$DOC" || missing+=("$section")
        fi
        section="${BASH_REMATCH[1]%"${BASH_REMATCH[1]##*[![:space:]]}"}"
        has_bind=0
        continue
    fi
    [[ "$line" =~ ^[[:space:]]*bind[a-z]*[[:space:]]*= ]] && has_bind=1
done < "$CONF"
if [ "$has_bind" -eq 1 ] && [ -n "$section" ]; then
    grep -qF "## $section" "$DOC" || missing+=("$section")
fi

if [ "${#missing[@]}" -eq 0 ]; then
    pass "every keybinds.conf section with bindings has a heading in the document"
else
    fail "sections missing from docs/keybindings.md" "${missing[@]}"
fi

# --- row count matches the runtime cheatsheet --------------------------------
#
# Both skins walk the same ORDER, so a row present in one and absent from the
# other means the markdown renderer lost something.

print_rows=$("$CHEATSHEET" --print | grep -c '^  ')
md_rows=$("$CHEATSHEET" --markdown | grep -c '^| `')
if [ "$print_rows" -eq "$md_rows" ]; then
    pass "markdown and rofi renderings agree on $md_rows rows"
else
    fail "renderings disagree on row count" \
        "--print: $print_rows rows, --markdown: $md_rows rows"
fi

# --- per-user values are not frozen into the document ------------------------
#
# options/terminal and options/browser are read at Hyprland parse time, so their
# values are this machine's. Committing them would restate the drift the
# generated document exists to prevent.

frozen=()
while IFS= read -r name; do
    value="$(head -n1 "$ROOT/options/$name" 2>/dev/null)"
    [ -n "$value" ] || continue
    grep -qF "options/$name" "$DOC" || frozen+=("$name: no reference to options/$name")
    if grep -qi "(\`\?$value\`\?)" "$DOC"; then
        frozen+=("$name: the document names '$value' instead of options/$name")
    fi
done < <(printf '%s\n' terminal browser)

if [ "${#frozen[@]}" -eq 0 ]; then
    pass "options-backed values are named by file, not by this machine's answer"
else
    fail "per-user values leaked into the document" "${frozen[@]}"
fi

# --- summary -----------------------------------------------------------------

echo
echo "  $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
