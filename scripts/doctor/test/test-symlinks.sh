# Tests for scripts/doctor/checks/symlinks.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/symlinks.sh"

sym_saved_root="$DOCTOR_ROOT"

# --- a repo containing every symlink state the check classifies ---
sym_fixture="$(make_fixture)"

mkdir -p "$sym_fixture/target-dir" "$sym_fixture/sub"
echo "real" > "$sym_fixture/target-dir/real-file"

# healthy: relative, resolves to a file
ln -s "../target-dir/real-file" "$sym_fixture/sub/good-relative"
# healthy: relative, resolves to a directory
ln -s "../target-dir" "$sym_fixture/sub/good-dir-link"
# error: relative target does not exist
ln -s "../target-dir/nonexistent" "$sym_fixture/sub/relative-dangling"
# error: absolute AND dangling — reported as dangling, not as non-portable
ln -s "/home/someone/nowhere/missing-file" "$sym_fixture/sub/absolute-dangling"
# warn: absolute but resolving. The fixture lives under $TMPDIR, so this is the
# general "absolute target" case rather than a literal /home/... one.
ln -s "$sym_fixture/target-dir/real-file" "$sym_fixture/sub/absolute-resolving"
# error: git has it as a symlink, the working tree has a regular file
ln -s "../target-dir/real-file" "$sym_fixture/sub/clobbered-by-file"
# error: git has it as a symlink, the working tree has nothing
ln -s "../target-dir/real-file" "$sym_fixture/sub/deleted-entirely"

git -C "$sym_fixture" add -A
git -C "$sym_fixture" commit -qm "fixture"

# Break the last two only after committing, so the index still records mode
# 120000 for them — the index is what the check derives its list from.
rm "$sym_fixture/sub/clobbered-by-file"
echo "not a link" > "$sym_fixture/sub/clobbered-by-file"
rm "$sym_fixture/sub/deleted-entirely"

DOCTOR_ROOT="$sym_fixture"

doctor_reset
sym_out="$(check_symlinks 2>&1)"
# The call above ran in a command substitution, so its increments were lost
# with the subshell. Re-run in this shell to observe the counters.
doctor_reset
check_symlinks >/dev/null 2>&1

assert_contains "$sym_out" "relative-dangling" "dangling relative symlink is reported"
assert_contains "$sym_out" "ERROR" "dangling symlink is ERROR severity"
assert_contains "$sym_out" "absolute-dangling" "dangling absolute symlink is reported"
assert_contains "$sym_out" "absolute-resolving" "absolute-but-resolving symlink is reported"
assert_contains "$sym_out" "WARN" "absolute symlink is WARN severity"
assert_contains "$sym_out" "clobbered-by-file" "symlink replaced by a regular file is reported"
assert_contains "$sym_out" "deleted-entirely" "symlink missing from the working tree is reported"
assert_not_contains "$sym_out" "good-relative" "healthy relative symlink produces no finding"
assert_not_contains "$sym_out" "good-dir-link" "healthy symlink to a directory produces no finding"
assert_contains "$sym_out" "2 of 7 tracked symlinks" "ok line reports the healthy count"

# absolute-dangling is both absolute and broken; the if/elif reports it as
# dangling only, so it lands in the error tally rather than the warning one.
assert_eq "$DOCTOR_ERRORS" "4" "dangling, clobbered and missing symlinks counted as errors"
assert_eq "$DOCTOR_WARNINGS" "1" "one absolute resolving symlink counted as warning"

# The fix hint for a non-portable link is the relative target to use instead.
assert_contains "$sym_out" "../target-dir/real-file" "non-portable link is given a relative fix"

# --- a /home/... target is WARN, matching the live rofi/colors.rasi finding ---
# Needs a real existing path under /home to resolve; if this machine has no
# /home entries the general absolute case above already covers the branch.
sym_home_target=""
for sym_home_candidate in /home/*; do
    if [ -e "$sym_home_candidate" ]; then
        sym_home_target="$sym_home_candidate"
        break
    fi
done

if [ -n "$sym_home_target" ]; then
    sym_home_fixture="$(make_fixture)"
    ln -s "$sym_home_target" "$sym_home_fixture/home-absolute"
    git -C "$sym_home_fixture" add -A
    git -C "$sym_home_fixture" commit -qm "fixture"

    DOCTOR_ROOT="$sym_home_fixture"
    doctor_reset
    sym_home_out="$(check_symlinks 2>&1)"
    doctor_reset
    check_symlinks >/dev/null 2>&1

    assert_contains "$sym_home_out" "home-absolute" "symlink into /home is reported"
    assert_contains "$sym_home_out" "WARN" "symlink into /home is WARN severity"
    assert_eq "$DOCTOR_WARNINGS" "1" "symlink into /home counted as a warning"
    assert_eq "$DOCTOR_ERRORS" "0" "resolving /home symlink is not an error"
fi

# --- paths git would C-quote must still be read back verbatim ---
# `git ls-files -s` renders a path containing a quote or a non-ASCII byte as a
# C-style quoted string, which no longer names a file on disk. Reading the list
# NUL-delimited avoids that; without it these two links look dangling.
sym_quote_fixture="$(make_fixture)"
echo "real" > "$sym_quote_fixture/real-file"
ln -s "real-file" "$sym_quote_fixture/spaced link"
ln -s "real-file" "$sym_quote_fixture/ünicode-lïnk"
git -C "$sym_quote_fixture" add -A
git -C "$sym_quote_fixture" commit -qm "fixture"

DOCTOR_ROOT="$sym_quote_fixture"
doctor_reset
sym_quote_out="$(check_symlinks 2>&1)"
doctor_reset
check_symlinks >/dev/null 2>&1

assert_contains "$sym_quote_out" "2 of 2 tracked symlinks" "quoted-path symlinks read back as healthy"
assert_eq "$DOCTOR_ERRORS" "0" "quoted paths are not mistaken for dangling links"

# --- a repo with no tracked symlinks at all ---
sym_bare_fixture="$(make_fixture)"
echo "plain" > "$sym_bare_fixture/regular-file"
git -C "$sym_bare_fixture" add -A
git -C "$sym_bare_fixture" commit -qm "fixture"

DOCTOR_ROOT="$sym_bare_fixture"
doctor_reset
sym_bare_out="$(check_symlinks 2>&1)"
doctor_reset
check_symlinks >/dev/null 2>&1

assert_contains "$sym_bare_out" "no tracked symlinks found" "repo without symlinks warns"
assert_not_contains "$sym_bare_out" "tracked symlinks are healthy" "no ok line without symlinks"
assert_eq "$DOCTOR_WARNINGS" "1" "empty symlink list counted as a warning"

# --- a DOCTOR_ROOT that is not a git repository ---
DOCTOR_ROOT="$sym_saved_root"
doctor_reset
sym_nogit_out="$(check_symlinks 2>&1)"
assert_contains "$sym_nogit_out" "no tracked symlinks found" "non-repo root warns instead of crashing"
assert_not_contains "$sym_nogit_out" "fatal" "git's own error is not leaked to the report"

DOCTOR_ROOT="$sym_saved_root"
