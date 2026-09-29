# Tests for scripts/doctor/checks/autostart.sh — sourced by run-tests.sh
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/autostart.sh"

as_out_file="$DOCTOR_TEST_TMP/autostart.out"
as_root="$DOCTOR_TEST_TMP/autostart"
mkdir -p "$as_root/user" "$as_root/system"
printf '[Desktop Entry]\nType=Application\nName=Tray\nExec=not-installed-tool --tray\n' > "$as_root/user/tray.desktop"
printf '[Desktop Entry]\nType=Application\nName=Fine\nExec=bash -c true\n' > "$as_root/user/fine.desktop"
printf '[Desktop Entry]\nType=Application\nName=Quoted\nExec="/nonexistent dir/run"\n' > "$as_root/user/quoted.desktop"
printf "[Desktop Entry]\nType=Application\nName=Single\nExec='/single quoted/run' --x\n" > "$as_root/user/single.desktop"
printf '[Desktop Entry]\nType=Application\nName=Try\nTryExec=/no such/try exec\nExec=bash\n' > "$as_root/user/try.desktop"
printf '[Desktop Entry]\nType=Application\nName=Both\nTryExec=missing-try\nExec=missing-exec\n' > "$as_root/user/both.desktop"
printf '[Desktop Entry]\nType=Application\nName=Gone\nHidden=true\n' > "$as_root/user/gone.desktop"
printf '[Desktop Entry]\nType=Application\nName=Kept\nHidden=true\n' > "$as_root/user/kept.desktop"
printf '[Desktop Entry]\nName=Kept\nExec=kept\n' > "$as_root/system/kept.desktop"
printf '[Desktop Entry]\nType=Application\nName=Off\nExec=also-missing\nHidden=true\nComment=hand\n' > "$as_root/user/off.desktop"
printf '[Desktop Entry]\nType=Application\nName=Loud\nExec=loud-missing\nHidden=YES\n' > "$as_root/user/loud.desktop"
printf '[Desktop Entry]\nType=Application\nName=Relapse\nExec=relapse-missing\nHidden=true\nHidden=false\n' > "$as_root/user/relapse.desktop"
printf '[Desktop Entry]\nType=Link\nName=Link\nExec=link-missing\n' > "$as_root/user/link.desktop"
printf '[Desktop Entry]\nName=Untyped\nExec=untyped-missing\n' > "$as_root/user/untyped.desktop"
printf '[Desktop Entry]\nType=Application\nName=Dot\nExec=dot-missing\n' > "$as_root/user/.dot.desktop"
printf '[Desktop Entry]\nType=Application\nName=Backup\nExec=backup-missing\n' > "$as_root/user/backup.desktop~"
printf '[Desktop Entry]\nType=Application\nName=Xg\nExec=xg-missing\nX-GNOME-Autostart-enabled=false\n' > "$as_root/user/xg.desktop"

DOCTOR_AUTOSTART_DIR="$as_root/user"
DOCTOR_AUTOSTART_SYSTEM="$as_root/system"
doctor_reset
check_autostart > "$as_out_file" 2>&1
as_text="$(cat "$as_out_file")"
# tray, quoted, single, try, both, relapse, xg
assert_eq "$DOCTOR_WARNINGS" "7" "autostart: seven warnings"
assert_eq "$DOCTOR_NOTICES" "1" "autostart: one notice"
assert_contains "$as_text" "not-installed-tool" "autostart: names the missing binary"
assert_contains "$as_text" "/nonexistent dir/run" "autostart: handles a double-quoted Exec"
assert_contains "$as_text" "/single quoted/run" "autostart: handles a single-quoted Exec"
assert_contains "$as_text" "/no such/try exec" "autostart: TryExec is looked up verbatim"
assert_contains "$as_text" "missing-try" "autostart: names a missing TryExec"
assert_contains "$as_text" "missing-exec" "autostart: names a missing Exec beside a missing TryExec"
assert_contains "$as_text" "relapse-missing" "autostart: the last Hidden wins"
assert_contains "$as_text" "xg-missing" "autostart: X-GNOME-Autostart-enabled is ignored"
assert_contains "$as_text" "gone.desktop" "autostart: notes the orphaned override"
assert_not_contains "$as_text" "kept.desktop" "autostart: an override with a system entry is fine"
assert_not_contains "$as_text" "also-missing" "autostart: hidden entries are not checked for binaries"
assert_not_contains "$as_text" "loud-missing" "autostart: Hidden is a case-insensitive boolean"
assert_not_contains "$as_text" "link-missing" "autostart: non-Application entries are skipped"
assert_not_contains "$as_text" "untyped-missing" "autostart: entries without Type are skipped"
assert_not_contains "$as_text" "dot-missing" "autostart: dotfiles are skipped"
assert_not_contains "$as_text" "backup-missing" "autostart: backup files are skipped"
assert_not_contains "$as_text" "✓" "autostart: no all-clear with findings"

# Links: systemd follows a live one (so its entry is checked) and ignores a dangling one.
mkdir -p "$as_root/links"
printf '[Desktop Entry]\nType=Application\nName=Linked\nExec=linked-target-missing\n' > "$as_root/linked-target.desktop"
ln -s "$as_root/linked-target.desktop" "$as_root/links/linked.desktop"
ln -s "$as_root/nowhere.desktop" "$as_root/links/dangling.desktop"
DOCTOR_AUTOSTART_DIR="$as_root/links"
doctor_reset
check_autostart > "$as_out_file" 2>&1
as_text="$(cat "$as_out_file")"
assert_eq "$DOCTOR_WARNINGS" "2" "autostart: a broken linked entry and a dangling link both warn"
assert_contains "$as_text" "linked-target-missing" "autostart: a symlinked entry is checked through the link"
assert_contains "$as_text" "dangling.desktop is a link to a missing file" "autostart: a dangling link is reported"

DOCTOR_AUTOSTART_DIR="$as_root/absent"
doctor_reset
check_autostart > "$as_out_file" 2>&1
assert_eq "$((DOCTOR_WARNINGS + DOCTOR_NOTICES))" "0" "autostart: a missing directory is clean"
assert_contains "$(cat "$as_out_file")" "✓" "autostart: a missing directory prints the all-clear"

mkdir -p "$as_root/clean"
printf '[Desktop Entry]\nType=Application\nName=Fine\nExec=bash -c true\n' > "$as_root/clean/fine.desktop"
DOCTOR_AUTOSTART_DIR="$as_root/clean"
doctor_reset
check_autostart > "$as_out_file" 2>&1
assert_eq "$((DOCTOR_WARNINGS + DOCTOR_NOTICES))" "0" "autostart: a resolving entry is clean"
assert_contains "$(cat "$as_out_file")" "✓" "autostart: prints the all-clear when nothing is found"
# Reset for later files; read by the check sourced above.
# shellcheck disable=SC2034
DOCTOR_AUTOSTART_DIR="" DOCTOR_AUTOSTART_SYSTEM=""
