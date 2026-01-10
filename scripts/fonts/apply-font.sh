#!/usr/bin/env bash

##
## Apply Font Configuration
## Reads font from $HOME/.config/options/font and applies it to all configs
## Created by : @GeodeArc
##

# Read font options
main_font="$(cat $HOME/.config/options/font 2>/dev/null || echo "FiraCode Nerd Font")"
gtk_font="$(cat $HOME/.config/options/font-gtk 2>/dev/null || echo "Cascadia Mono Semi-Bold")"

# Remove quotes if present
main_font=$(echo "$main_font" | sed 's/^"//;s/"$//')
gtk_font=$(echo "$gtk_font" | sed 's/^"//;s/"$//')

echo "Applying fonts..."
echo "Main font: $main_font"
echo "GTK font: $gtk_font"

# Update Rofi font
rofi_font_file="$HOME/.config/rofi/options/font.rasi"
mkdir -p "$(dirname "$rofi_font_file")"
echo "configuration { font: \"$main_font 10\"; }" > "$rofi_font_file"
echo "✓ Updated Rofi font"

# Update hardcoded fonts in Rofi theme files (keybinds, etc.)
find "$HOME/.config/rofi" -name "*.rasi" -type f | while read theme_file; do
    # Skip the font.rasi file itself
    if [[ "$theme_file" == "$rofi_font_file" ]]; then
        continue
    fi
    
    # Update hardcoded font references
    if grep -qE "font:.*\"[^\"]*(FiraCode|JetbrainsMono|Hack|Cascadia|CommitMono)" "$theme_file" 2>/dev/null; then
        # Create backup
        cp "$theme_file" "$theme_file.bak" 2>/dev/null
        
        # Extract size from existing font (e.g., "Font Name 10" -> "10")
        font_size=$(grep -oE "font:.*\"[^\"]* [0-9]+\"" "$theme_file" | grep -oE "[0-9]+" | head -1)
        if [[ -z "$font_size" ]]; then
            font_size="10"
        fi
        
        # Update font references
        sed -i "s|font:[[:space:]]*\"[^\"]*\"|font: \"$main_font $font_size\"|g" "$theme_file"
    fi
done
echo "✓ Updated Rofi theme fonts"

# Update Waybar font (CSS)
waybar_css="$HOME/.config/waybar/style.css"
if [[ -f "$waybar_css" ]]; then
    cp "$waybar_css" "$waybar_css.bak" 2>/dev/null
    sed -i "s|font-family:.*;|font-family: \"$main_font\", \"JetbrainsMono Nerd\", \"Hack Nerd\", sans-serif;|" "$waybar_css"
    echo "✓ Updated Waybar font"
fi

# Update Kitty font
kitty_conf="$HOME/.config/kitty/kitty.conf"
if [[ -f "$kitty_conf" ]]; then
    cp "$kitty_conf" "$kitty_conf.bak" 2>/dev/null
    if grep -q "^font_family" "$kitty_conf"; then
        sed -i "s|^font_family.*|font_family $main_font|" "$kitty_conf"
    else
        sed -i "/^background_opacity/a font_family $main_font" "$kitty_conf"
    fi
    echo "✓ Updated Kitty font"
fi

# Update Ghostty font
ghostty_conf="$HOME/.config/ghostty/config"
if [[ -f "$ghostty_conf" ]]; then
    cp "$ghostty_conf" "$ghostty_conf.bak" 2>/dev/null
    sed -i '/^font-family =/d' "$ghostty_conf"
    if grep -q "^# pywal colors" "$ghostty_conf"; then
        sed -i "/^# pywal colors/i font-family = $main_font" "$ghostty_conf"
    else
        echo "" >> "$ghostty_conf"
        echo "font-family = $main_font" >> "$ghostty_conf"
    fi
    echo "✓ Updated Ghostty font"
fi

# Update Alacritty font
alacritty_conf="$HOME/.config/alacritty/alacritty.toml"
if [[ -f "$alacritty_conf" ]]; then
    cp "$alacritty_conf" "$alacritty_conf.bak" 2>/dev/null
    if grep -q 'normal.family =' "$alacritty_conf"; then
        sed -i "s|normal.family = \".*\"|normal.family = \"$main_font\"|" "$alacritty_conf"
    fi
    echo "✓ Updated Alacritty font"
fi

# Update GTK font
gtk3_conf="$HOME/.config/gtk-3.0/settings.ini"
gtk4_conf="$HOME/.config/gtk-4.0/settings.ini"

for gtk_conf in "$gtk3_conf" "$gtk4_conf"; do
    if [[ -f "$gtk_conf" ]]; then
        cp "$gtk_conf" "$gtk_conf.bak" 2>/dev/null
        if grep -q "^gtk-font-name=" "$gtk_conf"; then
            existing_font=$(grep "^gtk-font-name=" "$gtk_conf" | cut -d'=' -f2-)
            if echo "$existing_font" | grep -q "@wght="; then
                size=$(echo "$existing_font" | sed 's/.* \([0-9]\+\) @wght=.*/\1/')
                weight=$(echo "$existing_font" | sed 's/.*@wght=\([0-9]\+\).*/\1/')
                if [[ -z "$size" ]] || [[ "$size" == "$existing_font" ]]; then size="11"; fi
                if [[ -z "$weight" ]] || [[ "$weight" == "$existing_font" ]]; then
                    sed -i "s|^gtk-font-name=.*|gtk-font-name=$gtk_font $size|" "$gtk_conf"
                else
                    sed -i "s|^gtk-font-name=.*|gtk-font-name=$gtk_font $size @wght=$weight|" "$gtk_conf"
                fi
            else
                size=$(echo "$existing_font" | grep -oE "[0-9]+" | tail -1)
                if [[ -z "$size" ]]; then size="11"; fi
                sed -i "s|^gtk-font-name=.*|gtk-font-name=$gtk_font $size|" "$gtk_conf"
            fi
        else
            echo "gtk-font-name=$gtk_font 11" >> "$gtk_conf"
        fi
        echo "✓ Updated GTK font: $(basename $(dirname $gtk_conf))"
    fi
done

echo ""
echo "Font configuration applied successfully!"
echo "You may need to restart applications for changes to take effect."

