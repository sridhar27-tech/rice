-- --------------------------------
-- ---- WINDOWS AND WORKSPACES ----
-- --------------------------------

-- Layout configurations
hl.config({
    dwindle = {
        preserve_split = true, -- You probably want this
    },
    master = {
        new_status = "master",
    },
    scrolling = {
        fullscreen_on_one_column = true,
    },
    misc = {
        force_default_wallpaper = -1,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = false, -- If true disables the random hyprland logo / anime girl background. :(
    },
})

-- Window rules
local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- Workspace window routing rules for development
hl.window_rule({
    name = "workspace-browser",
    match = { class = "^(firefox|Brave-browser|Google-chrome|Chromium|zen-alpha|zen)$" },
    workspace = "1"
})

hl.window_rule({
    name = "workspace-neovim",
    match = { class = "^(neovim|nvim)$" },
    workspace = "2"
})

hl.window_rule({
    name = "workspace-claude-ai",
    match = { class = "^(claude|claude-code|ai-agent)$" },
    workspace = "3"
})

hl.window_rule({
    name = "workspace-terminals",
    match = { class = "^(kitty)$" },
    workspace = "4"
})

hl.window_rule({
    name = "workspace-music",
    match = { class = "^(Spotify|spotify|amberol|audacious)$" },
    workspace = "5"
})

-- Common utility windows should always float
hl.window_rule({
    name  = "float-pavucontrol",
    match = { class = "^(pavucontrol|org.pulseaudio.pavucontrol)$" },
    float = true
})

hl.window_rule({
    name  = "float-nm-connection-editor",
    match = { class = "^(nm-connection-editor)$" },
    float = true
})

hl.window_rule({
    name  = "float-system-dialogs",
    match = { class = "^(polkit-gnome-authentication-agent-1|org.kde.polkit-kde-authentication-agent-1|Pinentry-gtk)$" },
    float = true
})
