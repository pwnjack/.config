#!/usr/bin/env bash
# Wire the tracked SSH agent setup into this machine, so a key's passphrase is
# asked once per login: OpenSSH's socket-activated agent holds the key, and
# ssh/config (AddKeysToAgent yes) hands it over on first use. SSH_AUTH_SOCK
# comes from environment.d/ssh-agent.conf, which the systemd user manager reads
# at login; uwsm starts Hyprland under it, so every app and shell inherits it.
#
#   scripts/ssh/setup.sh [--dry-run] [--backup-dir DIR | --no-backup]
#
# ~/.ssh lies outside this repo, so it only gets a pointer: an Include on the
# FIRST line of ~/.ssh/config. First, because ssh applies a line that follows a
# Host or Match block to that block alone. Before the file changes it is copied
# to <backup dir>/.ssh/config, as scripts/lib/deploy.sh does for every config it
# replaces; install.sh passes its own --backup-dir so one install makes one
# backup. A symlinked ~/.ssh/config belongs to someone else's dotfiles and is
# left alone. Idempotent and never interactive.
#
# Test seam: SSH_SETUP_REPO overrides the repo root (where environment.d/ and
# ssh/ are read), so the tests can run against a private copy.
#
# checks/ssh.sh parses SSH_AGENT_UNIT and INCLUDE_LINE from this file, so keep
# each a single plain NAME="value" line.
set -euo pipefail

SSH_AGENT_UNIT="ssh-agent.socket"
# shellcheck disable=SC2088  # ssh expands the tilde itself
INCLUDE_LINE="Include ~/.config/ssh/config"

repo="${SSH_SETUP_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
dry=false
failed=0
backup="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) dry=true ;;
    --no-backup) backup="" ;;
    --backup-dir)
      if [ $# -lt 2 ] || [ -z "$2" ] || [[ $2 == -* ]]; then
        echo "ssh: --backup-dir needs a directory" >&2
        exit 2
      fi
      backup=$2
      shift
      ;;
    *) echo "ssh: unknown option '$1'" >&2; exit 2 ;;
  esac
  shift
done

run() { if $dry; then echo "  would run: $*"; else "$@"; fi; }
have_unit() {
  command -v systemctl >/dev/null 2>&1 \
    && systemctl --user cat "$SSH_AGENT_UNIT" >/dev/null 2>&1
}

# 1. The agent. Socket-activated: nothing runs until a client connects.
if have_unit; then
  echo "ssh: enabling $SSH_AGENT_UNIT"
  if ! run systemctl --user enable --now "$SSH_AGENT_UNIT"; then
    echo "ssh: could not enable $SSH_AGENT_UNIT; the Include is still set up" >&2
    failed=1
  fi
else
  echo "ssh: no $SSH_AGENT_UNIT user unit or no user session; skipping the agent"
fi

# 2. The Include, as the first line of ~/.ssh/config. ssh refuses an Include
# target that is group or world writable, which would break every ssh call.
fragment="$repo/ssh/config"
if [ -f "$fragment" ] && [ $((8#$(stat -c %a -- "$fragment") & 8#022)) -ne 0 ]; then
  echo "ssh: $fragment is group/world writable, which ssh refuses to include; running chmod go-w"
  run chmod go-w -- "$fragment"
fi

ssh_dir="$HOME/.ssh"
config="$ssh_dir/config"
first=""
if [ -f "$config" ]; then IFS= read -r first < "$config" || true; fi
# ssh ignores trailing whitespace, CR included, so the comparison does too.
first=${first%"${first##*[![:space:]]}"}

if [ "$first" = "$INCLUDE_LINE" ]; then
  echo "ssh: $config already includes the tracked fragment"
elif [ -L "$config" ]; then
  echo "ssh: $config is a symlink; left alone. Add this as the first line of its target:" >&2
  echo "  $INCLUDE_LINE" >&2
  exit 1
elif [ ! -e "$config" ]; then
  echo "ssh: creating $config"
  if $dry; then
    echo "  would create $config (mode 600) holding: $INCLUDE_LINE"
  else
    [ -d "$ssh_dir" ] || mkdir -m 700 -- "$ssh_dir"
    (umask 077 && printf '%s\n' "$INCLUDE_LINE" > "$config")
  fi
else
  if [ -n "$backup" ]; then
    if [ -e "$backup/.ssh/config" ] || [ -L "$backup/.ssh/config" ]; then
      echo "ssh: $backup/.ssh/config already exists; not overwriting it" >&2
      exit 1
    fi
    echo "ssh: backing up $config to $backup/.ssh/config"
    run mkdir -p -- "$backup/.ssh"
    run cp -a -- "$config" "$backup/.ssh/config"
  else
    echo "ssh: --no-backup given; not backing up $config"
  fi
  echo "ssh: adding '$INCLUDE_LINE' as the first line of $config"
  if $dry; then
    echo "  would rewrite $config with the Include first, contents and mode kept"
  else
    tmp=$(mktemp "$ssh_dir/.config.XXXXXX")
    trap 'rm -f -- "$tmp"' EXIT
    { printf '%s\n' "$INCLUDE_LINE"; cat -- "$config"; } > "$tmp"
    chmod --reference="$config" -- "$tmp"
    mv -f -- "$tmp" "$config"
    trap - EXIT
  fi
fi

# 3. The running user manager, so units started from now on see the socket.
conf="$repo/environment.d/ssh-agent.conf"
sock=$(sed -n '/^SSH_AUTH_SOCK=/{s///p;q;}' "$conf" 2>/dev/null || true)
if [ -n "$sock" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] && have_unit; then
  # shellcheck disable=SC2016  # the literal environment.d placeholder
  sock=${sock//'${XDG_RUNTIME_DIR}'/$XDG_RUNTIME_DIR}
  if [[ $sock == *'$'* ]]; then
    echo "ssh: SSH_AUTH_SOCK in $conf still holds a variable; skipping set-environment"
  else
    run systemctl --user set-environment "SSH_AUTH_SOCK=$sock"
  fi
fi

# Terminals already open carry the old environment until the next login.
if $dry; then
  echo "ssh: dry run complete; nothing was changed"
else
  echo "ssh: done. Log out and back in so every terminal carries SSH_AUTH_SOCK."
fi
exit "$failed"
