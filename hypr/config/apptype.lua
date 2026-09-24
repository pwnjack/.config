-- Default applications and preferences used by keybinds, autostart and envvars.

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
    editor = read_option("editor", "nvim"), -- TUI editor, opened in the terminal
    cursorTheme = read_option("cursortheme", "Bibata-Modern-Classic"),
    fileManager = "thunar", -- GUI file manager (yazi for CLI)

    -- The package ships this systemd user unit rather than a PATH executable.
    polkitAgent = "hyprpolkitagent.service",
}
