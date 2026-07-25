# Tests for scripts/doctor/checks/binaries.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash
#
# Variables are prefixed bin_ because every test file is sourced into the
# same shell as test-lib.sh, test-symlinks.sh and test-references.sh.

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/binaries.sh"

# Assigned throughout and read by the sourced check module, not by this file
# directly, which is what SC2034 would otherwise flag.
export DOCTOR_ROOT

# bin_line <file> <substring> -> the matching line, or empty
# Severity must be asserted on the finding's own line: asserting "WARN"
# against the whole report would pass even with every classification
# inverted, a real defect found reviewing the references module.
bin_line() {
    grep -F -- "$2" "$1" 2>/dev/null | head -n1
}

bin_fixture="$(make_fixture)"
mkdir -p "$bin_fixture/hypr/config/software" \
         "$bin_fixture/hypr/config/setup" \
         "$bin_fixture/options"

# bash/ls/cat/env are installed everywhere; the -absent- names are chosen to
# be implausible as real binaries.
echo "bash" > "$bin_fixture/options/terminal"
echo "absent-browser-qq" > "$bin_fixture/options/browser"

cat > "$bin_fixture/hypr/config/apptype.conf" <<'BIN_EOF'
$fileManager = ls        # GUI file manager
$textEditor = cat        # Text editor
$polkitAgent = absent-polkit-qq  # Authentication agent
BIN_EOF

cat > "$bin_fixture/hypr/config/software/keybinds.conf" <<'BIN_EOF'
bind = $Mod, RETURN, exec, $terminal
bind = $Mod, B, exec, $browser
bind = $Mod, E, exec, $fileManager
bind = $Mod, X, exec, absent-bin-qq
bind = $Mod, Y, exec, absent-bin-qq --flag
bind = $Mod, A, exec, ~/.config/scripts/thing.sh
bind = $Mod, D, exec, $HOME/.config/scripts/other.sh
bind = $Mod, Z, exec, $undefinedVariable
bind = $Mod, Q, killactive,
bind = $Mod, F, fullscreen
bind = $Mod, S, exec, cat -n /dev/null
bind = $Mod, P, exec, ls | absent-pipe-qq -x
bindel = ,XF86AudioRaiseVolume, exec, env FOO=1
BIN_EOF

cat > "$bin_fixture/hypr/config/setup/autostart.conf" <<'BIN_EOF'
exec-once = env
exec-once = absent-daemon-qq &
exec-once = $polkitAgent
exec-once = $HOME/.config/scripts/hyprland/startup.sh
BIN_EOF

git -C "$bin_fixture" add -A
git -C "$bin_fixture" commit -qm "fixture"

DOCTOR_ROOT="$bin_fixture"

# --- variable resolution ------------------------------------------------
assert_eq "$(_bin_resolve_var terminal)" "bash" "\$terminal resolves from options/"
assert_eq "$(_bin_resolve_var browser)" "absent-browser-qq" "\$browser resolves from options/"
assert_eq "$(_bin_resolve_var fileManager)" "ls" "\$fileManager resolves from apptype.conf"
assert_eq "$(_bin_resolve_var textEditor)" "cat" "apptype.conf trailing comment is stripped"
assert_eq "$(_bin_resolve_var polkitAgent)" "absent-polkit-qq" "\$polkitAgent resolves from apptype.conf"
assert_eq "$(_bin_resolve_var undefinedVariable)" "" "unknown variable resolves to empty"

# --- findings -----------------------------------------------------------
bin_out_file="$DOCTOR_TEST_TMP/bin-out"
doctor_reset
check_binaries > "$bin_out_file" 2>&1
bin_out="$(cat "$bin_out_file")"

assert_contains "$(bin_line "$bin_out_file" "absent-browser-qq")" "WARN" \
    "missing \$browser binary is WARN"
assert_contains "$(bin_line "$bin_out_file" "absent-bin-qq")" "WARN" \
    "missing literal keybind binary is WARN"
assert_contains "$(bin_line "$bin_out_file" "absent-daemon-qq")" "WARN" \
    "missing autostart binary is WARN"
assert_contains "$(bin_line "$bin_out_file" "absent-polkit-qq")" "WARN" \
    "missing \$polkitAgent binary is WARN"
assert_contains "$(bin_line "$bin_out_file" "undefinedVariable")" "WARN" \
    "unresolvable variable is WARN"
assert_contains "$(bin_line "$bin_out_file" "absent-pipe-qq")" "WARN" \
    "missing binary in a pipeline segment is WARN"

assert_eq "$DOCTOR_ERRORS" "0" "nothing in this module is ERROR severity"
assert_eq "$DOCTOR_NOTICES" "0" "nothing in this module is INFO severity"

# --- what must NOT be reported ------------------------------------------
assert_not_contains "$bin_out" "scripts/thing.sh" \
    "tilde path targets are left to the reference check"
assert_not_contains "$bin_out" "scripts/other.sh" \
    "\$HOME path targets are left to the reference check"
assert_not_contains "$bin_out" "killactive" "non-exec binds are not parsed as commands"
assert_not_contains "$bin_out" "fullscreen" "dispatcher-only binds are not parsed as commands"
assert_not_contains "$bin_out" "Mod" "modifier variables are never treated as binaries"
assert_not_contains "$bin_out" "'bash'" "installed \$terminal produces no finding"
assert_not_contains "$bin_out" "'cat'" "installed literal binary produces no finding"
assert_not_contains "$bin_out" "'env'" "binary shared by keybinds and autostart produces no finding"

# --- dedupe -------------------------------------------------------------
# Count finding lines only: the name also appears in that finding's fix hint.
assert_eq "$(grep -cF "'absent-bin-qq', which is not installed" "$bin_out_file")" "1" \
    "a binary bound twice is reported once"

# --- fix hints ----------------------------------------------------------
assert_contains "$bin_out" "pacman -S absent-bin-qq" \
    "missing binary hint names the package to install"
assert_contains "$bin_out" "hypr/config/apptype.conf" \
    "unresolvable variable hint points at where to define it"

# --- ok is the all-clear and nothing else -------------------------------
assert_not_contains "$bin_out" "✓" "no green tick while findings exist"

bin_clean_fixture="$(make_fixture)"
mkdir -p "$bin_clean_fixture/hypr/config/software" \
         "$bin_clean_fixture/hypr/config/setup" \
         "$bin_clean_fixture/options"
echo "bash" > "$bin_clean_fixture/options/terminal"
printf 'bind = $Mod, RETURN, exec, $terminal\nbind = $Mod, S, exec, cat\n' \
    > "$bin_clean_fixture/hypr/config/software/keybinds.conf"
printf 'exec-once = env\n' > "$bin_clean_fixture/hypr/config/setup/autostart.conf"
git -C "$bin_clean_fixture" add -A
git -C "$bin_clean_fixture" commit -qm "fixture"

DOCTOR_ROOT="$bin_clean_fixture"
bin_clean_file="$DOCTOR_TEST_TMP/bin-clean"
doctor_reset
check_binaries > "$bin_clean_file" 2>&1
bin_clean_out="$(cat "$bin_clean_file")"

assert_contains "$bin_clean_out" "✓" "green tick when every binary resolves"
assert_eq "$DOCTOR_WARNINGS" "0" "clean tree produces no warnings"

# --- missing config files are not an error ------------------------------
bin_empty_fixture="$(make_fixture)"
git -C "$bin_empty_fixture" commit -q --allow-empty -m "empty"
DOCTOR_ROOT="$bin_empty_fixture"
bin_empty_file="$DOCTOR_TEST_TMP/bin-empty"
doctor_reset
check_binaries > "$bin_empty_file" 2>&1
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS" "00" \
    "absent keybinds/autostart files produce no findings"
