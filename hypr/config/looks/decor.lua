return function(colors)
    hl.config({
        general = {
            gaps_in = 4,
            gaps_out = 10,
            border_size = 1,
            col = {
                active_border = colors.foreground_full,
                inactive_border = "rgba(595959aa)",
            },
        },

        decoration = {
            rounding = 18,
            active_opacity = 1.0,
            inactive_opacity = 1.0,

            shadow = { enabled = false },
            blur = {
                enabled = true,
                size = 6,
                passes = 4,
                vibrancy = 0.1696,
                new_optimizations = true,
                xray = false,
            },
        },
    })
end
