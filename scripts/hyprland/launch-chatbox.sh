#!/bin/bash
# Toggle AI sidebar with aichat in terminal

# Load environment variables from .env file
if [ -f "$HOME/.config/.env" ]; then
    set -a
    source "$HOME/.config/.env"
    set +a
fi

# Check if ai_sidebar window exists in special workspace
WINDOW_ADDR=$(hyprctl clients -j | jq -r '.[] | select(.workspace.name == "special:aichat") | .address' | head -1)

if [ -n "$WINDOW_ADDR" ]; then
	# Window exists, just toggle the special workspace
	hyprctl dispatch 'hl.dsp.workspace.toggle_special("aichat")'
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
	hyprctl dispatch "hl.dsp.exec_cmd([[ghostty --config-file=$HOME/.config/ghostty/ai-sidebar -e aichat -s assistant]], { float = true, workspace = [[special:aichat]] })"

	# Wait for window to appear and retry getting the address
	for _ in 1 2 3 4 5; do
		sleep 0.3
		WINDOW_ADDR=$(hyprctl clients -j | jq -r '.[] | select(.workspace.name == "special:aichat") | .address' | head -1)
		[ -n "$WINDOW_ADDR" ] && break
	done

	if [ -n "$WINDOW_ADDR" ]; then
		# Apply size and position
		hyprctl dispatch "hl.dsp.window.resize({ x = $SIDEBAR_WIDTH, y = $SIDEBAR_HEIGHT, relative = false, window = [[address:$WINDOW_ADDR]] })"
		hyprctl dispatch "hl.dsp.window.move({ x = $X_POS, y = $Y_POS, relative = false, window = [[address:$WINDOW_ADDR]] })"
	fi
fi
