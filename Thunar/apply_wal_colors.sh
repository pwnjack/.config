#!/bin/bash

# Apply pywal colors to Thunar via GTK 3 user CSS

gtk_css="$HOME/.config/gtk-3.0/gtk.css"
wal_css="$HOME/.cache/wal/colors-waybar.css"

# If wal colors are not available, do nothing
if [[ ! -f "$wal_css" ]]; then
    exit 0
fi

# Ensure gtk.css exists
if [[ ! -f "$gtk_css" ]]; then
    mkdir -p "$HOME/.config/gtk-3.0"
    touch "$gtk_css"
fi

# Extract colors from wal's waybar css
bg=$(grep -m1 "@define-color background" "$wal_css" | awk '{print $3}' | tr -d ';')
fg=$(grep -m1 "@define-color foreground" "$wal_css" | awk '{print $3}' | tr -d ';')
sel=$(grep -m1 "@define-color color5" "$wal_css" | awk '{print $3}' | tr -d ';')
rb=$(grep -m1 "@define-color color1" "$wal_css" | awk '{print $3}' | tr -d ';')

# Fallbacks in case parsing failed
bg=${bg:-#05090C}
fg=${fg:-#cfddde}
sel=${sel:-#8DAFB4}
rb=${rb:-#2A7789}

# Remove old pywal-generated Thunar block from gtk.css
if grep -q "thunar pywal start" "$gtk_css" 2>/dev/null; then
    sed -i '/\/\* thunar pywal start \*\//,/\/\* thunar pywal end \*\//d' "$gtk_css"
fi

# Append new block
{
    echo "/* thunar pywal start */"
    echo "/* Automatically generated - do not edit manually */"
    echo ".thunar,"
    echo ".thunar .view,"
    echo ".thunar toolbar,"
    echo ".thunar scrolledwindow.sidebar treeview.view {"
    echo "    background-color: $bg;"
    echo "    color: $fg;"
    echo "}"
    echo ""
    echo ".thunar .view widget:selected,"
    echo ".thunar treeview *:selected {"
    echo "    background-color: $sel;"
    echo "    color: $bg;"
    echo "}"
    echo ""
    echo ".thunar .view .rubberband,"
    echo ".thunar treeview rubberband,"
    echo ".thunar scrolledwindow.sidebar treeview.view .rubberband {"
    echo "    background-color: $rb;"
    echo "}"
    echo "/* thunar pywal end */"
} >> "$gtk_css"

# Thunar reads GTK theme on startup; existing windows may need restart
