hl.config({
    general = {
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
    },

    dwindle = {
        preserve_split = true,
        smart_split = false,
    },

    master = { new_status = "master" },

    misc = {
        force_default_wallpaper = 1,
        disable_splash_rendering = true,
        disable_hyprland_logo = true,
        key_press_enables_dpms = true,
        mouse_move_enables_dpms = true,
        vrr = 0,
    },

    binds = { disable_keybind_grabbing = false },

    xwayland = {
        enabled = true,
        force_zero_scaling = false,
        use_nearest_neighbor = false,
    },

    cursor = {
        sync_gsettings_theme = true,
        enable_hyprcursor = true,
    },
})

-- Refresh the custom dots immediately whenever their active/occupied state can
-- change. Signal 7 belongs to custom/workspace; each module also has a slow
-- interval as a fallback.
local function refresh_waybar_workspaces()
    hl.exec_cmd("pkill -RTMIN+7 waybar")
end

for _, event in ipairs({
    "workspace.active",
    "window.open",
    "window.destroy",
    "window.move_to_workspace",
}) do
    hl.on(event, refresh_waybar_workspaces)
end
