-- -------------------
-- ---- AUTOSTART ----
-- -------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function ()
    hl.exec_cmd("waybar")
    hl.exec_cmd("swaync")
    hl.exec_cmd("nm-applet")
    hl.exec_cmd("awww init")
    hl.exec_cmd("sleep 0.5 && waypaper --restore")
    -- Custom draggable clock widget on workspace 1
    hl.exec_cmd("python ~/.config/hypr/scripts/home_clock.py")
    hl.exec_cmd("hypridle")
    -- Ensure standard scrolling is enabled globally in GTK/GNOME applications
    hl.exec_cmd("gsettings set org.gnome.desktop.peripherals.mouse natural-scroll false")
    hl.exec_cmd("gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll false")
end)
