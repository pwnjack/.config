#!/bin/bash
#
# Binary availability for everything the keybinds and autostart invoke.
#
# Targets are extracted from keybinds.conf and autostart.conf, so binding a
# new key extends coverage automatically. Hyprland's `$variable` indirection
# is resolved the way Hyprland resolves it: $terminal and $browser from
# options/, everything else from hypr/config/apptype.conf.
#
# Everything here is WARN, never ERROR. A keybind pointing at an absent
# binary means one shortcut silently does nothing; the session still starts
# and every other binding still works.
#
# Scope decisions:
#
#   * Scripts under scripts/ are deliberately NOT scanned for the commands
#     they invoke. Reliably extracting invocations from bash defeats naive
#     parsing (variables, heredocs, conditionals, functions), and this repo's
#     scripts already guard with `command -v`. Their paths are still
#     validated by the reference check.
#
#   * Command targets that are paths (/…, ~/…, $HOME/…) are skipped here.
#     references.sh owns "does this file exist"; duplicating it would report
#     one broken keybind twice under two severities.
#
#   * Pipelines and command lists are split, so every segment's binary is
#     checked. `cliphist list | rofi -dmenu | wl-copy` is one keybind but
#     three binaries, and any of them missing breaks the shortcut.
#
#   * A missing binary is reported once globally, not once per binding or
#     per file. Installing it fixes every site at once, so repeating the
#     finding would pad the report without adding an action.
#
# Accepted risks:
#
#   * A token containing `=` is treated as an environment assignment and
#     skipped, so `FOO=bar somecmd` checks nothing. No such binding exists
#     in this repo, and the alternative (guessing which token is the
#     command) is worse than a known blind spot.
#
#   * Command substitutions inside arguments are not evaluated, so a binary
#     invoked only from inside `$( … )` is not checked.
#

# Sourced here rather than from doctor.sh because the test suite sources this
# module directly, without the entry point.
# shellcheck source=../../lib/hypr-vars.sh
source "${BASH_SOURCE[0]%/*}/../../lib/hypr-vars.sh"

# Names already reported this run, space-delimited and space-padded.
_BIN_SEEN=""

# _bin_resolve_var <name> -> value, or empty when undefined.
# The rules live in scripts/lib/hypr-vars.sh, shared with the keybinds
# cheatsheet, which resolves the same variables for display.
_bin_resolve_var() {
    hypr_resolve_var "$1" "$DOCTOR_ROOT"
}

# _bin_check_token <token> <origin-file>
_bin_check_token() {
    local token="$1" origin="$2" bin

    [ -n "$token" ] || return 0

    # Paths belong to the reference check. Both `~` and `$HOME` are quoted:
    # an unquoted ~/* in a case pattern is tilde-expanded to the running
    # user's home, so it would never match the literal "~/" in a config.
    case "$token" in
        /*|'~'/*|'$HOME'/*) return 0 ;;
    esac

    # Environment assignments are not commands.
    case "$token" in
        *=*) return 0 ;;
    esac

    if [ "${token:0:1}" = '$' ]; then
        bin="$(_bin_resolve_var "${token#\$}")"
        if [ -z "$bin" ]; then
            warn "$origin invokes $token, which is not defined anywhere" \
                 "define it in hypr/config/apptype.conf, or in options/$(doctor_q "${token#\$}")"
            return 0
        fi
    else
        bin="$token"
    fi

    # Report each missing binary once, however many places bind it.
    case "$_BIN_SEEN" in
        *" $bin "*) return 0 ;;
    esac
    _BIN_SEEN="$_BIN_SEEN $bin "

    command -v "$bin" >/dev/null 2>&1 && return 0

    # A package of the same name being installed changes the diagnosis
    # completely: the config is not missing a package, it is naming something
    # that was never executable from PATH, so the line silently does nothing.
    if _bin_package_installed "$bin"; then
        warn "$origin invokes '$bin', which is installed but ships no executable on PATH — this line silently does nothing" \
             "pacman -Ql $(doctor_q "$bin") | grep -E 'bin/|systemd' to find the real entry point"
    else
        warn "$origin invokes '$bin', which is not installed" \
             "pacman -S $(doctor_q "$bin")   (or drop it from $(doctor_q "$origin"))"
    fi
}

# _bin_package_installed <name> -> 0 when a package of that name is installed.
# Its own function so the tests can stub it: the real answer is specific to
# whichever machine happens to be running the suite.
_bin_package_installed() {
    command -v pacman >/dev/null 2>&1 || return 1
    pacman -Q "$1" >/dev/null 2>&1
}

# _bin_check_command <raw-command-string> <origin-file>
# Splits pipelines and command lists, then checks each segment's first token.
_bin_check_command() {
    local raw="$1" origin="$2" segment first

    raw="${raw%&}"

    while read -r segment; do
        # Leading whitespace would otherwise become the first field.
        read -r first _ <<< "$segment"
        _bin_check_token "$first" "$origin"
        _bin_check_systemd_unit "$segment" "$origin"
    done < <(printf '%s\n' "$raw" | sed 's/&&/\n/g; s/||/\n/g; s/[|;]/\n/g')
}

# _bin_unit_exists <unit> -> 0 when systemd knows that user unit.
# Its own function so tests can stub it; the real answer is host-specific.
_bin_unit_exists() {
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl --user cat "$1" >/dev/null 2>&1
}

# _bin_check_systemd_unit <command-segment> <origin-file>
#
# `systemctl --user start foo.service` passes the binary check trivially —
# systemctl is always installed — so without this the unit name is unchecked
# and a typo fails silently on every login. That is exactly the failure this
# module exists to catch: it is how `exec-once = $polkitAgent` went unnoticed,
# and routing that fix through systemctl would otherwise have blinded the
# check that found it.
_bin_check_systemd_unit() {
    local segment="$1" origin="$2" unit=""

    case "$segment" in
        systemctl*' --user '*) ;;
        *) return 0 ;;
    esac

    # Last whitespace-delimited field, which is the unit for the start/restart/
    # enable forms this repo uses. Anything else is left alone.
    case "$segment" in
        *' start '*|*' restart '*|*' enable '*) unit="${segment##* }" ;;
        *) return 0 ;;
    esac

    [ -n "$unit" ] || return 0
    case "$unit" in
        -*) return 0 ;;   # a flag, not a unit
    esac

    # The unit is usually reached through a Hyprland variable — this repo
    # writes `systemctl --user start $polkitAgent` — so resolve it the same
    # way the binary check does. Skipping `$…` tokens here would silently
    # exempt precisely the line this check was added for.
    if [ "${unit:0:1}" = '$' ]; then
        unit="$(_bin_resolve_var "${unit#\$}")"
        [ -n "$unit" ] || return 0   # undefined: already reported as a token
    fi

    if ! _bin_unit_exists "$unit"; then
        warn "$origin starts the systemd user unit '$unit', which systemd does not know" \
             "systemctl --user list-unit-files | grep $(doctor_q "${unit%%.*}")"
    fi
}

# _bin_scan <file-relative-to-root> <sed-extraction-expression>
_bin_scan() {
    local conf="$1" expr="$2" line

    [ -f "$DOCTOR_ROOT/$conf" ] || return 0

    while read -r line; do
        _bin_check_command "$line" "$conf"
    done < <(sed -n "$expr" "$DOCTOR_ROOT/$conf")
}

check_binaries() {
    group "Binaries"

    local before_e="$DOCTOR_ERRORS" before_w="$DOCTOR_WARNINGS" before_n="$DOCTOR_NOTICES"
    _BIN_SEEN=""

    # Only `exec` binds name a command; killactive, fullscreen, movefocus and
    # friends are dispatchers and must never be parsed as binaries.
    _bin_scan "hypr/config/software/keybinds.conf" \
        's/^[[:space:]]*bind[a-z]*[[:space:]]*=.*[[:space:]]exec,[[:space:]]*//p'

    _bin_scan "hypr/config/setup/autostart.conf" \
        's/^[[:space:]]*exec-once[[:space:]]*=[[:space:]]*//p'

    if [ "$DOCTOR_ERRORS" = "$before_e" ] \
        && [ "$DOCTOR_WARNINGS" = "$before_w" ] \
        && [ "$DOCTOR_NOTICES" = "$before_n" ]; then
        ok "every binary referenced by keybinds and autostart is installed"
    fi
}
