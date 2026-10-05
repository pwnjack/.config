#!/bin/bash
#
# Tests for scripts/waybar/build-workspaces.sh. WORKSPACES_LIB and
# WORKSPACES_INCLUDE point the outputs into a temp dir. The inode is the
# rebuild signal: a rename into place always gives the library a new one.
# WORKSPACES_SRC points a copy of the sources at the script for edit scenarios.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/build-workspaces.sh"
REPO="$(cd "$TEST_DIR/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

echo "build-workspaces.sh"

lib="$TMP/lib/workspaces.so"
include="$TMP/state/workspaces.jsonc"
# XDG_RUNTIME_DIR points into $TMP so the build-directory assertions look where
# the script actually creates it.
run() { XDG_RUNTIME_DIR="$TMP" WORKSPACES_LIB="$lib" WORKSPACES_INCLUDE="$include" bash "$SCRIPT"; }

before="$(git -C "$REPO" status --porcelain --untracked-files=all)"

if run; then pass "the first run succeeds"; else fail "the first run succeeds"; fi
if [ -f "$lib" ]; then pass "the library is installed"; else fail "the library is installed"; fi
assert_eq "$(stat -c %a "$lib")" "755" "the library is world-readable and executable"
assert_eq "$(jq -c . "$include")" \
    "{\"cffi/workspaces\":{\"module_path\":\"$lib\",\"source\":\"$REPO/waybar/workspaces\"}}" \
    "the include names the library and its sources"

inode="$(stat -c %i "$lib")"
run >/dev/null
assert_eq "$(stat -c %i "$lib")" "$inode" "an up-to-date library is not rebuilt"

assert_eq "$(cat "$lib.sha256" | wc -l)" "1" "the content stamp is stored beside the library"
rm -f "$lib.sha256"
inode="$(stat -c %i "$lib")"
run >/dev/null
if [ "$(stat -c %i "$lib")" != "$inode" ]; then
    pass "a library without a stamp is rebuilt and renamed into place"
else
    fail "a library without a stamp is rebuilt and renamed into place"
fi
assert_eq "$(stat -c %a "$lib")" "755" "the library is still executable after a rebuild"

# A copied source tree stands in for edits: the script reads it via WORKSPACES_SRC.
SRC="$TMP/src"
cp -r "$REPO/waybar/workspaces" "$SRC"
lib2="$TMP/lib2/workspaces.so"
include2="$TMP/state2/workspaces.jsonc"
run2() {
    XDG_RUNTIME_DIR="$TMP" WORKSPACES_SRC="$SRC" WORKSPACES_LIB="$lib2" WORKSPACES_INCLUDE="$include2" bash "$SCRIPT" "$@"
}

out="$(run2)"
assert_eq "$out" "build-workspaces: installed $lib2; restart Waybar to load it" \
    "an install announces itself and says to restart Waybar"
assert_eq "$(run2)" "" "an up-to-date run prints nothing"
assert_eq "$(find "$TMP" -maxdepth 1 -name 'workspaces-build.*' | wc -l)" "0" \
    "the build directory is removed"

if run2 --check >/dev/null; then pass "--check succeeds right after an install"; else fail "--check succeeds right after an install"; fi

listing() { find "$TMP" -printf '%p %i %T@ %s\n' | sort; }
rm -f "$lib2.sha256"
snap="$(listing)"
out="$(run2 --check)"
rc=$?
assert_eq "$rc" "1" "--check fails without a stamp"
assert_eq "$(printf '%s\n' "$out" | wc -l)" "1" "--check prints one line"
assert_eq "$(listing)" "$snap" "--check creates and modifies nothing"
run2 >/dev/null

# An older-mtime edit: content changes, mtime goes backwards.
inode="$(stat -c %i "$lib2")"
echo '/* edit */' >> "$SRC/model.h"
touch -d '2000-01-01' "$SRC/model.h"
if run2 --check >/dev/null; then fail "--check fails when a source differs"; else pass "--check fails when a source differs"; fi
run2 >/dev/null
if [ "$(stat -c %i "$lib2")" != "$inode" ]; then
    pass "an edit with an older mtime triggers a rebuild"
else
    fail "an edit with an older mtime triggers a rebuild"
fi
assert_eq "$(stat -c %a "$lib2")" "755" "the mode is 755 after a rebuild"

# A deleted source (unused header) triggers a rebuild too.
echo '/* extra */' > "$SRC/extra.h"
run2 >/dev/null
inode="$(stat -c %i "$lib2")"
rm "$SRC/extra.h"
run2 >/dev/null
if [ "$(stat -c %i "$lib2")" != "$inode" ]; then
    pass "a deleted source triggers a rebuild"
else
    fail "a deleted source triggers a rebuild"
fi

# A failed build leaves the installed library untouched.
inode="$(stat -c %i "$lib2")"
echo 'this is not C' >> "$SRC/model.c"
if run2 >/dev/null 2>&1; then rc=0; else rc=$?; fi
if [ "$rc" != 0 ]; then pass "a failed build exits non-zero"; else fail "a failed build exits non-zero"; fi
assert_eq "$(stat -c %i "$lib2")" "$inode" "a failed build keeps the old library"
assert_eq "$(find "$TMP" \( -name 'workspaces.so.*' -o -name 'workspaces.jsonc.*' -o -name 'workspaces-build.*' \) \
    ! -name workspaces.so.sha256 ! -name workspaces.so.lock | wc -l)" "0" "a failed build leaves no temporary file"

# Paths must be absolute.
out="$(WORKSPACES_LIB=relative.so WORKSPACES_INCLUDE="$include" bash "$SCRIPT" 2>&1)"
rc=$?
assert_eq "$rc" "1" "a relative WORKSPACES_LIB exits 1"
case "$out" in
    *WORKSPACES_LIB*absolute*) pass "a relative WORKSPACES_LIB says why" ;;
    *) fail "a relative WORKSPACES_LIB says why" ;;
esac
if WORKSPACES_SRC="$TMP/nowhere" WORKSPACES_LIB="$lib" WORKSPACES_INCLUDE="$include" bash "$SCRIPT" >/dev/null 2>&1; then
    fail "a missing Makefile exits 1"
else
    pass "a missing Makefile exits 1"
fi

assert_eq "$(find "$TMP" \( -name 'workspaces.so.*' -o -name 'workspaces.jsonc.*' \) \
    ! -name workspaces.so.sha256 ! -name workspaces.so.lock | wc -l)" "0" "no temporary file is left behind"
assert_eq "$(git -C "$REPO" status --porcelain --untracked-files=all)" "$before" \
    "nothing is written inside the repository"

test_summary
