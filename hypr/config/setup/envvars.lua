return function(cursor_theme)
    hl.env("XCURSOR_THEME", cursor_theme)
    hl.env("XCURSOR_SIZE", "24")
    hl.env("HYPRCURSOR_THEME", cursor_theme)
    hl.env("HYPRCURSOR_SIZE", "24")
    hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

    -- SSH_AUTH_SOCK for everything Hyprland launches, in both the plain and the
    -- uwsm session (environment.d only reaches the latter). The socket is
    -- OpenSSH's ssh-agent.socket, enabled by scripts/ssh/setup.sh; setup.sh and
    -- scripts/doctor/checks/ssh.sh read the socket name from this line. The
    -- guard matters: concatenating nil would break the whole configuration.
    local runtime = os.getenv("XDG_RUNTIME_DIR")
    if runtime and runtime ~= "" then hl.env("SSH_AUTH_SOCK", runtime .. "/ssh-agent.socket") end
end
