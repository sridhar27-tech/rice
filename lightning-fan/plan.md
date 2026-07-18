# Lightning Fan — Implementation Plan

Custom fan control UI and daemon for HP Omen (AMD Ryzen 7 7000 series, RTX 4060) on EndeavourOS/Hyprland. Replaces hotkey-based control with a dedicated React/TS Tauri UI and a background daemon.

## 1. Core Architecture

The application is split into two components:
1. **Daemon (`lightning-faud`, Rust)**: Runs in the background (as a user systemd service or system service). It is the only process with write access to the fan sysfs nodes.
2. **Frontend (Tauri + React/TypeScript)**: User-space GUI displaying telemetry, curves, and sliders. Communicates with the daemon over a Unix Domain Socket.

```
┌─────────────────────────┐     Unix Socket      ┌─────────────────────────┐
│        Frontend         │                      │         Daemon          │
│ (Tauri + React/TS UI)   │ ◄── JSON Telemetry ──│    (lightning-faud)     │
│      runs as user       │ ─── JSON Commands ──►│   writes hwmon/EC nodes │
└─────────────────────────┘                      └─────────────────────────┘
```

* **Socket Path**: `/run/user/1000/lightning-fan.sock` (runs securely in the user's runtime directory, avoiding root socket requirement).
* **Hardware Write Node**: `/sys/class/hwmon/hwmon8/pwm1` (accessible via the `wheel` group using custom udev rules).
* **Hardware Mode Node**: `/sys/class/hwmon/hwmon8/pwm1_enable` (manual/auto toggle).

---

## 2. Hardware Interfaces (HP Omen)

Through system discovery, the following interfaces are identified:
* **Controller**: `hp-wmi` platform driver (exposing hwmon interface, e.g., `/sys/class/hwmon/hwmon8`).
* **Telemetry**:
  * **CPU Fan Speed**: `/sys/class/hwmon/hwmon8/fan1_input` (RPM).
  * **GPU Fan Speed**: `/sys/class/hwmon/hwmon8/fan2_input` (RPM).
  * **CPU Temperature**: `/sys/class/hwmon/hwmon6/temp1_input` (k10temp package temperature).
  * **GPU Temperature**: Nvidia GPU temperature queried via `nvidia-smi` (or `/sys/class/hwmon/hwmon3/temp1_input` for integrated AMD GPU).
* **Fan Control**:
  * **Target PWM**: `/sys/class/hwmon/hwmon8/pwm1` (0-255 duty cycle. Controls both fans together on this chassis).
  * **PWM Enable**: `/sys/class/hwmon/hwmon8/pwm1_enable` (`1` = Manual control, `0` = BIOS auto control).

---

## 3. Safety Layer (Daemon-Side)

1. **Path Whitelist**: Hardcoded paths for `pwm1` and `pwm1_enable` to prevent path traversal or writing to arbitrary sysfs paths.
2. **Value Clamps**:
   * Any duty cycle request outside 0-255 is rejected or clamped.
   * Hard minimum duty cycle floor of `12` (minimum starting speed) when manual mode is engaged to prevent stalls under load.
3. **Debouncing & Rate Limits**: Enforces a minimum interval of 1 second between consecutive writes to the EC sysfs nodes to prevent hardware fatigue.
4. **Watchdog (Dead-Man Switch)**:
   * The daemon expects a heartbeat message from the active UI every 5 seconds.
   * If no heartbeat is received for 10 seconds (e.g., UI crashed, disconnected, or workspace closed), the daemon automatically reverts `pwm1_enable` to `0` (firmware auto control) for thermal safety.
5. **SIGTERM/SIGINT Handler**: Gracefully traps exit signals, writing `0` to `pwm1_enable` to restore automatic BIOS control before terminating.
6. **Isolated Scope**: Never writes to other EC registers (battery, keyboard backlights, etc.).
7. **Rotating Audit Log**: Logs every operation (source, command type, previous value, target value, outcome) to `~/.local/share/lightning-fan/audit.log`.

---

## 4. IPC Protocol

Simple JSON messages over the Unix Domain Socket:

### UI -> Daemon (Commands)
```jsonc
// Enable firmware automatic mode
{ "cmd": "set_auto" }

// Enable manual mode with target speed (0 - 255)
{ "cmd": "set_manual", "speed": 180 }

// Set custom temperature curve (array of 5 points: {temp: °C, speed: 0-255})
{ "cmd": "set_curve", "curve": [ {"t": 40, "s": 50}, {"t": 55, "s": 100}, {"t": 70, "s": 160}, {"t": 80, "s": 220}, {"t": 90, "s": 255} ] }

// Heartbeat message (every 5 seconds)
{ "cmd": "heartbeat" }
```

### Daemon -> UI (Telemetry & Responses)
```jsonc
// Broadcast status (every 1 second)
{
  "type": "status",
  "mode": "auto | manual | curve",
  "current_speed_pct": 70,       // current target duty cycle %
  "cpu_fan_rpm": 2300,
  "gpu_fan_rpm": 2200,
  "cpu_temp": 45,
  "gpu_temp": 43,
  "watchdog_seconds": 5
}

// Command acknowledgement/rejection
{ "type": "ack", "status": "ok | rejected", "reason": "optional reason" }
```
