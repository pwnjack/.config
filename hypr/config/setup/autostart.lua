return function(apps)
    hl.on("hyprland.start", function()
        -- System UI components
        hl.exec_cmd("waybar")
        hl.exec_cmd("swaync")
        hl.exec_cmd("swayosd-server")

        -- Wallpaper management
        hl.exec_cmd("awww-daemon")
        hl.exec_cmd("$HOME/.config/scripts/hyprland/restore-wallpaper.sh")
        hl.exec_cmd("$HOME/.config/sddm/watch_wallpaper.sh")

        -- System services
        hl.exec_cmd("hypridle")
        hl.exec_cmd("hyprsunset")
        hl.exec_cmd("systemctl --user start " .. apps.polkitAgent)
        hl.exec_cmd("wl-paste --type text --watch cliphist store")
        hl.exec_cmd("wl-paste --type image --watch cliphist store")

        -- User startup script
        hl.exec_cmd("$HOME/.config/scripts/hyprland/startup.sh")
    end)
end
