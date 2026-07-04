-- -----------------------
-- ---- LOOK AND FEEL ----
-- -----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 4,
        gaps_out = 10,

        border_size = 2,

        col = {
            active_border   = { colors = {"rgba(c4a7e7ee)", "rgba(9ccfd8ee)"}, angle = 45 },
            inactive_border = "rgba(6e6a86aa)",
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = true,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },

    decoration = {
        rounding       = 12,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 0.92,
        inactive_opacity = 0.85,

        shadow = {
            enabled      = true,
            range        = 15,
            render_power = 3,
            color        = "rgba(35, 33, 54, 0.4)",
        },

        blur = {
            enabled           = true,
            size              = 8,
            passes            = 3,
            vibrancy          = 0.2,
            ignore_opacity    = true,
            new_optimizations = true,
        },
    },
})
