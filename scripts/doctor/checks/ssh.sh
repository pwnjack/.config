#!/bin/bash
#
# SSH agent wiring (scripts/ssh/setup.sh): passphrase once per login.
#
# Nothing is restated here. The socket path comes from
# environment.d/ssh-agent.conf, and the unit name and Include line from
# scripts/ssh/setup.sh, which owns them.
#
# Every finding is a WARN: without the agent ssh still works and just asks for
# the passphrase on every use. A shell started before the setup, which lacks
# SSH_AUTH_SOCK until the next login, is only a note.
#
# Two details mirror setup.sh: the first line of ~/.ssh/config is compared
# without trailing whitespace (ssh ignores it, a CR included), and the tracked
# ssh/config fragment is warned about when group or world writable, because ssh
# refuses such an Include target ("Bad owner or permissions") and then every
# ssh call fails.
#
# Trees without environment.d/ssh-agent.conf, or whose file sets no
# SSH_AUTH_SOCK, get no output: the feature does not apply there.

_ssh_unit_enabled() {
    systemctl --user is-enabled --quiet "$1" 2>/dev/null
}

_ssh_socket_live() {
    [ -S "$1" ]
}

_ssh_home() {
    printf '%s' "$HOME"
}

_ssh_runtime_dir() {
    printf '%s' "${XDG_RUNTIME_DIR:-}"
}

_ssh_session_sock() {
    printf '%s' "${SSH_AUTH_SOCK:-}"
}

# _ssh_file_mode <file> — the octal permission bits.
_ssh_file_mode() {
    stat -c %a -- "$1" 2>/dev/null
}

# _ssh_assignment <file> <name> — one plain NAME="value" assignment, or
# nothing when it is missing or duplicated (same rule as _upd_assignment).
_ssh_assignment() {
    awk -v name="$2" '
        $0 ~ "^" name "=\"[^\"]+\"$" {
            value = $0
            sub("^[^\"]*\"", "", value)
            sub("\"$", "", value)
            count++
        }
        END { if (count == 1) print value }
    ' "$1" 2>/dev/null
}

check_ssh() {
    local conf="$DOCTOR_ROOT/environment.d/ssh-agent.conf"
    local setup="$DOCTOR_ROOT/scripts/ssh/setup.sh"
    local fragment="$DOCTOR_ROOT/ssh/config"
    local sock unit include config first="" fix mode found=0 nosock=0

    [ -f "$conf" ] || return 0
    sock=$(sed -n '/^SSH_AUTH_SOCK=/{s///p;q;}' "$conf" 2>/dev/null)
    [ -n "$sock" ] || return 0
    group "SSH agent"

    unit=$(_ssh_assignment "$setup" SSH_AGENT_UNIT)
    include=$(_ssh_assignment "$setup" INCLUDE_LINE)
    if [ -z "$unit" ] || [ -z "$include" ]; then
        warn "cannot derive the agent unit and Include line from scripts/ssh/setup.sh" \
            "git -C $(doctor_q "$DOCTOR_ROOT") diff -- scripts/ssh/setup.sh"
        return 0
    fi
    # The one expansion environment.d performs that this file relies on.
    # shellcheck disable=SC2016
    sock=${sock//'${XDG_RUNTIME_DIR}'/$(_ssh_runtime_dir)}
    # su, sudo -u and cron carry no runtime dir: the socket path is unknowable.
    if [ -z "$(_ssh_runtime_dir)" ] || [[ $sock == *'$'* ]]; then nosock=1; fi
    fix="bash $(doctor_q "$setup")"

    if ! _ssh_unit_enabled "$unit"; then
        warn "$unit is not enabled — ssh asks for the passphrase on every use" "$fix"
        found=1
    elif [ "$nosock" -eq 0 ] && ! _ssh_socket_live "$sock"; then
        warn "nothing is listening at $sock" "systemctl --user restart $(doctor_q "$unit")"
        found=1
    fi

    config="$(_ssh_home)/.ssh/config"
    if [ -f "$config" ] && [ ! -r "$config" ]; then
        warn "$config is not readable" "chmod u+r $(doctor_q "$config")"
        found=1
    else
        if [ -f "$config" ]; then IFS= read -r first 2>/dev/null < "$config" || true; fi
        first=${first%"${first##*[![:space:]]}"}
        if [ "$first" = "$include" ]; then
            :
        elif [ -L "$config" ]; then
            # setup.sh leaves a symlinked config alone, so its hint cannot clear this.
            warn "$config is a symlink whose target does not start with: $include" \
                "add that line at the top of $(doctor_q "$(readlink -f -- "$config")")"
            found=1
        else
            warn "$config does not start with: $include" "$fix"
            found=1
        fi
    fi

    if [ -f "$fragment" ]; then
        mode=$(_ssh_file_mode "$fragment")
        if [[ $mode =~ ^[0-7]+$ ]] && [ $((8#$mode & 8#022)) -ne 0 ]; then
            warn "$fragment is group/world writable — ssh refuses to include it" \
                "chmod go-w $(doctor_q "$fragment")"
            found=1
        fi
    fi

    if [ "$nosock" -eq 1 ]; then
        note "no XDG_RUNTIME_DIR in this shell — cannot check the agent socket"
        found=1
    elif [ "$found" -eq 0 ] && [ "$(_ssh_session_sock)" != "$sock" ]; then
        note "this shell has no SSH_AUTH_SOCK=$sock yet — log out and back in"
        found=1
    fi

    [ "$found" -eq 0 ] && ok "the SSH agent is wired: passphrase once per login"
    return 0
}
