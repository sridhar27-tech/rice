#!/usr/bin/env bash
# sys_info.sh — Collects CPU/GPU temp, fan speed, and screen refresh rate for Waybar.

# CPU Temperature (k10temp)
CPU_TEMP="N/A"
for name_file in /sys/class/hwmon/hwmon*/name; do
    if [ -f "$name_file" ] && [ "$(cat "$name_file")" = "k10temp" ]; then
        DIR=$(dirname "$name_file")
        if [ -f "$DIR/temp1_input" ]; then
            CPU_TEMP=$(( $(cat "$DIR/temp1_input") / 1000 ))
        fi
        break
    fi
done

# GPU Temperature (Nvidia / AMD)
NVIDIA_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
AMD_TEMP=""
for name_file in /sys/class/hwmon/hwmon*/name; do
    if [ -f "$name_file" ] && [ "$(cat "$name_file")" = "amdgpu" ]; then
        DIR=$(dirname "$name_file")
        if [ -f "$DIR/temp1_input" ]; then
            AMD_TEMP=$(( $(cat "$DIR/temp1_input") / 1000 ))
        fi
        break
    fi
done

GPU_TEMP="N/A"
GPU_SOURCE="N/A"
if [ -n "$NVIDIA_TEMP" ] && [ "$NVIDIA_TEMP" -eq "$NVIDIA_TEMP" ] 2>/dev/null; then
    GPU_TEMP="$NVIDIA_TEMP"
    GPU_SOURCE="Nvidia"
elif [ -n "$AMD_TEMP" ]; then
    GPU_TEMP="$AMD_TEMP"
    GPU_SOURCE="AMD"
fi

# Median filter helper to smooth out erratic sensor spikes/drops
get_median_speed() {
    local sensor_path="$1"
    local cache_file="$2"
    local raw_val=$(cat "$sensor_path" 2>/dev/null || echo 0)
    
    local history=""
    if [ -f "$cache_file" ]; then
        history=$(cat "$cache_file" 2>/dev/null)
    fi
    
    history="$history $raw_val"
    # Keep only the last 5 entries
    history=$(echo $history | tr ' ' '\n' | grep -v '^$' | tail -n 5 | tr '\n' ' ')
    echo "$history" > "$cache_file"
    
    local count=$(echo $history | tr ' ' '\n' | grep -v '^$' | wc -l)
    if [ "$count" -lt 5 ]; then
        echo "$raw_val"
    else
        echo $history | tr ' ' '\n' | sort -n | sed -n '3p'
    fi
}

# Fan Speed (hp-wmi hwmon)
FAN1=0
FAN2=0
for name_file in /sys/class/hwmon/hwmon*/name; do
    if [ -f "$name_file" ] && [ "$(cat "$name_file")" = "hp" ]; then
        DIR=$(dirname "$name_file")
        FAN1=$(get_median_speed "$DIR/fan1_input" "/tmp/waybar_fan1_history")
        FAN2=$(get_median_speed "$DIR/fan2_input" "/tmp/waybar_fan2_history")
        break
    fi
done

# FPS (Active monitor refresh rate)
FPS=$(hyprctl monitors | grep -oP '\d+(?:\.\d+)?(?=\s+at)' | head -n 1 | cut -d. -f1)
FPS=${FPS:-60}

# Output format
TEXT=" ${CPU_TEMP}°C  󰢮 ${GPU_TEMP}°C  󰈐 ${FAN1} RPM  󰍹 ${FPS}Hz"
TOOLTIP="CPU: ${CPU_TEMP}°C\nGPU (${GPU_SOURCE}): ${GPU_TEMP}°C\nFan 1: ${FAN1} RPM\nFan 2: ${FAN2} RPM\nRefresh Rate: ${FPS}Hz"

echo "{\"text\": \"$TEXT\", \"tooltip\": \"$TOOLTIP\"}"
