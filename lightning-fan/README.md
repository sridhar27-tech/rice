# Lightning Fan ⚡🌀

Custom fan control UI and daemon for HP Omen (AMD Ryzen 7 7000 series, RTX 4060) on EndeavourOS/Hyprland. Replaces standard hotkeys with an interactive React GUI and a secure background controller.

## Architecture

* **Daemon (`lightning-faud`)**: A Rust background service that runs as a systemd user unit. It communicates with the UI over a Unix Domain Socket at `/run/user/1000/lightning-fan.sock` and is the only process with write access to the fan sysfs nodes.
* **Frontend (`lightning-fan`)**: A desktop UI built on Tauri v2, React, TypeScript, and Recharts. Runs in user-space without any privileges.

---

## Safety Features (Daemon-Side)

1. **Path Whitelist**: Hardcoded paths for `pwm1` and `pwm1_enable` sysfs nodes.
2. **Value Clamps**: Safe duty cycle constraints (hard minimum of `12` in manual mode to prevent stalling, maximum `255`).
3. **Debounce Rate Limit**: Limits hardware writes to a maximum frequency of 1 write per second.
4. **Dead-Man Switch / Watchdog**: Reverts to BIOS automatic fan control if the UI connection drops or a heartbeat is missed for 10 seconds.
5. **SIGTERM/SIGINT Handlers**: Gracefully traps termination signals and resets the fans to BIOS auto mode before exit.
6. **Audit Logging**: Logs all actions with timestamps to `~/.local/share/lightning-fan/audit.log`.

---

## Installation & Running

### 1. Enable Hardware Permissions
Verify your udev rules allow writing to the fan controllers under the `wheel` group:
```bash
sudo ~/setup_fan_rules.sh
```

### 2. Run the Daemon
The daemon runs as a user systemd service:
```bash
# Reload user daemon services
systemctl --user daemon-reload

# Start and enable the service
systemctl --user enable --now lightning-faud
```

### 3. Run the Frontend
Launch the Tauri desktop UI:
```bash
cd frontend
npm run tauri dev
```
Or run the pre-built release binary.
