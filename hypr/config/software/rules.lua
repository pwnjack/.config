-- Window rules

hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})

-- Floating apps
hl.window_rule({ name = "float-pavucontrol", match = { class = "^(org.pulseaudio.pavucontrol)$" }, float = true })
hl.window_rule({ name = "float-blueman", match = { title = "^(blueman-manager)$" }, float = true })
hl.window_rule({ name = "float-network-editor", match = { class = "^(nm-connection-editor)$" }, float = true })
hl.window_rule({ name = "float-waypaper", match = { class = "^(waypaper)$" }, float = true })
hl.window_rule({ name = "resources", match = { class = "^(net.nokyan.Resources)$" }, float = true, size = "1150 600" })
hl.window_rule({ name = "float-calculator", match = { class = "^(Calculator)$" }, float = true })

-- GTK file pickers
hl.window_rule({
    name = "float-file-picker",
    match = { title = "^(Open Files|Open Folder|Select Image|Change Download Location|File Picker)$" },
    float = true,
})
hl.window_rule({ name = "float-portal-picker", match = { class = "^(xdg-desktop-portal-gtk)$" }, float = true })

-- AI sidebar (Super+A)
hl.window_rule({
    name = "ai-sidebar",
    match = { title = "^(aichat)$" },
    float = true,
    workspace = "special:aichat",
    size = "800 95%",
    move = "100%-810 2.5%",
    opacity = "0.95",
    dim_around = true,
})

-- Browser picture-in-picture
hl.window_rule({
    name = "picture-in-picture",
    match = { title = "^(Picture-in-Picture)$" },
    float = true,
    pin = true,
    move = "69.5% 4%",
})

-- Game window rules. See docs/gaming-wow.md before changing these.
hl.window_rule({
    name = "battlenet-launcher",
    match = { class = "^(battle.net.exe)$" },
    float = true,
    size = "1280 720",
    center = true,
})
hl.window_rule({
    name = "battlenet-gamescope",
    match = { class = "^(gamescope)$", title = "^(Battle.net)" },
    float = true,
    size = "1280 720",
    center = true,
})

local function game_rule(name, match)
    hl.window_rule({
        name = name,
        match = match,
        workspace = "5",
        fullscreen = true,
        immediate = true,
        no_blur = true,
        no_shadow = true,
        decorate = false,
        idle_inhibit = "fullscreen",
    })
end

game_rule("wow-classic", { class = "^(WowClassic.exe)$" })
game_rule("wow-gamescope", { class = "^(gamescope)$", title = "^(World of Warcraft)$" })

-- Layer rules
local function layer(name, namespace, effects)
    effects.name = name
    effects.match = { namespace = namespace }
    hl.layer_rule(effects)
end

layer("blur-waybar", "^(waybar)$", { blur = true, ignore_alpha = 0.5 })
layer("blur-swaync-control-center", "^(swaync-control-center)$", { blur = true, ignore_alpha = 0.1 })
layer("blur-swaync-notifications", "^(swaync-notification-window)$", { blur = true, ignore_alpha = 0.1 })
layer("blur-settings-panel", "^(settings-panel)$", { blur = true, ignore_alpha = 0.1 })
