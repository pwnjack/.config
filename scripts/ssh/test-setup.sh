#!/bin/bash
#
# Tests for scripts/ssh/setup.sh.
#
# Standalone, exit 1 on any failure. Every case runs the script as a subprocess
# against its own throwaway HOME, with systemctl replaced by a stub on PATH that
# logs its arguments, so nothing touches the real ~/.ssh or user manager.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$TEST_DIR/setup.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

# The literal is the point: it is what ssh reads, unexpanded.
# shellcheck disable=SC2088
INC='Include ~/.config/ssh/config'

mkdir -p "$TMP/bin"
cat > "$TMP/bin/systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$*" in
    "--user cat "*) [ "${STUB_UNIT:-present}" = present ] ;;
    *) exit 0 ;;
esac
STUB
chmod +x "$TMP/bin/systemctl"
export PATH="$TMP/bin:$PATH"
export STUB_LOG="$TMP/systemctl.log"

n=0
# fresh_home -- a new, empty HOME in $h.
fresh_home() { n=$((n + 1)); h="$TMP/home$n"; mkdir -p "$h"; }
# setup <args...> -- run the script against $h; sets $out and $rc.
setup() {
    : > "$STUB_LOG"
    out=$(HOME="$h" XDG_RUNTIME_DIR=/run/user/test bash "$SETUP" "$@" 2>&1) && rc=0 || rc=$?
}
mode() { stat -c %a -- "$1"; }
exists() { if [ -e "$1" ] || [ -L "$1" ]; then echo yes; else echo no; fi; }
# existing_config <mode> -- a config with a Host block and no Include.
existing_config() {
    mkdir -p "$h/.ssh"
    printf 'Host example\n    User someone\n' > "$h/.ssh/config"
    chmod "$1" "$h/.ssh/config"
    cp -a "$h/.ssh/config" "$TMP/original$n"
}

# --- fresh machine -----------------------------------------------------------
fresh_home
setup --backup-dir "$h/bak"
assert_eq "$rc" 0 "fresh: exits 0"
assert_eq "$(mode "$h/.ssh")" 700 "fresh: ~/.ssh is created private"
assert_eq "$(mode "$h/.ssh/config")" 600 "fresh: the config is created private"
assert_eq "$(cat "$h/.ssh/config")" "$INC" "fresh: the config holds just the Include"
assert_eq "$(exists "$h/bak")" no "fresh: nothing to back up"
assert_contains "$(cat "$STUB_LOG")" "--user enable --now ssh-agent.socket" \
    "fresh: the agent socket is enabled"
assert_contains "$(cat "$STUB_LOG")" \
    "--user set-environment SSH_AUTH_SOCK=/run/user/test/ssh-agent.socket" \
    "fresh: the running user manager gets SSH_AUTH_SOCK"

# --- existing config ---------------------------------------------------------
fresh_home
existing_config 640
setup --backup-dir "$h/bak"
assert_eq "$rc" 0 "existing: exits 0"
assert_eq "$(cmp -s "$TMP/original$n" "$h/bak/.ssh/config" && echo same)" same \
    "existing: the backup is byte-for-byte the old file"
assert_eq "$(mode "$h/bak/.ssh/config")" 640 "existing: the backup keeps the mode"
assert_eq "$(head -n 1 "$h/.ssh/config")" "$INC" "existing: the Include comes first"
assert_eq "$(tail -n +2 "$h/.ssh/config")" "$(cat "$TMP/original$n")" \
    "existing: the old contents follow unchanged"
assert_eq "$(mode "$h/.ssh/config")" 640 "existing: the config keeps its mode"
assert_contains "$out" "$h/bak/.ssh/config" "existing: says where the backup went"

# --- second run is a no-op ---------------------------------------------------
cp -a "$h/.ssh/config" "$TMP/after$n"
setup --backup-dir "$h/bak2"
assert_eq "$rc" 0 "rerun: exits 0"
assert_eq "$(cmp -s "$TMP/after$n" "$h/.ssh/config" && echo same)" same \
    "rerun: the config is unchanged"
assert_eq "$(exists "$h/bak2")" no "rerun: no backup when nothing changes"

# --- Include present but not first -------------------------------------------
fresh_home
mkdir -p "$h/.ssh"
printf 'Host example\n%s\n' "$INC" > "$h/.ssh/config"
setup --backup-dir "$h/bak"
assert_eq "$(head -n 1 "$h/.ssh/config")" "$INC" "late include: a copy is put first"
assert_eq "$(exists "$h/bak/.ssh/config")" yes "late include: backed up first"

# --- --no-backup and the default backup dir ----------------------------------
fresh_home
existing_config 600
setup --no-backup
assert_eq "$(head -n 1 "$h/.ssh/config")" "$INC" "no-backup: still changed"
assert_eq "$(compgen -G "$h/.config-backup-*" || echo none)" none "no-backup: no backup made"

fresh_home
existing_config 600
setup
assert_eq "$(compgen -G "$h/.config-backup-*/.ssh/config" >/dev/null && echo yes)" yes \
    "default: backs up under ~/.config-backup-<timestamp>"

# --- --dry-run writes nothing ------------------------------------------------
fresh_home
existing_config 600
before=$(find "$h" -printf '%p %m %s %T@\n' | sort)
setup --dry-run --backup-dir "$h/bak"
after=$(find "$h" -printf '%p %m %s %T@\n' | sort)
assert_eq "$rc" 0 "dry run: exits 0"
assert_eq "$after" "$before" "dry run: nothing under HOME changes"
assert_eq "$(grep -vc '^--user cat ' "$STUB_LOG")" 0 "dry run: systemctl is only queried"
assert_contains "$out" "would" "dry run: says what it would do"

fresh_home
setup --dry-run
assert_eq "$(exists "$h/.ssh")" no "dry run: a fresh HOME gets no ~/.ssh"

# --- no unit -----------------------------------------------------------------
fresh_home
STUB_UNIT=absent setup
assert_eq "$rc" 0 "no unit: exits 0"
assert_contains "$out" "skipping the agent" "no unit: says it skips the agent"
assert_eq "$(cat "$h/.ssh/config")" "$INC" "no unit: the Include is still written"
assert_not_contains "$(cat "$STUB_LOG")" "enable" "no unit: nothing is enabled"

# --- symlinked config is left alone ------------------------------------------
fresh_home
mkdir -p "$h/.ssh"
printf 'Host x\n' > "$h/elsewhere"
ln -s "$h/elsewhere" "$h/.ssh/config"
setup --backup-dir "$h/bak"
assert_eq "$rc" 1 "symlink: exits 1"
assert_eq "$(readlink "$h/.ssh/config")" "$h/elsewhere" "symlink: the link is untouched"
assert_eq "$(cat "$h/elsewhere")" "Host x" "symlink: its target is untouched"
assert_contains "$out" "$INC" "symlink: names the line to add"

# --- bad arguments -----------------------------------------------------------
fresh_home
setup --nonsense
assert_eq "$rc" 2 "args: an unknown option exits 2"
setup --backup-dir
assert_eq "$rc" 2 "args: --backup-dir without a value exits 2"

test_summary "ssh setup"
