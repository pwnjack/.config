#!/bin/bash
# Toggle AI sidebar with aichat in terminal

# Check if ai_sidebar window exists in special workspace
WINDOW_ADDR=$(hyprctl clients -j | jq -r '.[] | select(.workspace.name == "special:aichat") | .address' | head -1)

if [ -n "$WINDOW_ADDR" ]; then
	# Window exists, just toggle the special workspace
	hyprctl dispatch togglespecialworkspace aichat
else
	# Get monitor dimensions
	MONITOR_HEIGHT=$(hyprctl monitors -j | jq -r '.[0].height')
	MONITOR_WIDTH=$(hyprctl monitors -j | jq -r '.[0].width')

	# Calculate sidebar dimensions (800px wide, with proper padding)
	SIDEBAR_WIDTH=800
	PADDING=10
	SIDEBAR_HEIGHT=$((MONITOR_HEIGHT - (PADDING * 2)))
	X_POS=$((MONITOR_WIDTH - SIDEBAR_WIDTH - PADDING))
	Y_POS=$PADDING

	# Launch ghostty with aichat (themed config and persistent session)
	hyprctl dispatch exec "[float;workspace special:aichat] ghostty --config-file=$HOME/.config/ghostty/ai-sidebar -e aichat -s assistant"

	# Wait for window to appear and retry getting the address
	for i in 1 2 3 4 5; do
		sleep 0.3
		WINDOW_ADDR=$(hyprctl clients -j | jq -r '.[] | select(.workspace.name == "special:aichat") | .address' | head -1)
		[ -n "$WINDOW_ADDR" ] && break
	done

	if [ -n "$WINDOW_ADDR" ]; then
		# Apply size and position
		hyprctl dispatch resizewindowpixel exact $SIDEBAR_WIDTH $SIDEBAR_HEIGHT,address:$WINDOW_ADDR
		hyprctl dispatch movewindowpixel exact $X_POS $Y_POS,address:$WINDOW_ADDR
	fi
fi
