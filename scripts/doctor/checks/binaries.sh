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

# Names already reported this run, space-delimited and space-padded.
_BIN_SEEN=""

# _bin_resolve_var <name> -> value, or empty when undefined.
# Mirrors how Hyprland resolves the variables used in keybinds.conf.
_bin_resolve_var() {
    local name="$1" value=""

    case "$name" in
        terminal|browser)
            if [ -f "$DOCTOR_ROOT/options/$name" ]; then
                value="$(head -n1 "$DOCTOR_ROOT/options/$name")"
            fi
            ;;
        *)
            if [ -f "$DOCTOR_ROOT/hypr/config/apptype.conf" ]; then
                # [$] is a character class matching a literal $, which keeps
                # the expression readable and unambiguous to shellcheck.
                value="$(sed -n "s/^[\$]${name}[[:space:]]*=[[:space:]]*//p" \
                    "$DOCTOR_ROOT/hypr/config/apptype.conf" | head -n1)"
                value="${value%%#*}"
            fi
            ;;
    esac

    # Trim surrounding whitespace.
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
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

    if ! command -v "$bin" >/dev/null 2>&1; then
        warn "$origin invokes '$bin', which is not installed" \
             "pacman -S $(doctor_q "$bin")   (or drop it from $(doctor_q "$origin"))"
    fi
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
    done < <(printf '%s\n' "$raw" | sed 's/&&/\n/g; s/||/\n/g; s/[|;]/\n/g')
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
