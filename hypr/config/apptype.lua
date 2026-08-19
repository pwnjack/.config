-- Default applications used by keybinds and autostart.

local home = os.getenv("HOME") or ""

local function read_option(name, fallback)
    local file = io.open(home .. "/.config/options/" .. name, "r")
    if not file then
        return fallback
    end

    local value = file:read("*l")
    file:close()
    if not value or value == "" then
        return fallback
    end
    return value
end

return {
    browser = read_option("browser", "firefox"),
    terminal = read_option("terminal", "ghostty"),
    fileManager = "thunar", -- GUI file manager (yazi for CLI)
    textEditor = "nvim", -- Text editor (neovim)

    -- The package ships this systemd user unit rather than a PATH executable.
    polkitAgent = "hyprpolkitagent.service",
}
