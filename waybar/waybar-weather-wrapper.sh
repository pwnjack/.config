#!/bin/bash
# Wrapper script for waybar-weather that outputs once and exits
timeout 3 waybar-weather 2>/dev/null | grep -v "^time=" | head -1
