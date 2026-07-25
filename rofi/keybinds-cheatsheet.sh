#!/usr/bin/env bash
#
# Keybinds Cheatsheet
#
# Renders hypr/config/software/keybinds.conf into a searchable rofi list, so
# the sheet cannot disagree with the bindings it documents. It used to be a
# hand-written printf block, and it had drifted: it advertised a mouse-scroll
# workspace bind that does not exist, omitted every silent-move binding, and
# named Ghostty and Zen in text while the binds resolved $terminal and $browser
# from options/.
#
# Usage: keybinds-cheatsheet.sh [--print]
#   --print   write the sheet to stdout instead of opening rofi
#
# How a line becomes a row:
#
#   * `## Heading` starts a section; sections with no rows are dropped, which
#     is what keeps "Modifier Keys" out of the sheet.
#   * A trailing `#` comment is the label, and wins over everything. `$vars`
#     inside it are resolved through scripts/lib/hypr-vars.sh, the same
#     resolution the doctor's binary check uses.
#   * Without a comment the label comes from the dispatcher table below. An
#     unknown dispatcher falls back to its own name, so a new binding always
#     produces a row — never a silent omission, which is the failure mode this
#     script exists to end.
#   * Rows sharing a section, bind type, modifier set, dispatcher and label are
#     folded into one, with their keys listed together.
#
# The dispatcher and keysym tables below are the one hand-written thing here.
# They are display vocabulary, not a second copy of a target list: nothing
# drifts when a binding changes, and an entry missing from either degrades to
# showing the raw name rather than to a wrong or absent row.
#
set -uo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$self_dir")"

# shellcheck source=../scripts/lib/hypr-vars.sh
source "$root/scripts/lib/hypr-vars.sh"

conf="$root/hypr/config/software/keybinds.conf"
theme="$self_dir/themes/keybinds/main.rasi"

if [ ! -f "$conf" ]; then
    echo "keybinds-cheatsheet: no keybinds at $conf" >&2
    exit 1
fi

# A `%s` marks where the dispatcher's argument belongs. The label with the
# `%s` removed is the row's fold key, which is why "Switch to workspace 1"
# through "…11" become one row reading "Switch to workspace".
declare -A DISPATCH_LABEL=(
    [workspace]="Switch to workspace %s"
    [movetoworkspace]="Move window to workspace %s"
    [movetoworkspacesilent]="Move window to workspace %s silently"
    [togglespecialworkspace]="Toggle special workspace"
    [movefocus]="Move focus %s"
    [movewindow]="Move window %s"
    [resizeactive]="Resize window"
    [killactive]="Close window"
    [exit]="Exit Hyprland"
    [togglefloating]="Toggle floating"
    [fullscreen]="Toggle fullscreen"
    [pseudo]="Toggle pseudo-tiling"
    [pin]="Pin window (always on top)"
    [cyclenext]="Cycle to next window"
    [togglegroup]="Toggle window group"
)

declare -A DIRECTION=([l]="left" [r]="right" [u]="up" [d]="down")

# _trim <string> -> the string without leading or trailing whitespace.
_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# _squeeze <string> -> runs of whitespace collapsed to one space, then trimmed.
# Only used on labels whose `%s` was substituted away.
_squeeze() {
    local s="$1"
    while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done
    _trim "$s"
}

# _key_display <keysym> -> how that key is written on a keyboard.
# Everything unlisted passes through, which covers letters, digits and Fn keys.
_key_display() {
    case "$1" in
        RETURN|Return|KP_Enter) printf 'Enter' ;;
        SPACE|space)            printf 'Space' ;;
        ESCAPE|Escape)          printf 'Esc' ;;
        TAB|Tab)                printf 'Tab' ;;
        EQUAL|equal)            printf '=' ;;
        MINUS|minus)            printf '-' ;;
        period)                 printf '.' ;;
        comma)                  printf ',' ;;
        slash)                  printf '/' ;;
        BACKSPACE)              printf 'Backspace' ;;
        mouse:272)              printf 'Mouse1' ;;
        mouse:273)              printf 'Mouse2' ;;
        mouse_up)               printf 'Scroll up' ;;
        mouse_down)             printf 'Scroll down' ;;
        left|right|up|down)     local k="$1"; printf '%s' "${k^}" ;;
        XF86*)                  printf '%s' "${1#XF86}" ;;
        *)                      printf '%s' "$1" ;;
    esac
}

# _mods_display <raw-mods> -> "Super + Shift", or empty for an unmodified bind.
# `$Mod`-style names are resolved from the assignments in keybinds.conf itself,
# so renaming the modifier variable renames it here too.
_mods_display() {
    local out="" token value
    for token in $1; do
        if [ "${token:0:1}" = '$' ]; then
            value="${MODVAR[${token#\$}]:-${token#\$}}"
        else
            value="$token"
        fi
        value="${value,,}"
        out="${out:+$out + }${value^}"
    done
    printf '%s' "$out"
}

# _expand_vars <text> -> text with every $var replaced by its resolved value.
# This is what lets `# Terminal ($terminal)` read "Terminal (ghostty)".
_expand_vars() {
    local text="$1" out="" name value rest
    while [[ "$text" =~ ^([^$]*)\$([A-Za-z_][A-Za-z0-9_]*)(.*)$ ]]; do
        name="${BASH_REMATCH[2]}"
        rest="${BASH_REMATCH[3]}"
        value="$(hypr_resolve_var "$name" "$root")"
        out="$out${BASH_REMATCH[1]}${value:-\$$name}"
        text="$rest"
    done
    printf '%s%s' "$out" "$text"
}

# _format_keys <key>... -> the key column's list of keys.
# Three or more consecutive digits collapse to a range, and the full set of
# arrow keys collapses to the word every keyboard prints on them.
_format_keys() {
    local -a keys=("$@") out=()
    local n=${#keys[@]} i j k sep

    if [ "$n" -eq 4 ]; then
        local sorted
        sorted="$(printf '%s\n' "${keys[@]}" | sort | tr '\n' ' ')"
        if [ "$sorted" = "Down Left Right Up " ]; then
            printf 'Arrows'
            return
        fi
    fi

    i=0
    while [ "$i" -lt "$n" ]; do
        # Extend j over the longest ascending run of single digits from i.
        j=$i
        while [ $((j + 1)) -lt "$n" ] \
            && [[ "${keys[j]}" =~ ^[0-9]$ ]] \
            && [[ "${keys[j+1]}" =~ ^[0-9]$ ]] \
            && [ "${keys[j+1]}" -eq $(( keys[j] + 1 )) ]; do
            j=$((j + 1))
        done
        if [ $((j - i)) -ge 2 ]; then
            out+=("${keys[i]}-${keys[j]}")
        else
            # Too short to be worth a range: list the keys individually.
            for ((k = i; k <= j; k++)); do
                out+=("${keys[k]}")
            done
        fi
        i=$((j + 1))
    done

    # Two keys read as alternatives; longer lists read as a set.
    [ "${#out[@]}" -eq 2 ] && sep="/" || sep=", "
    local first=1 item
    for item in "${out[@]}"; do
        [ "$first" -eq 1 ] && first=0 || printf '%s' "$sep"
        printf '%s' "$item"
    done
}

# Record separators: \x1f between the fields of a fold key, \x1e between the
# keys accumulated into one row. Both are outside anything a config can hold.
US=$'\x1f'
RS=$'\x1e'

declare -A MODVAR=()
declare -A ROW_SECTION=() ROW_MODS=() ROW_KEYS=() ROW_DESC=() ROW_LABEL=() ROW_N=()
declare -a ORDER=()

section=""
while IFS= read -r line || [ -n "$line" ]; do
    # Modifier assignments sit above the first bind, so a single pass sees
    # them before anything needs them.
    if [[ "$line" =~ ^\$([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*([^#]*) ]]; then
        MODVAR[${BASH_REMATCH[1]}]="$(_trim "${BASH_REMATCH[2]}")"
        continue
    fi

    if [[ "$line" =~ ^##[[:space:]]+(.*)$ ]]; then
        section="$(_trim "${BASH_REMATCH[1]}")"
        continue
    fi

    [[ "$line" =~ ^[[:space:]]*(bind[a-z]*)[[:space:]]*=(.*)$ ]] || continue
    bindtype="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]}"

    # Hyprland ends a line at the first `#`, so the parser and Hyprland can
    # never disagree about where the command stops and the label starts.
    comment=""
    if [[ "$rest" == *"#"* ]]; then
        comment="$(_trim "${rest#*#}")"
        rest="${rest%%#*}"
    fi

    IFS=',' read -r f_mods f_key f_disp f_args <<< "$rest"
    mods="$(_trim "$f_mods")"
    key="$(_trim "$f_key")"
    disp="$(_trim "$f_disp")"
    args="$(_trim "$f_args")"
    [ -n "$key" ] || continue

    if [ -n "$comment" ]; then
        desc="$(_expand_vars "$comment")"
        label="$desc"
    else
        fmt="${DISPATCH_LABEL[$disp]:-}"
        if [ -z "$fmt" ]; then
            # Unknown dispatcher: name it rather than drop the binding.
            desc="$(_squeeze "$disp $args")"
            label="$disp"
        else
            label="$(_squeeze "${fmt//%s/}")"
            # SC2059: the format string is deliberately a variable — it comes
            # from DISPATCH_LABEL above, never from the config being parsed,
            # and carrying `%s` is the whole point of that table.
            # shellcheck disable=SC2059
            case "$disp" in
                cyclenext)
                    [ "$args" = "prev" ] && label="Cycle to previous window"
                    desc="$label"
                    ;;
                movefocus|movewindow)
                    printf -v desc "$fmt" "${DIRECTION[$args]:-$args}"
                    desc="$(_squeeze "$desc")"
                    ;;
                *)
                    if [[ "$args" =~ ^[0-9]+$ ]]; then
                        printf -v desc "$fmt" "$args"
                        desc="$(_squeeze "$desc")"
                    else
                        desc="$label"
                    fi
                    ;;
            esac
        fi
    fi

    sig="$section$US$bindtype$US$mods$US$disp$US$label"
    if [ -z "${ROW_N[$sig]:-}" ]; then
        ORDER+=("$sig")
        ROW_SECTION[$sig]="$section"
        ROW_MODS[$sig]="$(_mods_display "$mods")"
        ROW_KEYS[$sig]="$(_key_display "$key")"
        ROW_DESC[$sig]="$desc"
        ROW_LABEL[$sig]="$label"
        ROW_N[$sig]=1
    else
        ROW_KEYS[$sig]="${ROW_KEYS[$sig]}$RS$(_key_display "$key")"
        ROW_N[$sig]=$(( ROW_N[$sig] + 1 ))
    fi
done < "$conf"

# Two passes: the first settles the key column's width so the descriptions
# line up, the second prints. Both walk ORDER, so file order is preserved.
declare -a COMBOS=() LABELS=() SECTIONS=()
width=0
for sig in "${ORDER[@]}"; do
    IFS="$RS" read -r -a keys <<< "${ROW_KEYS[$sig]}"
    combo="$(_format_keys "${keys[@]}")"
    [ -n "${ROW_MODS[$sig]}" ] && combo="${ROW_MODS[$sig]} + $combo"
    combo="  $combo"

    if [ "${ROW_N[$sig]}" -gt 1 ]; then
        text="${ROW_LABEL[$sig]}"
    else
        text="${ROW_DESC[$sig]}"
    fi

    COMBOS+=("$combo")
    LABELS+=("$text")
    SECTIONS+=("${ROW_SECTION[$sig]}")
    [ "${#combo}" -gt "$width" ] && width="${#combo}"
done

render() {
    local i prev="" first=1
    for i in "${!COMBOS[@]}"; do
        if [ "${SECTIONS[i]}" != "$prev" ]; then
            [ "$first" -eq 1 ] || printf '\n'
            printf '%s\n' "${SECTIONS[i]^^}"
            prev="${SECTIONS[i]}"
            first=0
        fi
        printf '%-*s  %s\n' "$width" "${COMBOS[i]}" "${LABELS[i]}"
    done
}

if [ "${1:-}" = "--print" ]; then
    render
    exit 0
fi

render | rofi -dmenu \
    -p "Keybinds" \
    -theme "$theme" \
    -i \
    -no-custom \
    -select "" \
    -kb-custom-1 "" \
    -kb-accept-entry "" \
    -kb-accept-alt "" \
    -kb-row-select ""
