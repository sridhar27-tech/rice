#!/usr/bin/env bash

# File path passed by waypaper
WALLPAPER="$1"

# Get current backend from config.ini
CONFIG_FILE="$HOME/.config/waypaper/config.ini"
if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

BACKEND=$(grep -E "^backend\s*=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '[:space:]')

if [ "$BACKEND" = "mpvpaper" ]; then
    # Kill awww daemon so it doesn't overlap the video
    pkill -f awww-daemon
    pkill -x hyprpaper
elif [ "$BACKEND" = "awww" ]; then
    # Kill mpvpaper so the static wallpaper is shown
    pkill -x mpvpaper
    pkill -x hyprpaper
    # Make sure awww-daemon is running
    if ! pgrep -f awww-daemon >/dev/null; then
        awww-daemon &
        sleep 0.3
        # Send the image to the newly started daemon
        awww img "$WALLPAPER"
    fi
elif [ "$BACKEND" = "hyprpaper" ]; then
    # Kill other daemons
    pkill -f awww-daemon
    pkill -x mpvpaper
    # Ensure hyprpaper is running
    if ! pgrep -x hyprpaper >/dev/null; then
        hyprpaper &
        sleep 0.3
    fi
fi
