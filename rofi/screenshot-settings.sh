#!/usr/bin/env bash
#
# Screenshot Settings
# Back to the menu, pick a delay, or toggle freezing the screen while selecting.
#
# Freeze is a preference (options/screenshot, read by
# scripts/hyprland/screenshot.sh); the delay is transient state in the cache.
#

freeze_option="$HOME/.config/options/screenshot"

back=$'\uEB6F' timer=$'\U000F13AB' freeze=$'\U000F1933'

chosen=$(printf '%s\n' "$back" "$timer" "$freeze" | rofi -dmenu \
    -theme "$HOME/.config/rofi/themes/screenshot/settings.rasi" \
    -p $'\uF007'" $USER" \
    -mesg "Back | Toggle Timer | Toggle Freeze")

case "$chosen" in
    "$back") ;;
    "$timer") "$HOME/.config/rofi/screenshot-timer.sh" ;;
    "$freeze")
        if grep -qx true "$freeze_option" 2>/dev/null; then
            echo false > "$freeze_option"
            notify-send -i applets-screenshooter-symbolic "Disabled Screenshot Freeze"
        else
            echo true > "$freeze_option"
            notify-send -i applets-screenshooter-symbolic "Enabled Screenshot Freeze" "This may not work on virtual machines"
        fi
        ;;
    *) exit 0 ;;
esac

exec "$HOME/.config/rofi/screenshot.sh"
