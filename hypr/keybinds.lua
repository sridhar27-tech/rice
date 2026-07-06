-- ---------------------
-- ---- KEYBINDINGS ----
-- ---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind("ALT + F4", hl.dsp.window.close())
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))

-- Legacy/alias binds
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd("kitty @ --to unix:/tmp/kitty launch || kitty"))
local closeWindowBind = hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle only
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("firefox"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("waypaper")) -- Wallpaper browser
hl.bind("ALT + Tab", function ()
    local active_ws = hl.get_active_workspace()
    local workspaces = hl.get_workspaces()

    -- collect and sort workspace ids that exist
    local ids = {}
    for _, ws in ipairs(workspaces) do
        table.insert(ids, ws.id)
    end
    table.sort(ids)

    local next_ws = ids[1]
    if active_ws then
        for _, id in ipairs(ids) do
            if id > active_ws.id then
                next_ws = id
                break
            end
        end
    end

    hl.dispatch(hl.dsp.focus({ workspace = next_ws }))
end)


-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Resize windows with mainMod + ALT + arrow keys
hl.bind(mainMod .. " + ALT + left",  hl.dsp.window.resize({ x = -40, y = 0, relative = true}), { repeating = true })
hl.bind(mainMod .. " + ALT + right", hl.dsp.window.resize({ x = 40, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + ALT + up",    hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })
hl.bind(mainMod .. " + ALT + down",  hl.dsp.window.resize({ x = 0, y = 40, relative = true }), { repeating = true })

-- Swap windows with ALT + SHIFT + arrow keys
hl.bind("ALT + SHIFT + left",  hl.dsp.window.swap({ direction = "l" }))
hl.bind("ALT + SHIFT + right", hl.dsp.window.swap({ direction = "r" }))
hl.bind("ALT + SHIFT + up",    hl.dsp.window.swap({ direction = "u" }))
hl.bind("ALT + SHIFT + down",  hl.dsp.window.swap({ direction = "d" }))


-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- screenshot
hl.bind(
    "ALT + PRINT",
    hl.dsp.exec_cmd([[sh -c 'mkdir -p "$HOME/Pictures/Screenshots" && grim "$HOME/Pictures/Screenshots/$(date +%F_%H-%M-%S).png"']])
)

hl.bind(
    "SHIFT + PRINT",
    hl.dsp.exec_cmd([[sh -c 'mkdir -p "$HOME/Pictures/Screenshots" && grim -g "$(slurp)" "$HOME/Pictures/Screenshots/$(date +%F_%H-%M-%S).png"']])
)

-- fan control
hl.bind(
    "SUPER + SHIFT + Up",
    hl.dsp.exec_cmd("bash ~/.config/hypr/scripts/fan_control.sh up"),
    { repeating = true }
)

hl.bind(
    "SUPER + SHIFT + Down",
    hl.dsp.exec_cmd("bash ~/.config/hypr/scripts/fan_control.sh down"),
    { repeating = true }
)