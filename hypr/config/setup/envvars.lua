return function(apps)
    local cursor_theme = apps.cursorTheme
    hl.env("XCURSOR_THEME", cursor_theme)
    hl.env("XCURSOR_SIZE", "24")
    hl.env("HYPRCURSOR_THEME", cursor_theme)
    hl.env("HYPRCURSOR_SIZE", "24")
    hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

    -- Default programs for tools that ask the environment instead of
    -- mimeapps.list: $BROWSER (gh, Python's webbrowser, xdg-open's fallback on
    -- an unrecognised desktop), $EDITOR and $VISUAL (git, sudoedit, crontab,
    -- yazi) and $TERMINAL (Rofi's launcher for Terminal=true apps, scripts).
    -- They come from options/, so a settings panel change, which reloads
    -- Hyprland, reaches every program started after it; `true` exports them
    -- to systemd and D-Bus-activated apps too, as for SSH_AUTH_SOCK below.
    -- GLib apps and uwsm open Terminal=true entries through xdg-terminal-exec
    -- instead, which scripts/settings/terminal.sh points at the same terminal.
    -- scripts/doctor/checks/defaults.sh reads these lines.
    hl.env("BROWSER", apps.browser, true)
    hl.env("TERMINAL", apps.terminal, true)
    hl.env("EDITOR", apps.editor, true)
    hl.env("VISUAL", apps.editor, true)

    -- SSH_AUTH_SOCK for everything Hyprland launches, in both the plain and the
    -- uwsm session (environment.d only reaches the latter). The final `true`
    -- also imports it into the systemd user manager and the D-Bus activation
    -- environment, which uwsm's fixed export list would leave out: systemd
    -- units and D-Bus-activated apps (Ghostty) need it. The socket is
    -- OpenSSH's ssh-agent.socket, enabled by scripts/ssh/setup.sh; setup.sh and
    -- scripts/doctor/checks/ssh.sh read the socket name from this line. The
    -- guard matters: concatenating nil would break the whole configuration.
    local runtime = os.getenv("XDG_RUNTIME_DIR")
    if runtime and runtime ~= "" then hl.env("SSH_AUTH_SOCK", runtime .. "/ssh-agent.socket", true) end
end
