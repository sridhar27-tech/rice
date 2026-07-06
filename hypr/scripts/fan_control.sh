#!/usr/bin/env bash
# fan_control.sh — Adjusts fan speed and sends a notification.

PWM_PATH=$(glob() { echo "$1"; }; glob /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1)

if [ ! -f "$PWM_PATH" ]; then
    notify-send -t 2000 "Fan Control" "Error: Fan control device not found!"
    exit 1
fi

CURRENT_VAL=$(cat "$PWM_PATH")
STEP=25

case "$1" in
    up)
        NEW_VAL=$((CURRENT_VAL + STEP))
        [ $NEW_VAL -gt 255 ] && NEW_VAL=255
        ;;
    down)
        NEW_VAL=$((CURRENT_VAL - STEP))
        [ $NEW_VAL -lt 0 ] && NEW_VAL=0
        ;;
    max)
        NEW_VAL=255
        ;;
    off)
        NEW_VAL=0
        ;;
    *)
        if [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 0 ] && [ "$1" -le 255 ]; then
            NEW_VAL="$1"
        else
            echo "Usage: $0 {up|down|max|off|value}"
            exit 1
        fi
        ;;
esac

# Write the new value (should be writable by wheel group now)
echo "$NEW_VAL" > "$PWM_PATH" 2>/dev/null

if [ $? -eq 0 ]; then
    PCT=$(( NEW_VAL * 100 / 255 ))
    notify-send -r 9991 -t 1500 -i kcmthermal "Fan Control" "Speed: ${PCT}% (${NEW_VAL}/255)"
else
    # Fallback to sudo if permission is not set up yet
    sudo sh -c "echo $NEW_VAL > $PWM_PATH"
    PCT=$(( NEW_VAL * 100 / 255 ))
    notify-send -r 9991 -t 1500 -i kcmthermal "Fan Control" "Speed: ${PCT}% (${NEW_VAL}/255) [sudo]"
fi
