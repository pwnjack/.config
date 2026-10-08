# Tests for scripts/doctor/checks/ssh.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang.
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/ssh.sh"

ssh_root="$DOCTOR_TEST_TMP/ssh-root"
ssh_home="$DOCTOR_TEST_TMP/ssh-home"
mkdir -p "$ssh_root/environment.d" "$ssh_root/scripts/ssh" "$ssh_root/ssh" "$ssh_home/.ssh"
echo 'AddKeysToAgent yes' > "$ssh_root/ssh/config"
# Quoted heredocs: both lines must reach the fixture literally.
cat > "$ssh_root/environment.d/ssh-agent.conf" <<'EOT'
# comment
SSH_AUTH_SOCK=${XDG_RUNTIME_DIR}/ssh-agent.socket
EOT
cat > "$ssh_root/scripts/ssh/setup.sh" <<'EOT'
SSH_AGENT_UNIT="ssh-agent.socket"
INCLUDE_LINE="Include ~/.config/ssh/config"
EOT
# shellcheck disable=SC2088
ssh_include='Include ~/.config/ssh/config'
ssh_expected="/run/user/test/ssh-agent.socket"

ssh_enabled=yes
ssh_live=yes
ssh_session="$ssh_expected"
ssh_mode=644

# Host probes are the only pieces replaced.
_ssh_unit_enabled() { [ "$ssh_enabled" = yes ]; }
_ssh_socket_live() { [ "$ssh_live" = yes ] && [ "$1" = "$ssh_expected" ]; }
_ssh_home() { printf '%s' "$ssh_home"; }
_ssh_runtime_dir() { printf '%s' /run/user/test; }
_ssh_session_sock() { printf '%s' "$ssh_session"; }
_ssh_file_mode() { printf '%s' "$ssh_mode"; }

ssh_run() {
    doctor_reset
    DOCTOR_ROOT="${1:-$ssh_root}" check_ssh > "$DOCTOR_TEST_TMP/ssh.out" 2>&1
    ssh_out=$(cat "$DOCTOR_TEST_TMP/ssh.out")
}
ssh_healthy() {
    ssh_enabled=yes; ssh_live=yes; ssh_session="$ssh_expected"; ssh_mode=644
    printf '%s\nHost x\n' "$ssh_include" > "$ssh_home/.ssh/config"
}

# Not applicable: no environment.d file, or one without SSH_AUTH_SOCK.
mkdir -p "$DOCTOR_TEST_TMP/ssh-bare"
ssh_run "$DOCTOR_TEST_TMP/ssh-bare"
assert_eq "$ssh_out" "" "ssh: a tree without the env file prints nothing"
mkdir -p "$DOCTOR_TEST_TMP/ssh-novar/environment.d"
echo 'OTHER=1' > "$DOCTOR_TEST_TMP/ssh-novar/environment.d/ssh-agent.conf"
ssh_run "$DOCTOR_TEST_TMP/ssh-novar"
assert_eq "$ssh_out" "" "ssh: an env file without SSH_AUTH_SOCK prints nothing"

# Healthy.
ssh_healthy
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_ERRORS$DOCTOR_NOTICES" "000" "ssh: healthy has no findings"
assert_contains "$ssh_out" "SSH agent" "ssh: prints its group"
assert_contains "$ssh_out" "passphrase once per login" "ssh: healthy says so"

# ssh ignores trailing whitespace on the Include line, CR included.
ssh_healthy; printf '%s\r\nHost x\n' "$ssh_include" > "$ssh_home/.ssh/config"
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_ERRORS$DOCTOR_NOTICES" "000" "ssh: a CRLF first line is healthy"
ssh_healthy; printf '%s  \nHost x\n' "$ssh_include" > "$ssh_home/.ssh/config"
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_ERRORS$DOCTOR_NOTICES" "000" "ssh: a trailing-space first line is healthy"

# Unit not enabled.
ssh_healthy; ssh_enabled=no
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: a disabled unit is one warning"
assert_contains "$ssh_out" "ssh-agent.socket is not enabled" "ssh: names the unit"
assert_contains "$ssh_out" "scripts/ssh/setup.sh" "ssh: the hint runs the setup script"
assert_not_contains "$ssh_out" "passphrase once per login" "ssh: no ok beside a finding"

# Enabled, nothing listening.
ssh_healthy; ssh_live=no
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: a dead socket is one warning"
assert_contains "$ssh_out" "$ssh_expected" "ssh: names the expanded socket path"
assert_contains "$ssh_out" "systemctl --user restart ssh-agent.socket" "ssh: the hint restarts the unit"

# Config missing, then Include not first.
ssh_healthy; rm -f "$ssh_home/.ssh/config"
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: a missing config is one warning"
assert_contains "$ssh_out" "$ssh_include" "ssh: names the Include line"
ssh_healthy; printf 'Host x\n%s\n' "$ssh_include" > "$ssh_home/.ssh/config"
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: an Include that is not first is one warning"

# ssh refuses an Include target that is group or world writable.
ssh_healthy; ssh_mode=664
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: a group-writable fragment is one warning"
assert_contains "$ssh_out" "chmod go-w" "ssh: the hint removes the write bits"
assert_contains "$ssh_out" "$ssh_root/ssh/config" "ssh: names the fragment"
assert_not_contains "$ssh_out" "passphrase once per login" "ssh: no ok beside the mode warning"
ssh_healthy; ssh_mode=644
ssh_run
assert_eq "$DOCTOR_WARNINGS" 0 "ssh: a 644 fragment is healthy"

# The current shell predates the setup.
ssh_healthy; ssh_session=""
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_NOTICES" "01" "ssh: a stale session is a note, not a warning"
assert_contains "$ssh_out" "log out and back in" "ssh: the note says what to do"
assert_not_contains "$ssh_out" "passphrase once per login" "ssh: no ok beside the note"

# Setup script lost its assignments.
ssh_healthy
cp "$ssh_root/scripts/ssh/setup.sh" "$DOCTOR_TEST_TMP/ssh-setup.bak"
echo '# emptied' > "$ssh_root/scripts/ssh/setup.sh"
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: underivable settings are one warning"
assert_contains "$ssh_out" "cannot derive" "ssh: says it cannot derive them"
cp "$DOCTOR_TEST_TMP/ssh-setup.bak" "$ssh_root/scripts/ssh/setup.sh"
