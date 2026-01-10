#!/bin/bash
#
# Mako Pywal Color Integration
# Applies pywal colors to mako notification daemon
#

# Source pywal colors
source "$HOME/.cache/wal/colors.sh"

# Create mako config with pywal colors
cat > "$HOME/.config/mako/config" << EOF
# Mako Configuration
# Colors automatically generated from wallpaper via pywal
# Last updated: $(date)

# Appearance
font=JetBrains Mono 11
background-color=${background}dd
text-color=${foreground}
border-color=${color4}
border-size=2
border-radius=10
max-icon-size=64

# Behavior
max-visible=5
layer=overlay
default-timeout=5000
ignore-timeout=0

# Position
anchor=top-right
margin=20

# Grouping
group-by=app-name

# Urgency levels
[urgency=low]
border-color=${color2}
default-timeout=3000

[urgency=normal]
border-color=${color4}
default-timeout=5000

[urgency=critical]
border-color=${color1}
background-color=${color1}22
default-timeout=0

# Application specific (examples)
[app-name="Spotify"]
border-color=${color5}

[app-name="Discord"]
border-color=${color6}
EOF

# Reload mako to apply new colors
if pgrep -x mako > /dev/null; then
    makoctl reload
fi
