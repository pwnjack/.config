#!/bin/bash
# Wrapper script for waybar-weather that outputs once and exits
# Wait for network connectivity before attempting to fetch weather

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
        [ -n "$(ip route | grep default)" ]
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

# Output result or minimal valid JSON if all retries failed
# This ensures waybar always receives valid JSON and displays the module
if [ -z "$output" ]; then
    echo '{"text":"","tooltip":"Weather data unavailable"}'
else
    echo "$output"
fi