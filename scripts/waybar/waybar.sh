#!/bin/bash

# Waybar rebuilds its tray watcher on reload. Some tray clients, including
# Proton VPN, keep running but do not register themselves with the rebuilt
# watcher, so recover every discoverable StatusNotifierItem after it settles.
restore_tray_items() {
    command -v busctl >/dev/null 2>&1 || return 0

    local attempt service
    sleep 0.2
    for ((attempt = 0; attempt < 20; attempt++)); do
        if busctl --user get-property \
            org.kde.StatusNotifierWatcher \
            /StatusNotifierWatcher \
            org.kde.StatusNotifierWatcher \
            RegisteredStatusNotifierItems >/dev/null 2>&1; then
            break
        fi
        sleep 0.05
    done

    while read -r service _; do
        case "$service" in
            org.kde.StatusNotifierItem-*)
                busctl --user call \
                    org.kde.StatusNotifierWatcher \
                    /StatusNotifierWatcher \
                    org.kde.StatusNotifierWatcher \
                    RegisterStatusNotifierItem s "$service" >/dev/null 2>&1 || true
                ;;
        esac
    done < <(busctl --user --no-pager list 2>/dev/null)
}

if ! pkill -USR2 -x waybar 2>/dev/null; then
    waybar &
fi

restore_tray_items
