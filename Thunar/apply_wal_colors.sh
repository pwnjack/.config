#!/bin/bash
#
# Render the pywal palette as GTK 3 CSS for Thunar.
#
# gtk-3.0/thunar-colors.css is a tracked symlink to the file written here.
# Thunar reads GTK CSS on startup, so open windows keep the old colors.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"

declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
. "$config_dir/scripts/theming/palette.sh"
wal_load

mkdir -p "$cache_dir"

cat > "$cache_dir/thunar-gtk.css" <<EOF
/* Automatically generated - do not edit manually */
.thunar,
.thunar .view,
.thunar toolbar,
.thunar scrolledwindow.sidebar treeview.view {
    background-color: ${wal[0]};
    color: ${wal[7]};
}

.thunar .view widget:selected,
.thunar treeview *:selected {
    background-color: ${wal[5]};
    color: ${wal[0]};
}

.thunar .view .rubberband,
.thunar treeview rubberband,
.thunar scrolledwindow.sidebar treeview.view .rubberband {
    background-color: ${wal[1]};
}
EOF
