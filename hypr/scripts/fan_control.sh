#!/usr/bin/env bash
# fan_control.sh — Adjusts fan speed and sends a notification.
# Uses flock to serialize key events and debounces hardware writes by 2 seconds.

PWM_PATH=$(glob() { echo "$1"; }; glob /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1)
ENABLE_PATH=$(glob() { echo "$1"; }; glob /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1_enable)

if [ ! -f "$PWM_PATH" ]; then
    notify-send -t 2000 "Fan Control" "Error: Fan control device not found!"
    exit 1
fi

LOCK_FILE="/tmp/fan_control.lock"
PID_FILE="/tmp/fan_control_timer.pid"
TARGET_FILE="/tmp/fan_target_val"

# Execute all calculations and timer scheduling inside a serialized lock
(
    flock -x 200

    # 1. Read current target value (check state file first, fallback to hardware)
    if [ -f "$TARGET_FILE" ]; then
        CURRENT_VAL=$(cat "$TARGET_FILE" 2>/dev/null)
    else
        CURRENT_VAL=$(cat "$PWM_PATH" 2>/dev/null)
    fi
    CURRENT_VAL=${CURRENT_VAL:-0}
    STEP=26

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

    # 2. Save the accumulated target value to state file
    echo "$NEW_VAL" > "$TARGET_FILE"

    # 3. Calculate percentage and notify the user immediately
    PCT=$(( NEW_VAL * 100 / 255 ))
    notify-send -r 9991 -t 1500 -i kcmthermal "Fan Control" "Speed: ${PCT}% (${NEW_VAL}/255)" &

    # 4. Manage the debounce timer
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        # Terminate the previous timer subshell to cancel its pending write
        kill "$OLD_PID" 2>/dev/null
    fi

    # Spawn the new debounced timer (sleep 2 seconds before writing to hardware)
    (
        sleep 2
        TARGET=$(cat "$TARGET_FILE" 2>/dev/null)
        if [ -n "$TARGET" ]; then
            # Ensure manual fan control is enabled
            if [ -f "$ENABLE_PATH" ]; then
                echo "1" > "$ENABLE_PATH" 2>/dev/null
            fi
            # Write target value to hardware sysfs node
            echo "$TARGET" > "$PWM_PATH" 2>/dev/null
            if [ $? -ne 0 ]; then
                notify-send -r 9991 -t 1500 -i dialog-error "Fan Control" "Error: Write failed. Run ~/setup_fan_rules.sh" &
            fi
            # Clean up target state file
            rm -f "$TARGET_FILE"
        fi
        # Clean up PID file
        rm -f "$PID_FILE"
    ) >/dev/null 2>&1 &
    echo "$!" > "$PID_FILE"
    disown

) 200>"$LOCK_FILE"
