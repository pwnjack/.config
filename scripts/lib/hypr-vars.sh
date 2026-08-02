#!/bin/bash
#
# Resolution of Hyprland `$variable` indirection.
#
# Hyprland substitutes these while parsing its config, so anything that reads a
# config line afterwards has to redo the substitution itself. Two things do:
# the doctor's binary check, which needs to know the command a keybind really
# runs, and the keybinds cheatsheet, which labels `$terminal` with the terminal
# you actually use. One copy means a new variable source is taught once.
#
# Sourced, never executed. It defines a function and nothing else, so sourcing
# it twice in one shell is harmless.
#

# hypr_var_origin <name> -> `options` or `apptype`.
#
# Which of the two sources below defines the variable. Split out so the list of
# options-backed names exists once: hypr_resolve_var needs it to know where to
# read, and the cheatsheet's markdown mode needs it to know which values are a
# per-user preference rather than a repo constant. A second copy of this list
# would be a second source of truth.
hypr_var_origin() {
    case "$1" in
        terminal|browser) printf 'options' ;;
        *)                printf 'apptype' ;;
    esac
}

# hypr_resolve_var <name> <root> -> value on stdout, empty when undefined.
#
# `name` is the bare variable name, without the leading `$`. Two sources, in
# the order the config itself establishes them:
#
#   terminal, browser   hyprland.conf assigns these by reading options/<name>
#                       at parse time ($browser = $(cat …/options/browser)),
#                       so the file is the value.
#   everything else     hypr/config/apptype.conf, `$name = value  # comment`.
#
# Comments are stripped at the first `#`, which is Hyprland's own rule.
hypr_resolve_var() {
    local name="$1" root="$2" value=""

    case "$(hypr_var_origin "$name")" in
        options)
            if [ -f "$root/options/$name" ]; then
                value="$(head -n1 "$root/options/$name")"
            fi
            ;;
        *)
            if [ -f "$root/hypr/config/apptype.conf" ]; then
                # [$] is a character class matching a literal $, which keeps
                # the expression readable and unambiguous to shellcheck.
                value="$(sed -n "s/^[\$]${name}[[:space:]]*=[[:space:]]*//p" \
                    "$root/hypr/config/apptype.conf" | head -n1)"
                value="${value%%#*}"
            fi
            ;;
    esac

    # Trim surrounding whitespace.
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}
