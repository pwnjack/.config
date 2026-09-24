#!/usr/bin/env bash
#
# Apply options/font and options/font-gtk to every config that names a font.
# Run by the settings panel after either option changes; a nonzero exit makes
# the panel restore the previous option.
#
# Every rofi theme imports rofi/options/font.rasi, so rofi needs one file
# rewritten rather than each theme. Other fonts named inside themes (the
# `feather` icon font, the cheatsheet's monospace) are deliberate and left alone.
#

config_dir="$HOME/.config"

read_font() {
    local value
    value=$(head -n1 "$config_dir/options/$1" 2>/dev/null)
    value=${value#\"}
    printf '%s' "${value%\"}"
}

main_font=$(read_font font)
gtk_font=$(read_font font-gtk)
main_font=${main_font:-FiraCode Nerd Font}
gtk_font=${gtk_font:-Cascadia Mono Semi-Bold}

# Every target quotes the name with double quotes, so one inside it cannot be
# written anywhere safely.
if [[ "$main_font$gtk_font" == *\"* ]]; then
    echo "Font names cannot contain double quotes" >&2
    exit 1
fi

# Escape the characters a sed replacement treats specially (| is the delimiter).
sed_escape() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }
main_sed=$(sed_escape "$main_font")
gtk_sed=$(sed_escape "$gtk_font")

echo "Main font: $main_font"
echo "GTK font:  $gtk_font"

failed=0

# Rofi
printf 'configuration { font: "%s 10"; }\n' "$main_font" > "$config_dir/rofi/options/font.rasi" || failed=1

# Waybar. The declaration may be wrapped over several lines, so the substitution
# runs on the whole file (-z) and [^;]* spans the line break.
waybar_css="$config_dir/waybar/style.css"
if [[ -f "$waybar_css" ]]; then
    sed -z -i -E \
        "s|font-family:[^;]*;|font-family: \"$main_sed\", \"JetbrainsMono Nerd\", \"Hack Nerd\", sans-serif;|" \
        "$waybar_css" || failed=1
fi

# Ghostty
ghostty_conf="$config_dir/ghostty/config"
if [[ -f "$ghostty_conf" ]]; then
    if grep -q '^font-family = ' "$ghostty_conf"; then
        sed -i "s|^font-family = .*|font-family = \"$main_sed\"|" "$ghostty_conf" || failed=1
    else
        printf '\nfont-family = "%s"\n' "$main_font" >> "$ghostty_conf" || failed=1
    fi
fi

# Alacritty (untracked, optional)
alacritty_conf="$config_dir/alacritty/alacritty.toml"
if [[ -f "$alacritty_conf" ]]; then
    sed -i "s|normal.family = \".*\"|normal.family = \"$main_sed\"|" "$alacritty_conf" || failed=1
fi

# GTK 3 and 4. Keep the size and any variable-font weight already configured:
# "Name 11" or "Name 11 @wght=500".
for gtk_conf in "$config_dir/gtk-3.0/settings.ini" "$config_dir/gtk-4.0/settings.ini"; do
    [[ -f "$gtk_conf" ]] || continue
    current=$(sed -n 's/^gtk-font-name=//p' "$gtk_conf" | head -n1)
    size=11 weight=""
    if [[ "$current" =~ ([0-9]+)( @wght=[0-9]+)?$ ]]; then
        size=${BASH_REMATCH[1]}
        weight=${BASH_REMATCH[2]}
    fi
    if [[ -n "$current" ]]; then
        sed -i "s|^gtk-font-name=.*|gtk-font-name=$gtk_sed $size$weight|" "$gtk_conf" || failed=1
    else
        echo "gtk-font-name=$gtk_font $size$weight" >> "$gtk_conf" || failed=1
    fi
done

if [[ "$failed" -ne 0 ]]; then
    echo "Some configs could not be updated" >&2
    exit 1
fi
echo "Fonts applied. Restart open applications to see the change."
