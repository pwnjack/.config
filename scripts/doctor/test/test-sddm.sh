# Tests for scripts/doctor/checks/sddm.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash
#
# Each check runs once with output redirected under DOCTOR_TEST_TMP. Reading
# the output through command substitution only after the check has returned
# preserves the severity counters in this shared shell.

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/sddm.sh"

export DOCTOR_ROOT

sddm_out_file="$DOCTOR_TEST_TMP/sddm.out"
sddm_expected_file="$DOCTOR_TEST_TMP/sddm-expected.out"
sddm_host="sddm"
sddm_sudo_output=""
sddm_watcher="running"
sddm_ffmpeg="installed"
sddm_out=""
sddm_helper=""
sddm_sudoers=""
sddm_theme_dir=""
sddm_backgrounds_dir=""
sddm_helper_state="root:root 755"
sddm_sudoers_state="root:root 440"
sddm_theme_owner="root"
sddm_backgrounds_owner="root"

# Host probes are the only pieces replaced. Parsing, filesystem comparisons
# and every finding decision below are the real check implementation.
_sddm_is_display_manager() {
    [ "$sddm_host" = "sddm" ]
}

_sddm_sudo_listing() {
    printf '%s\n' "$sddm_sudo_output"
}

_sddm_watcher_running() {
    [ "$sddm_watcher" = "running" ]
}

_sddm_have_ffmpeg() {
    [ "$sddm_ffmpeg" = "installed" ]
}

_sddm_username() {
    printf 'fixture-user\n'
}

_sddm_file_state() {
    case "$1" in
        "$sddm_helper") printf '%s\n' "$sddm_helper_state" ;;
        "$sddm_sudoers") printf '%s\n' "$sddm_sudoers_state" ;;
        *) stat -c '%U:%G %a' -- "$1" 2>/dev/null ;;
    esac
}

_sddm_resolved_owner() {
    case "$1" in
        "$sddm_theme_dir") printf '%s\n' "$sddm_theme_owner" ;;
        "$sddm_backgrounds_dir") printf '%s\n' "$sddm_backgrounds_owner" ;;
        *)
            local resolved
            resolved=$(readlink -f -- "$1" 2>/dev/null) || return 0
            stat -c '%U' -- "$resolved" 2>/dev/null
            ;;
    esac
}

# sddm_make_fixture — create the tracked sources plus fake host paths. The
# helper is deliberately absent so each scenario chooses missing, drifted or
# current state explicitly.
sddm_make_fixture() {
    local dir helper sudoers
    dir="$(make_fixture)" || return 1
    helper="$dir/host/bin/wallpaper-helper"
    sudoers="$dir/host/sudoers/wallpaper-rule"

    mkdir -p "$dir/sddm" \
             "$dir/host/themes/fixture-theme/Backgrounds" \
             "$dir/host/cache/awww/1" \
             "$dir/host/sudoers"
    printf 'SUDOERS_FILE="%s"\nINSTALLED_HELPER="%s"\n' \
        "$sudoers" "$helper" > "$dir/sddm/setup-sudo.sh"
    printf 'fixture sudoers rule\n' > "$sudoers"
    # The fixture reproduces shell source literally; expansion would defeat
    # the parser test.
    # shellcheck disable=SC2016
    printf '%s\n' \
        'current_theme=""' \
        '[[ -z "$current_theme" ]] && current_theme="fixture-theme"' \
        'privileged source body' > "$dir/sddm/update_sddm_root.sh"
    printf '#!/bin/bash\n' > "$dir/sddm/update_sddm.sh"
    printf '#!/bin/bash\n' > "$dir/sddm/watch_wallpaper.sh"
    printf '[Theme]\nCurrent=fixture-theme\n' > "$dir/host/sddm.conf"
    printf 'awww event\n' > "$dir/host/cache/awww/1/fixture-monitor"
    printf 'greeter background\n' > \
        "$dir/host/themes/fixture-theme/Backgrounds/wallpaper.jpg"
    # Default to a stale sync: the watcher trigger is newer than the output.
    touch -t 202001010000 "$dir/host/themes/fixture-theme/Backgrounds/wallpaper.jpg"
    touch -t 202002010000 "$dir/host/cache/awww/1/fixture-monitor"
    printf '%s' "$dir"
}

sddm_use_fixture() {
    DOCTOR_ROOT="$1"
    DOCTOR_SDDM_CONF="$1/host/sddm.conf"
    DOCTOR_SDDM_THEMES="$1/host/themes"
    DOCTOR_SDDM_AWWW_CACHE="$1/host/cache/awww"
    sddm_helper="$1/host/bin/wallpaper-helper"
    sddm_sudoers="$1/host/sudoers/wallpaper-rule"
    sddm_theme_dir="$1/host/themes/fixture-theme"
    sddm_backgrounds_dir="$sddm_theme_dir/Backgrounds"
    sddm_helper_state="root:root 755"
    sddm_sudoers_state="root:root 440"
    sddm_theme_owner="root"
    sddm_backgrounds_owner="root"
}

sddm_run_check() {
    doctor_reset
    check_sddm > "$sddm_out_file" 2>&1
    sddm_out="$(cat "$sddm_out_file")"
}

# --- all live breakages that used to be silent -----------------------------
sddm_broken="$(sddm_make_fixture)"
sddm_use_fixture "$sddm_broken"
sddm_host="sddm"
sddm_sudo_output=""
sddm_watcher="stopped"
sddm_ffmpeg="missing"
sddm_run_check

assert_contains "$sddm_out" "not in the effective passwordless sudo permissions" \
    "missing passwordless-sudo grant is an ERROR"
assert_contains "$sddm_out" "run $sddm_broken/sddm/setup-sudo.sh" \
    "missing grant points at the derived setup script"
assert_contains "$sddm_out" "installed SDDM wallpaper helper is missing" \
    "missing installed helper is an ERROR"
assert_contains "$sddm_out" "ffmpeg is not installed" \
    "missing ffmpeg is an ERROR"
assert_contains "$sddm_out" "wallpaper watcher is not running" \
    "stopped watcher is a WARN"
assert_contains "$sddm_out" "greeter background is older than the newest awww cache update" \
    "stale greeter background is a WARN"
assert_eq "$DOCTOR_ERRORS" "3" "broken host records exactly three errors"
assert_eq "$DOCTOR_WARNINGS" "2" "broken host records exactly two warnings"

# --- an installed copy that no longer matches its tracked source -----------
sddm_drift="$(sddm_make_fixture)"
sddm_use_fixture "$sddm_drift"
mkdir -p "$(dirname "$sddm_helper")"
printf 'drifted installed copy\n' > "$sddm_helper"
sddm_sudo_output="(root) NOPASSWD: $sddm_helper fixture-user"
sddm_watcher="running"
sddm_ffmpeg="installed"
touch -t 202003010000 \
    "$sddm_drift/host/themes/fixture-theme/Backgrounds/wallpaper.jpg"
sddm_run_check

assert_contains "$sddm_out" "differs from the tracked source" \
    "drifted installed helper is a WARN"
assert_eq "$DOCTOR_ERRORS" "0" "drift alone is not an error"
assert_eq "$DOCTOR_WARNINGS" "1" "drift produces exactly one warning"

# --- the grant must pin exactly the invoking username ----------------------
sddm_unrestricted="$(sddm_make_fixture)"
sddm_use_fixture "$sddm_unrestricted"
mkdir -p "$(dirname "$sddm_helper")"
cp "$sddm_unrestricted/sddm/update_sddm_root.sh" "$sddm_helper"
sddm_sudo_output="(root) NOPASSWD: $sddm_helper"
sddm_watcher="running"
sddm_ffmpeg="installed"
touch -t 202003010000 \
    "$sddm_unrestricted/host/themes/fixture-theme/Backgrounds/wallpaper.jpg"
sddm_run_check

assert_contains "$sddm_out" "not in the effective passwordless sudo permissions" \
    "argument-unrestricted helper grant is rejected"
assert_eq "$DOCTOR_ERRORS" "1" "unrestricted grant records one error"

# --- broader effective grants accepted by sudo are accepted here too ------
sddm_blanket_grant="$(sddm_make_fixture)"
sddm_use_fixture "$sddm_blanket_grant"
mkdir -p "$(dirname "$sddm_helper")"
cp "$sddm_blanket_grant/sddm/update_sddm_root.sh" "$sddm_helper"
sddm_sudo_output="(ALL) NOPASSWD: ALL"
sddm_watcher="running"
sddm_ffmpeg="installed"
touch -t 202003010000 \
    "$sddm_blanket_grant/host/themes/fixture-theme/Backgrounds/wallpaper.jpg"
sddm_run_check

assert_not_contains "$sddm_out" "not in the effective passwordless sudo permissions" \
    "blanket NOPASSWD: ALL satisfies the effective grant check"
assert_eq "$DOCTOR_ERRORS" "0" "blanket grant produces no error"

sddm_command_list="$(sddm_make_fixture)"
sddm_use_fixture "$sddm_command_list"
mkdir -p "$(dirname "$sddm_helper")"
cp "$sddm_command_list/sddm/update_sddm_root.sh" "$sddm_helper"
sddm_sudo_output="(root) NOPASSWD: /usr/bin/true, $sddm_helper fixture-user, /usr/bin/false"
sddm_watcher="running"
sddm_ffmpeg="installed"
touch -t 202003010000 \
    "$sddm_command_list/host/themes/fixture-theme/Backgrounds/wallpaper.jpg"
sddm_run_check

assert_not_contains "$sddm_out" "not in the effective passwordless sudo permissions" \
    "helper entry within a comma-separated command list satisfies the grant check"
assert_eq "$DOCTOR_ERRORS" "0" "comma-separated helper grant produces no error"

# /etc/sudoers.d is not traversable by an ordinary user on Arch. An empty
# metadata probe for its child must not override an effective sudo grant.
sddm_unreadable_sudoers="$(sddm_make_fixture)"
sddm_use_fixture "$sddm_unreadable_sudoers"
mkdir -p "$(dirname "$sddm_helper")"
cp "$sddm_unreadable_sudoers/sddm/update_sddm_root.sh" "$sddm_helper"
sddm_sudo_output="(root) NOPASSWD: $sddm_helper fixture-user"
sddm_sudoers_state=""
sddm_watcher="running"
sddm_ffmpeg="installed"
touch -t 202003010000 \
    "$sddm_unreadable_sudoers/host/themes/fixture-theme/Backgrounds/wallpaper.jpg"
assert_eq "$(_sddm_file_state "$sddm_sudoers")" "" \
    "fixture reproduces an unreadable sudoers drop-in metadata probe"
sddm_run_check

assert_not_contains "$sddm_out" "sudoers drop-in" \
    "unreadable sudoers file metadata produces no finding when the grant works"
assert_eq "$DOCTOR_ERRORS" "0" \
    "effective grant and safe helper produce no sudoers-path error"

# --- installed helper retains its ownership and mode boundary -------------
sddm_permissions="$(sddm_make_fixture)"
sddm_use_fixture "$sddm_permissions"
mkdir -p "$(dirname "$sddm_helper")"
cp "$sddm_permissions/sddm/update_sddm_root.sh" "$sddm_helper"
sddm_sudo_output="(root) NOPASSWD: $sddm_helper fixture-user"
sddm_watcher="running"
sddm_ffmpeg="installed"
touch -t 202003010000 \
    "$sddm_permissions/host/themes/fixture-theme/Backgrounds/wallpaper.jpg"

sddm_helper_state="fixture-user:fixture-user 755"
sddm_run_check
assert_contains "$sddm_out" "helper has unsafe ownership or mode" \
    "user-owned installed helper is an ERROR"
assert_eq "$DOCTOR_ERRORS" "1" "wrong helper owner records one error"

sddm_helper_state="root:root 775"
sddm_run_check
assert_contains "$sddm_out" "helper has unsafe ownership or mode" \
    "group-writable installed helper is an ERROR"
assert_eq "$DOCTOR_ERRORS" "1" "wrong helper mode records one error"

sddm_symlink="$(sddm_make_fixture)"
sddm_use_fixture "$sddm_symlink"
mkdir -p "$(dirname "$sddm_helper")"
ln -s "$sddm_symlink/sddm/update_sddm_root.sh" "$sddm_helper"
sddm_sudo_output="(root) NOPASSWD: $sddm_helper fixture-user"
sddm_watcher="running"
sddm_ffmpeg="installed"
touch -t 202003010000 \
    "$sddm_symlink/host/themes/fixture-theme/Backgrounds/wallpaper.jpg"
sddm_run_check

assert_contains "$sddm_out" "helper must not be a symlink" \
    "installed helper symlink is rejected even when its content matches"
assert_eq "$DOCTOR_ERRORS" "1" "helper symlink records one error"

# --- missing greeter output is a finding ----------------------------------
sddm_missing_background="$(sddm_make_fixture)"
sddm_use_fixture "$sddm_missing_background"
mkdir -p "$(dirname "$sddm_helper")"
cp "$sddm_missing_background/sddm/update_sddm_root.sh" "$sddm_helper"
sddm_sudo_output="(root) NOPASSWD: $sddm_helper fixture-user"
sddm_watcher="running"
sddm_ffmpeg="installed"
rm "$sddm_missing_background/host/themes/fixture-theme/Backgrounds/wallpaper.jpg"
sddm_run_check

assert_contains "$sddm_out" "greeter background is missing" \
    "missing greeter background is a WARN"
assert_eq "$DOCTOR_WARNINGS" "1" "missing greeter background records one warning"

# The live success order is awww trigger first, then root's ffmpeg output.
# wall.sh updates current_wallpaper later still, but that unrelated symlink is
# deliberately not the staleness baseline.
sddm_live_order="$(sddm_make_fixture)"
sddm_use_fixture "$sddm_live_order"
mkdir -p "$(dirname "$sddm_helper")"
cp "$sddm_live_order/sddm/update_sddm_root.sh" "$sddm_helper"
sddm_sudo_output="(root) NOPASSWD: $sddm_helper fixture-user"
sddm_watcher="running"
sddm_ffmpeg="installed"
touch -t 202001010000 "$sddm_live_order/host/cache/awww/1/fixture-monitor"
touch -t 202002010000 \
    "$sddm_live_order/host/themes/fixture-theme/Backgrounds/wallpaper.jpg"
sddm_run_check

assert_not_contains "$sddm_out" "last sync did not complete" \
    "trigger-before-background live ordering is recognised as synchronised"
assert_eq "$DOCTOR_WARNINGS" "0" \
    "successful live write ordering produces no staleness warning"

# --- root writes must not land below a user-owned theme directory ----------
sddm_user_theme="$(sddm_make_fixture)"
sddm_use_fixture "$sddm_user_theme"
mkdir -p "$(dirname "$sddm_helper")"
cp "$sddm_user_theme/sddm/update_sddm_root.sh" "$sddm_helper"
sddm_sudo_output="(root) NOPASSWD: $sddm_helper fixture-user"
sddm_watcher="running"
sddm_ffmpeg="installed"
sddm_theme_owner="fixture-user"
touch -t 202003010000 \
    "$sddm_user_theme/host/themes/fixture-theme/Backgrounds/wallpaper.jpg"
sddm_run_check

assert_contains "$sddm_out" "theme directory is owned by fixture-user, not root" \
    "user-owned resolved theme directory is an ERROR"
assert_contains "$sddm_out" "privileged helper writes into a user-controlled directory" \
    "theme ownership finding explains the root-write boundary"
assert_not_contains "$sddm_out" "SDDM wallpaper sync is healthy" \
    "unsafe theme directory prevents the all-clear"
assert_eq "$DOCTOR_ERRORS" "1" "user-owned theme directory records one error"

# --- non-SDDM hosts do not get findings or even a heading ------------------
sddm_other="$(sddm_make_fixture)"
sddm_use_fixture "$sddm_other"
sddm_host="other"
sddm_sudo_output=""
sddm_watcher="stopped"
sddm_ffmpeg="missing"
sddm_run_check

assert_eq "$sddm_out" "" "non-SDDM host is a silent no-op"
assert_eq "$DOCTOR_ERRORS" "0" "non-SDDM host records no errors"
assert_eq "$DOCTOR_WARNINGS" "0" "non-SDDM host records no warnings"

# --- missing and malformed source definitions fail clearly -----------------
sddm_no_setup="$(make_fixture)"
sddm_use_fixture "$sddm_no_setup"
sddm_host="sddm"
sddm_run_check

assert_contains "$sddm_out" "setup-sudo.sh is missing" \
    "missing setup source is reported"
assert_eq "$DOCTOR_ERRORS" "1" "missing setup source records one error"

sddm_bad_setup="$(make_fixture)"
mkdir -p "$sddm_bad_setup/sddm"
printf 'SUDOERS_FILE="fixture-rule"\n' > "$sddm_bad_setup/sddm/setup-sudo.sh"
sddm_use_fixture "$sddm_bad_setup"
sddm_run_check

assert_contains "$sddm_out" "cannot derive SDDM privileged paths" \
    "unparseable setup source is reported"
assert_eq "$DOCTOR_ERRORS" "1" "unparseable setup source records one error"

# --- clean SDDM host prints exactly the group and one all-clear line --------
sddm_clean="$(sddm_make_fixture)"
sddm_use_fixture "$sddm_clean"
mkdir -p "$(dirname "$sddm_helper")"
cp "$sddm_clean/sddm/update_sddm_root.sh" "$sddm_helper"
sddm_host="sddm"
sddm_sudo_output="(root) NOPASSWD: $sddm_helper fixture-user"
sddm_watcher="running"
sddm_ffmpeg="installed"
touch -t 202003010000 \
    "$sddm_clean/host/themes/fixture-theme/Backgrounds/wallpaper.jpg"
sddm_run_check

{
    group "SDDM"
    ok "SDDM wallpaper sync is healthy"
} > "$sddm_expected_file"
sddm_expected="$(cat "$sddm_expected_file")"
assert_eq "$sddm_out" "$sddm_expected" \
    "clean host prints exactly the SDDM heading and ok line"
assert_eq "$DOCTOR_ERRORS" "0" "clean host records no errors"
assert_eq "$DOCTOR_WARNINGS" "0" "clean host records no warnings"

# --- doctor and root helper accept the same Current= grammar --------------
printf '[Theme]\n  Current = other-theme  \n' > "$sddm_clean/host/sddm.conf"
assert_eq "$(_sddm_current_theme)" "" \
    "indented Current assignment is rejected like the root helper rejects it"
printf '[Theme]\nCurrent=other-theme\n' > "$sddm_clean/host/sddm.conf"
assert_eq "$(_sddm_current_theme)" "other-theme" \
    "unindented Current= assignment matches the root helper grammar"

# --- updater rejects ambiguous or unsafe installed-helper paths -----------
sddm_script_fixture="$(make_fixture)"
mkdir -p "$sddm_script_fixture/sddm" "$sddm_script_fixture/bin" \
         "$sddm_script_fixture/host/bin"
cp "$REPO_DIR/sddm/update_sddm.sh" "$sddm_script_fixture/sddm/update_sddm.sh"
printf '#!/bin/bash\nexit 0\n' > "$sddm_script_fixture/host/bin/helper"
chmod +x "$sddm_script_fixture/host/bin/helper"

cat > "$sddm_script_fixture/bin/stat" <<'SDDM_STAT_EOF'
#!/bin/bash
if [[ "$2" == "%U:%G %a" ]]; then
    printf '%s\n' "${SDDM_TEST_STAT_NAMED:-root:root 755}"
else
    printf '%s\n' "${SDDM_TEST_STAT_NUMERIC:-0 755}"
fi
SDDM_STAT_EOF
cat > "$sddm_script_fixture/bin/sudo" <<'SDDM_SUDO_EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SDDM_TEST_SUDO_LOG"
if [[ "$1" == "-n" && "$2" == "-l" ]]; then
    printf '%s\n' "${SDDM_TEST_SUDO_LISTING:-}"
elif [[ "$1" == "visudo" ]]; then
    cp "${@: -1}" "$SDDM_TEST_RULE_COPY"
fi
exit 0
SDDM_SUDO_EOF
chmod +x "$sddm_script_fixture/bin/stat" "$sddm_script_fixture/bin/sudo"
sddm_sudo_log="$sddm_script_fixture/sudo.log"
sddm_rule_copy="$sddm_script_fixture/generated-rule"

printf 'INSTALLED_HELPER="%s"\nINSTALLED_HELPER="%s"\n' \
    "$sddm_script_fixture/host/bin/helper" \
    "$sddm_script_fixture/host/bin/second" \
    > "$sddm_script_fixture/sddm/setup-sudo.sh"
: > "$sddm_sudo_log"
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    bash "$sddm_script_fixture/sddm/update_sddm.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "1" \
    "updater rejects duplicate INSTALLED_HELPER definitions"
assert_contains "$sddm_script_out" "cannot derive one installed SDDM helper" \
    "duplicate helper diagnostic explains the ambiguity"
assert_eq "$(cat "$sddm_sudo_log")" "" \
    "ambiguous updater path is rejected before sudo"

printf 'INSTALLED_HELPER="%s"\n' \
    "$sddm_script_fixture/host/bin/helper" \
    > "$sddm_script_fixture/sddm/setup-sudo.sh"
: > "$sddm_sudo_log"
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_STAT_NUMERIC="1000 755" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    bash "$sddm_script_fixture/sddm/update_sddm.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "1" \
    "updater rejects a user-owned installed helper"
assert_contains "$sddm_script_out" "helper is missing or unsafe" \
    "unsafe installed helper points back to setup-sudo.sh"
assert_eq "$(cat "$sddm_sudo_log")" "" \
    "unsafe updater path is rejected before both sudo branches"

: > "$sddm_sudo_log"
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_STAT_NUMERIC="0 755" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    bash "$sddm_script_fixture/sddm/update_sddm.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "0" \
    "safe installed helper reaches passwordless sudo"
assert_eq "$(cat "$sddm_sudo_log")" \
    "-n $sddm_script_fixture/host/bin/helper fixture-user" \
    "updater invokes exactly the helper and username pinned by sudoers"

# --- setup avoids prompts when current and pins new grants ----------------
sddm_setup_fixture="$(make_fixture)"
mkdir -p "$sddm_setup_fixture/sddm" "$sddm_setup_fixture/host/bin" \
         "$sddm_setup_fixture/host/sudoers"
cp "$REPO_DIR/sddm/setup-sudo.sh" "$sddm_setup_fixture/sddm/setup-sudo.sh"
cp "$REPO_DIR/sddm/update_sddm_root.sh" \
    "$sddm_setup_fixture/sddm/update_sddm_root.sh"
sddm_setup_helper="$sddm_setup_fixture/host/bin/helper"
sddm_setup_sudoers="$sddm_setup_fixture/host/sudoers/rule"
cp "$sddm_setup_fixture/sddm/update_sddm_root.sh" "$sddm_setup_helper"
sed -i \
    -e "s|^SUDOERS_FILE=.*|SUDOERS_FILE=\"$sddm_setup_sudoers\"|" \
    -e "s|^INSTALLED_HELPER=.*|INSTALLED_HELPER=\"$sddm_setup_helper\"|" \
    "$sddm_setup_fixture/sddm/setup-sudo.sh"

: > "$sddm_sudo_log"
sddm_current_listing=$(printf '%s\n%s\n%s' \
    "(root) NOPASSWD: $sddm_setup_helper fixture-user" \
    "(root) NOPASSWD: /usr/bin/true" \
    "(root) /tmp/Backgrounds/wallpaper.jpg")
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_STAT_NAMED="root:root 755" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    SDDM_TEST_SUDO_LISTING="$sddm_current_listing" \
    SDDM_TEST_RULE_COPY="$sddm_rule_copy" \
    bash "$sddm_setup_fixture/sddm/setup-sudo.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "0" \
    "fully configured setup completes without an install path"
assert_not_contains "$(cat "$sddm_sudo_log")" "visudo" \
    "current setup does not run visudo"
assert_not_contains "$(cat "$sddm_sudo_log")" "install" \
    "current setup does not reinstall privileged files"
assert_contains "$(cat "$sddm_sudo_log")" "-n -l" \
    "setup inspects grants with non-interactive sudo"
assert_not_contains "$sddm_script_out" "obsolete NOPASSWD rule" \
    "legacy detector does not span separate sudo-listing lines"

: > "$sddm_sudo_log"
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_STAT_NAMED="root:root 755" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    SDDM_TEST_SUDO_LISTING="(ALL) NOPASSWD: ALL" \
    SDDM_TEST_RULE_COPY="$sddm_rule_copy" \
    bash "$sddm_setup_fixture/sddm/setup-sudo.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "0" \
    "setup accepts an existing blanket NOPASSWD: ALL grant"
assert_not_contains "$(cat "$sddm_sudo_log")" "visudo" \
    "blanket grant does not force sudoers validation"
assert_not_contains "$(cat "$sddm_sudo_log")" "install" \
    "blanket grant does not reinstall privileged files"

: > "$sddm_sudo_log"
sddm_comma_listing="(root) NOPASSWD: /usr/bin/true, $sddm_setup_helper fixture-user, /usr/bin/false"
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_STAT_NAMED="root:root 755" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    SDDM_TEST_SUDO_LISTING="$sddm_comma_listing" \
    SDDM_TEST_RULE_COPY="$sddm_rule_copy" \
    bash "$sddm_setup_fixture/sddm/setup-sudo.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "0" \
    "setup accepts the helper within a comma-separated command list"
assert_not_contains "$(cat "$sddm_sudo_log")" "visudo" \
    "comma-separated helper grant does not force sudoers validation"
assert_not_contains "$(cat "$sddm_sudo_log")" "install" \
    "comma-separated helper grant does not reinstall privileged files"

: > "$sddm_sudo_log"
rm "$sddm_setup_helper"
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_STAT_NAMED="root:root 755" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    SDDM_TEST_SUDO_LISTING="" \
    SDDM_TEST_RULE_COPY="$sddm_rule_copy" \
    bash "$sddm_setup_fixture/sddm/setup-sudo.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "0" \
    "drifted setup validates and installs through mocked sudo"
assert_eq "$(cat "$sddm_rule_copy")" \
    "fixture-user ALL=(root) NOPASSWD: $sddm_setup_helper fixture-user" \
    "generated sudoers rule pins the invoking username argument"
sddm_setup_log="$(cat "$sddm_sudo_log")"
assert_contains "$sddm_setup_log" "visudo -c -f" \
    "drifted sudoers rule is validated"
assert_contains "$sddm_setup_log" "install -m 0755 -o root -g root" \
    "drifted helper uses root-owned mode-0755 installation"
assert_contains "$sddm_setup_log" "install -m 0440 -o root -g root" \
    "drifted sudoers file uses root-owned mode-0440 installation"

# --- watcher preserves automatic failures in the journal ------------------
sddm_watch_source="$(cat "$REPO_DIR/sddm/watch_wallpaper.sh")"
assert_contains "$sddm_watch_source" "2> >(logger -t sddm-wallpaper-sync)" \
    "watcher routes updater stderr to its stable journal tag"

# Files share one shell, so return every filesystem seam to its live default.
# shellcheck disable=SC2034
DOCTOR_SDDM_CONF=/etc/sddm.conf
# shellcheck disable=SC2034
DOCTOR_SDDM_THEMES=/usr/share/sddm/themes
# shellcheck disable=SC2034
DOCTOR_SDDM_AWWW_CACHE="$HOME/.cache/awww"
