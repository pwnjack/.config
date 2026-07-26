#!/bin/bash
#
# Wrapper for waybar-weather: waits for the network, retries, and always
# emits valid JSON so waybar never renders a broken module.
#
# It also swaps waybar-weather's colour emoji for monochrome Nerd Font
# glyphs. The emoji were the only colour glyphs on an otherwise monochrome
# bar, and being bitmap emoji they ignore the pywal palette entirely.
# Mapped glyphs arrive pre-wrapped in <span size="large"> to match the bar
# scale (13px base, glyph promoted by a fifth) -- see waybar/style.css.
#
# An unmapped condition keeps its emoji rather than being replaced by a
# generic glyph: showing the wrong weather is worse than showing a
# mismatched one, and a stray emoji makes the gap visible so it can be
# added here.
#

TEXT_MAP='{"☀":"<span size=\"large\">󰖙</span>","☁":"<span size=\"large\">󰖐</span>","⛅":"<span size=\"large\">󰖕</span>","🌤":"<span size=\"large\">󰖕</span>","⛈":"<span size=\"large\">󰙾</span>","🌩":"<span size=\"large\">󰖓</span>","🌫":"<span size=\"large\">󰖑</span>","🌦":"<span size=\"large\">󰖗</span>","🌧":"<span size=\"large\">󰖖</span>","🌨":"<span size=\"large\">󰖘</span>","🌑":"<span size=\"large\">󰖔</span>","🌒":"<span size=\"large\">󰖔</span>","🌓":"<span size=\"large\">󰖔</span>","🌔":"<span size=\"large\">󰖔</span>","🌕":"<span size=\"large\">󰖔</span>","🌖":"<span size=\"large\">󰖔</span>","🌗":"<span size=\"large\">󰖔</span>","🌘":"<span size=\"large\">󰖔</span>","🌙":"<span size=\"large\">󰖔</span>"}'
TIP_MAP='{"🌅":"󰖜","🌇":"󰖛"}'

# Function to check network connectivity
check_network() {
    # First check if any network interface is up
    if command -v ip >/dev/null 2>&1; then
        ip route | grep -q "default" || return 1
    fi

    # Then check if we can reach a reliable host
    if command -v ping >/dev/null 2>&1; then
        ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1 || \
        ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1
    else
        # If ping is not available, just check for default route
        ip route | grep -q default
    fi
}

# Wait up to 30 seconds for network to be available
max_wait=30
waited=0
while ! check_network && [ $waited -lt $max_wait ]; do
    sleep 1
    waited=$((waited + 1))
done

# Try to fetch weather data with retries
max_retries=3
retry=0
output=""

while [ $retry -lt $max_retries ] && [ -z "$output" ]; do
    output=$(timeout 10 waybar-weather 2>/dev/null | grep -v "^time=" | head -1)
    if [ -z "$output" ]; then
        sleep 2
        retry=$((retry + 1))
    fi
done

# Output result, or minimal valid JSON if all retries failed, so waybar
# always receives something parseable.
if [ -z "$output" ]; then
    echo '{"text":"","tooltip":"Weather data unavailable"}'
    exit 0
fi

# U+FE0F is the emoji variation selector; it trails most of these glyphs and
# would survive the swap as an invisible stray character. If jq fails for any
# reason the untouched original is emitted rather than nothing.
printf '%s' "$output" | jq -c \
    --argjson text_map "$TEXT_MAP" \
    --argjson tip_map "$TIP_MAP" '
    def strip_vs: gsub("️"; "");
    def swap($m): reduce ($m | to_entries[]) as $e (.; gsub($e.key; $e.value));
    .text = (.text | strip_vs | swap($text_map))
    | if .tooltip then .tooltip = (.tooltip | strip_vs | swap($tip_map)) else . end
' 2>/dev/null || printf '%s' "$output"
