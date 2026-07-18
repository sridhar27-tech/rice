# Lightning Fan — Implementation Tasks

Tasks to implement the `lightning-fan` custom fan control system.

## Phase 1: Environment & Setup
- [ ] Verify Rust (`cargo`/`rustc`) is fully installed and in the user's `PATH`.
- [ ] Initialize Tauri app structure in `/home/bow/.config/lightning-fan/`.
- [ ] Set up project structure: `daemon/` for the Rust background service, and `frontend/` for the Tauri UI.

## Phase 2: Daemon MVP (`lightning-faud`)
- [ ] Write Rust daemon core to parse `/sys/class/hwmon/hwmon*` name files and locate the `hp` and `k10temp` controllers.
- [ ] Implement read-only CPU/GPU RPM and CPU/GPU temperatures polling logic.
- [ ] Implement Unix domain socket listener at `/run/user/1000/lightning-fan.sock` to broadcast JSON telemetry.

## Phase 3: Daemon Safety Layer & Write Control
- [ ] Implement `pwm1` and `pwm1_enable` write controls with safe clamping (floor: `12`, ceiling: `255`).
- [ ] Implement rate-limiter / debounce (minimum 1 second between EC writes).
- [ ] Implement SIGINT/SIGTERM handlers to reset `pwm1_enable` to `0` (restoring auto/firmware fan control) on shutdown.
- [ ] Implement client watchdog / dead-man switch (resets to auto mode if heartbeat is missed for 10 seconds).
- [ ] Implement rotating audit log to `~/.local/share/lightning-fan/audit.log`.

## Phase 4: Frontend Development (React + Tailwind CSS + Vite)
- [ ] Scaffold Tauri React/TS frontend.
- [ ] Design sliders for CPU/GPU target speed (percentage to PWM translation).
- [ ] Design live telemetry graph displaying CPU & GPU temperatures over a rolling 5-minute window.
- [ ] Integrate Unix Domain Socket connection using Tauri's sidecar/custom IPC commands.
- [ ] Implement client-side debounce (300-500ms) on slider movements.
- [ ] Implement the 5-second heartbeat sender to keep the daemon active.

## Phase 5: Fan Curves Editor
- [ ] Design interactive curve editor UI (drag-and-drop or point-adjust table) mapping temp (°C) to speed (%).
- [ ] Implement daemon-side curve execution (evaluates fan speed based on current max temperature and active curve points).
- [ ] Persist user curve profiles to `~/.config/lightning-fan/profiles.json`.

## Phase 6: Packaging & Integration
- [ ] Create `lightning-faud.service` user systemd unit.
- [ ] Add PKGBUILD/installer scripts for easy installation.
- [ ] Verify complete cleanup on uninstall.
