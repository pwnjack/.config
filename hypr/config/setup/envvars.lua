return function(cursor_theme)
    hl.env("XCURSOR_THEME", cursor_theme)
    hl.env("XCURSOR_SIZE", "24")
    hl.env("HYPRCURSOR_THEME", cursor_theme)
    hl.env("HYPRCURSOR_SIZE", "24")
    hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
end
