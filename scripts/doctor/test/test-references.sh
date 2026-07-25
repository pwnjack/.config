# Tests for scripts/doctor/checks/references.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash
#
# Checks are run ONCE, redirected to a file under $DOCTOR_TEST_TMP, and the
# output is read back. `out="$(check_x)"` would run the check in a subshell and
# discard its severity counters, forcing a second run to observe them — so the
# asserted text and the asserted counts would come from different executions.
#
# Every variable here is prefixed ref_ : test files share one shell.

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/references.sh"

# Assigned throughout this file but read only by the check sourced above — a
# cross-file use that SC2034 cannot see. Declare them external.
export DOCTOR_ROOT DOCTOR_CACHE

ref_out_file="$DOCTOR_TEST_TMP/references.out"

# =====================================================================
# A repo containing every reference state the check classifies.
# =====================================================================
ref_fixture="$(make_fixture)"

mkdir -p "$ref_fixture/hypr/config/spaced dir" \
         "$ref_fixture/scripts/hyprland" \
         "$ref_fixture/docs"

# --- Hyprland source chains -------------------------------------------------
# Heredocs are quoted so $HOME and $VARIABLE reach the fixture literally.
cat > "$ref_fixture/hypr/hyprland.conf" <<'EOF'
# main manifest
source = config/good.conf
source = config/missing.conf
source = config/inline.conf     # trailing comment must not become part of the path
source = config/spaced dir/there.conf
source = config/spaced dir/gone.conf
source = $VARIABLE/expanded.conf
source = config/*.conf
source = ~/.config/hypr/config/good.conf
source = /etc/hypr/absolute.conf
EOF

# Sources are resolved against the sourcing file's own directory, not against a
# hardcoded hypr/. This file proves the base is derived, not assumed.
cat > "$ref_fixture/hypr/hyprlock.conf" <<'EOF'
source = config/lock-missing.conf
EOF

# A conf at the top of the tree: its base directory is empty, so a naive
# "$root/$base/$target" would build a path containing a doubled slash.
cat > "$ref_fixture/top.conf" <<'EOF'
source = toplevel-target.conf
EOF

echo "colors" > "$ref_fixture/hypr/config/good.conf"
echo "inline" > "$ref_fixture/hypr/config/inline.conf"
echo "spaced" > "$ref_fixture/hypr/config/spaced dir/there.conf"

# --- literal ~/.config references -------------------------------------------
# docs/ and *.md cite illustrative paths that intentionally do not exist.
cat > "$ref_fixture/docs/plan.md" <<'EOF'
Illustrative: $HOME/.config/docs-md/never-exists
EOF
cat > "$ref_fixture/docs/notes.txt" <<'EOF'
Illustrative: $HOME/.config/docs-txt/never-exists
EOF
cat > "$ref_fixture/NOTES.md" <<'EOF'
Illustrative: ~/.config/md-only/never-exists
EOF

cat > "$ref_fixture/scripts/broken.sh" <<'EOF'
exec "$HOME/.config/gone/missing.sh"
EOF

# The referencing file's name is interpolated into a fix hint, so it needs a
# space in it to prove the hint is shell-quoted.
cat > "$ref_fixture/has space.sh" <<'EOF'
exec "$HOME/.config/gone/missing2.sh"
EOF

# Paths that are still templates or globs at rest: nothing on disk can be
# expected to match them, so they must be skipped rather than reported.
cat > "$ref_fixture/scripts/dynamic.sh" <<'EOF'
theme="$HOME/.config/themes/$NAME/x.rasi"
all=(~/.config/themes/*.rasi)
one=~/.config/themes/?.rasi
set=~/.config/themes/[ab].rasi
EOF

# The prefix strip must remove only the LEADING ~/.config/, never the last one.
cat > "$ref_fixture/nested.sh" <<'EOF'
p="$HOME/.config/scripts/x/.config/y"
EOF

cat > "$ref_fixture/present.sh" <<'EOF'
p="$HOME/.config/present.sh"
EOF

# --- wall.sh colour fan-out -------------------------------------------------
# The optional list is taken from the `for ... in ... ; do` header, so the
# waybar entry — which is not an apply_wal_colors.sh — must be WARN too. The
# reference outside the loop is not existence-guarded, so it stays an ERROR.
cat > "$ref_fixture/scripts/hyprland/wall.sh" <<'EOF'
#!/bin/bash
for script in \
    "$HOME/.config/ghostty/apply_wal_colors.sh" \
    "$HOME/.config/mako/apply_wal_colors.sh" \
    "$HOME/.config/scripts/waybar/waybar.sh"; do
    [ -x "$script" ] && "$script" &
done
"$HOME/.config/gone/wall-hard-ref.sh"
EOF

# --- a tracked symlink whose content is generated outside the repo ----------
# waypaper rewrites its own config in ~/.cache; a dangling reference inside it
# is not something an edit to this repo could fix.
ref_generated="$DOCTOR_TEST_TMP/ref-generated-content"
cat > "$ref_generated" <<'EOF'
stylesheet = ~/.config/generated/never-exists.css
EOF
ln -s "$ref_generated" "$ref_fixture/generated.ini"

git -C "$ref_fixture" add -A
git -C "$ref_fixture" commit -qm "fixture"

ref_cache_empty="$DOCTOR_TEST_TMP/ref-cache-empty"
mkdir -p "$ref_cache_empty"

DOCTOR_ROOT="$ref_fixture"
DOCTOR_CACHE="$ref_cache_empty"
doctor_reset
check_references > "$ref_out_file" 2>&1
ref_out="$(<"$ref_out_file")"

# --- source chains ----------------------------------------------------------
assert_contains "$ref_out" "hypr/hyprland.conf sources config/missing.conf" \
    "missing source target is reported"
assert_contains "$ref_out" "ERROR" "missing source target is ERROR severity"
assert_contains "$ref_out" "hypr/hyprlock.conf sources config/lock-missing.conf" \
    "source target is resolved against the sourcing file's own directory"
assert_not_contains "$ref_out" "config/good.conf, which does not exist" \
    "resolvable source target produces no finding"
assert_not_contains "$ref_out" "config/inline.conf, which does not exist" \
    "inline comment is stripped off the source target"
assert_not_contains "$ref_out" "trailing comment" \
    "no finding quotes the comment text back at the user"
assert_not_contains "$ref_out" "spaced dir/there.conf, which does not exist" \
    "source target containing a space still resolves"
assert_contains "$ref_out" "spaced dir/gone.conf" \
    "missing source target containing a space is reported"

# Neither a template nor a glob names a single file, so neither can be checked.
assert_not_contains "$ref_out" "expanded.conf" \
    "source target with an unexpanded variable is skipped"
assert_not_contains "$ref_out" "config/*.conf" \
    "globbed source target is skipped"
assert_not_contains "$ref_out" "absolute.conf" \
    "source target outside the tree under test is skipped"

# --- literal ~/.config references -------------------------------------------
assert_contains "$ref_out" "scripts/broken.sh references ~/.config/gone/missing.sh" \
    "missing literal \$HOME/.config path is reported"
assert_not_contains "$ref_out" "present.sh, which does not exist" \
    "literal path that exists produces no finding"

# docs/ and *.md hold illustrative paths; reporting them would bury the real
# findings under the contents of every plan ever written.
assert_not_contains "$ref_out" "docs-md" "a .md file under docs/ is not scanned"
assert_not_contains "$ref_out" "docs-txt" "a non-md file under docs/ is not scanned"
assert_not_contains "$ref_out" "md-only" "a .md file outside docs/ is not scanned"

assert_not_contains "$ref_out" "themes" \
    "paths holding a variable or a glob are skipped, not reported"

# The strip must be anchored to the front. A longest-match strip would turn
# scripts/x/.config/y into y and send the reader to the wrong file.
assert_contains "$ref_out" "nested.sh references ~/.config/scripts/x/.config/y" \
    "only the leading ~/.config/ is stripped"
assert_not_contains "$ref_out" "references ~/.config/y," \
    "a later /.config/ in the path is not mistaken for the prefix"

# --- generated content ------------------------------------------------------
assert_not_contains "$ref_out" "generated/never-exists.css" \
    "content of a tracked symlink is not scanned"

# --- wall.sh colour fan-out -------------------------------------------------
assert_contains "$ref_out" "applies colours via ~/.config/ghostty/apply_wal_colors.sh" \
    "missing wall.sh colour script is reported"
assert_contains "$ref_out" "WARN" "missing wall.sh colour script is WARN severity"
assert_contains "$ref_out" "applies colours via ~/.config/scripts/waybar/waybar.sh" \
    "the fan-out list is the whole for-loop, not just apply_wal_colors.sh"
assert_contains "$ref_out" "wall.sh references ~/.config/gone/wall-hard-ref.sh" \
    "an unguarded reference in wall.sh is not downgraded to a warning"

# --- pywal cache ------------------------------------------------------------
assert_contains "$ref_out" "$ref_cache_empty/wal/colors-hyprland.conf" \
    "missing pywal cache is reported"

# --- tallies ----------------------------------------------------------------
# 4 source targets, 4 literal paths, 1 pywal cache.
assert_eq "$DOCTOR_ERRORS" "9" "unresolvable references counted as errors"
# The three entries of wall.sh's existence-guarded loop.
assert_eq "$DOCTOR_WARNINGS" "3" "optional colour scripts counted as warnings"
assert_eq "$DOCTOR_NOTICES" "0" "nothing here is a notice"

# --- every fix hint is copy-pasteable ---------------------------------------
# One assertion per hint: a quoting bug survived Task 2 review because only one
# hint was ever asserted.
assert_contains "$ref_out" "restore $ref_fixture/hypr/config/spaced\\ dir/gone.conf, or drop the source line from $ref_fixture/hypr/hyprland.conf" \
    "source hint shell-quotes a target containing a space"
assert_contains "$ref_out" "restore $ref_fixture/gone/missing2.sh, or drop the reference from $ref_fixture/has\\ space.sh" \
    "literal hint shell-quotes the referencing file's name"
assert_contains "$ref_out" "restore $ref_fixture/ghostty/apply_wal_colors.sh, or remove it from the list in $ref_fixture/scripts/hyprland/wall.sh" \
    "colour script hint points at the list to edit"
ref_wal_hint='wal -i "$(readlink -f '"$ref_fixture"'/options/wallpaper)"'
assert_contains "$ref_out" "$ref_wal_hint" \
    "pywal hint regenerates the cache from the recorded wallpaper"

# A top-level conf has no base directory; "$root//$target" would be an ugly,
# unpasteable path even though the kernel tolerates it.
assert_contains "$ref_out" "restore $ref_fixture/toplevel-target.conf" \
    "hint for a top-level conf has no doubled slash"
assert_not_contains "$ref_out" "$ref_fixture//" "no hint contains a doubled slash"

# `<foo>` is input redirection to a shell, so the user would get an error from
# bash rather than from the command they pasted.
assert_not_contains "$ref_out" "<" "no hint contains what a shell reads as a redirection"

# --- the all-clear is reserved for an actually clear result -----------------
assert_not_contains "$ref_out" "✓" "repo with broken references gets no green tick"

# =====================================================================
# A repo where everything resolves.
# =====================================================================
ref_clean="$(make_fixture)"
mkdir -p "$ref_clean/hypr/config"
cat > "$ref_clean/hypr/hyprland.conf" <<'EOF'
source = config/colors.conf
EOF
echo "colors" > "$ref_clean/hypr/config/colors.conf"
cat > "$ref_clean/launch.sh" <<'EOF'
exec "$HOME/.config/hypr/hyprland.conf"
EOF
git -C "$ref_clean" add -A
git -C "$ref_clean" commit -qm "fixture"

ref_cache_full="$DOCTOR_TEST_TMP/ref-cache-full"
mkdir -p "$ref_cache_full/wal"
echo "generated" > "$ref_cache_full/wal/colors-hyprland.conf"

DOCTOR_ROOT="$ref_clean"
DOCTOR_CACHE="$ref_cache_full"
doctor_reset
check_references > "$ref_out_file" 2>&1
ref_clean_out="$(<"$ref_out_file")"

assert_contains "$ref_clean_out" "✓" "fully resolvable repo gets the green tick"
assert_contains "$ref_clean_out" "all config references resolve" \
    "fully resolvable repo says so"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS$DOCTOR_NOTICES" "000" \
    "fully resolvable repo records nothing"

# =====================================================================
# A repo whose only finding is a warning.
# =====================================================================
# ok is the all-clear and nothing else: gating it on the error count alone
# would print a green tick over a warning the reader is meant to act on.
ref_warn_fixture="$(make_fixture)"
mkdir -p "$ref_warn_fixture/scripts/hyprland"
cat > "$ref_warn_fixture/scripts/hyprland/wall.sh" <<'EOF'
#!/bin/bash
for script in \
    "$HOME/.config/ghostty/apply_wal_colors.sh"; do
    [ -x "$script" ] && "$script" &
done
EOF
git -C "$ref_warn_fixture" add -A
git -C "$ref_warn_fixture" commit -qm "fixture"

DOCTOR_ROOT="$ref_warn_fixture"
DOCTOR_CACHE="$ref_cache_full"
doctor_reset
check_references > "$ref_out_file" 2>&1
ref_warn_out="$(<"$ref_out_file")"

assert_contains "$ref_warn_out" "WARN" "warning-only repo still reports its warning"
assert_not_contains "$ref_warn_out" "✓" "a warning suppresses the all-clear line"
assert_eq "$DOCTOR_ERRORS" "0" "warning-only repo records no error"
assert_eq "$DOCTOR_WARNINGS" "1" "warning-only repo records one warning"

# =====================================================================
# A repo with no configs at all.
# =====================================================================
# Nothing to resolve is a clear result, not a notice: an empty target list is a
# normal outcome, and doctor_require_repo has already ruled out "no repository".
ref_bare_fixture="$(make_fixture)"
echo "plain" > "$ref_bare_fixture/regular-file"
git -C "$ref_bare_fixture" add -A
git -C "$ref_bare_fixture" commit -qm "fixture"

DOCTOR_ROOT="$ref_bare_fixture"
DOCTOR_CACHE="$ref_cache_full"
doctor_reset
check_references > "$ref_out_file" 2>&1
ref_bare_out="$(<"$ref_out_file")"

assert_contains "$ref_bare_out" "all config references resolve" \
    "repo without configs is a clear result"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS$DOCTOR_NOTICES" "000" \
    "repo without configs records nothing"
