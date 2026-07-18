use tokio::net::UnixListener;
use tokio::sync::Mutex;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::signal;
use serde::{Serialize, Deserialize};
use std::sync::Arc;
use std::path::{Path, PathBuf};
use std::fs;
use std::io::Write; // Added for audit logging
use std::process::Command;
use std::time::{Duration, Instant};

const SOCKET_PATH: &str = "/run/user/1000/lightning-fan.sock";
const AUDIT_LOG_DIR: &str = "/home/bow/.local/share/lightning-fan";
const AUDIT_LOG_PATH: &str = "/home/bow/.local/share/lightning-fan/audit.log";

#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq)]
struct CurvePoint {
    #[serde(rename = "t")]
    temp: u8,
    #[serde(rename = "s")]
    speed: u8,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
#[serde(tag = "mode", rename_all = "snake_case")]
enum FanMode {
    Auto,
    Manual { speed: u8 },
    Curve { curve: Vec<CurvePoint> },
}

#[derive(Debug, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
enum UiCommand {
    SetAuto,
    SetManual { speed: u8 },
    SetCurve { curve: Vec<CurvePoint> },
    Heartbeat,
}

#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum DaemonMessage {
    Status {
        mode: FanMode,
        current_speed_pct: u8,
        cpu_fan_rpm: u32,
        gpu_fan_rpm: u32,
        cpu_temp: u8,
        gpu_temp: u8,
        watchdog_seconds: u64,
    },
    Ack {
        status: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        reason: Option<String>,
    },
}

struct HwPaths {
    hp_dir: Option<PathBuf>,
    cpu_temp_file: Option<PathBuf>,
    gpu_temp_file: Option<PathBuf>,
}

struct DaemonState {
    mode: FanMode,
    last_heartbeat: Instant,
    hw_paths: HwPaths,
    last_speed_written: u8,
    last_write_time: Instant,
}

impl DaemonState {
    fn new(hw_paths: HwPaths) -> Self {
        Self {
            mode: FanMode::Auto,
            last_heartbeat: Instant::now(),
            hw_paths,
            last_speed_written: 0,
            last_write_time: Instant::now() - Duration::from_secs(5),
        }
    }
}

// Log actions to the audit log
fn audit_log(action: &str) {
    if let Err(e) = fs::create_dir_all(AUDIT_LOG_DIR) {
        eprintln!("Failed to create audit log directory: {}", e);
        return;
    }

    let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
    let log_line = format!("[{}] {}\n", timestamp, action);

    // Keep log file rotated/capped at 5MB
    if let Ok(metadata) = fs::metadata(AUDIT_LOG_PATH) {
        if metadata.len() > 5 * 1024 * 1024 {
            let _ = fs::rename(AUDIT_LOG_PATH, format!("{}.1", AUDIT_LOG_PATH));
        }
    }

    let mut options = fs::OpenOptions::new();
    options.create(true).append(true);
    if let Ok(mut file) = options.open(AUDIT_LOG_PATH) {
        let _ = file.write_all(log_line.as_bytes());
    }
}

// Auto-discover the hwmon sysfs nodes
fn discover_hw_paths() -> HwPaths {
    let mut hp_dir = None;
    let mut cpu_temp_file = None;
    let mut gpu_temp_file = None;

    if let Ok(entries) = fs::read_dir("/sys/class/hwmon") {
        for entry in entries.flatten() {
            let path = entry.path();
            let name_path = path.join("name");
            if let Ok(name) = fs::read_to_string(&name_path) {
                let name = name.trim();
                match name {
                    "hp" => {
                        hp_dir = Some(path);
                    }
                    "k10temp" => {
                        cpu_temp_file = Some(path.join("temp1_input"));
                    }
                    "amdgpu" => {
                        gpu_temp_file = Some(path.join("temp1_input"));
                    }
                    _ => {}
                }
            }
        }
    }

    HwPaths {
        hp_dir,
        cpu_temp_file,
        gpu_temp_file,
    }
}

// Query Nvidia GPU temp via nvidia-smi as fallback
fn get_nvidia_temp() -> Option<u8> {
    let output = Command::new("nvidia-smi")
        .args(["--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"])
        .output()
        .ok()?;

    if output.status.success() {
        let temp_str = String::from_utf8_lossy(&output.stdout);
        temp_str.trim().parse::<u8>().ok()
    } else {
        None
    }
}

fn read_sensor_temp(path: &Option<PathBuf>) -> Option<u8> {
    let path = path.as_ref()?;
    let val_str = fs::read_to_string(path).ok()?;
    let val = val_str.trim().parse::<u32>().ok()?;
    Some((val / 1000) as u8)
}

fn read_sensor_rpm(hp_dir: &Option<PathBuf>, fan_name: &str) -> u32 {
    if let Some(dir) = hp_dir {
        let path = dir.join(fan_name);
        if let Ok(val_str) = fs::read_to_string(path) {
            return val_str.trim().parse::<u32>().unwrap_or(0);
        }
    }
    0
}

// Write to EC fan sysfs nodes safely
fn write_hardware_fan(state: &mut DaemonState, enable_manual: bool, speed: u8) -> Result<(), String> {
    let hp_dir = state.hw_paths.hp_dir.as_ref()
        .ok_or_else(|| "Hardware controller 'hp' not discovered".to_string())?;

    let pwm1_path = hp_dir.join("pwm1");
    let pwm1_enable_path = hp_dir.join("pwm1_enable");

    // Rate limiting: enforce min 1 second between hardware writes
    let now = Instant::now();
    if now.duration_since(state.last_write_time) < Duration::from_secs(1) {
        return Ok(()); // Silently accept to prevent fast updates from overwhelming the EC
    }

    if enable_manual {
        // Clamp speed: floor 12 to prevent stall, ceiling 255
        let clamped_speed = if speed < 12 && speed > 0 {
            12
        } else {
            speed
        };

        // 1. Enable manual control
        fs::write(&pwm1_enable_path, "1")
            .map_err(|e| format!("Failed to write pwm1_enable: {}", e))?;

        // 2. Set PWM speed value
        fs::write(&pwm1_path, clamped_speed.to_string())
            .map_err(|e| format!("Failed to write pwm1: {}", e))?;

        if clamped_speed != state.last_speed_written {
            audit_log(&format!(
                "Hardware Write: Manual mode, speed: {}/255 (requested: {})",
                clamped_speed, speed
            ));
            state.last_speed_written = clamped_speed;
            state.last_write_time = now;
        }
    } else {
        // Restore BIOS automatic control
        fs::write(&pwm1_enable_path, "0")
            .map_err(|e| format!("Failed to write pwm1_enable: {}", e))?;

        if state.last_speed_written != 0 {
            audit_log("Hardware Write: Restored Auto (BIOS) mode");
            state.last_speed_written = 0;
            state.last_write_time = now;
        }
    }

    Ok(())
}

// Safely evaluate fan curve and return corresponding target speed
fn evaluate_curve(curve: &[CurvePoint], temp: u8) -> u8 {
    if curve.is_empty() {
        return 0;
    }
    
    // Sort points just in case
    let mut sorted_curve = curve.to_vec();
    sorted_curve.sort_by_key(|p| p.temp);

    // If temp is below the first point
    if temp <= sorted_curve[0].temp {
        return sorted_curve[0].speed;
    }

    // If temp is above the last point
    let len = sorted_curve.len();
    if temp >= sorted_curve[len - 1].temp {
        return sorted_curve[len - 1].speed;
    }

    // Interpolate between points
    for i in 0..len - 1 {
        let p1 = sorted_curve[i];
        let p2 = sorted_curve[i + 1];
        if temp >= p1.temp && temp <= p2.temp {
            let temp_range = (p2.temp - p1.temp) as f32;
            let speed_range = (p2.speed as i32 - p1.speed as i32) as f32;
            let factor = (temp - p1.temp) as f32 / temp_range;
            return (p1.speed as i32 + (factor * speed_range) as i32) as u8;
        }
    }

    0
}

#[tokio::main]
async fn main() {
    println!("Starting Lightning Fan Daemon...");
    audit_log("Daemon started");

    let hw_paths = discover_hw_paths();
    if hw_paths.hp_dir.is_none() {
        eprintln!("WARNING: Could not discover HP wmi fan controller. Hardware writes will fail.");
    } else {
        println!("Discovered HP hwmon controller: {:?}", hw_paths.hp_dir);
    }

    let state = Arc::new(Mutex::new(DaemonState::new(hw_paths)));

    // Ensure stale socket is cleaned up
    if Path::new(SOCKET_PATH).exists() {
        let _ = fs::remove_file(SOCKET_PATH);
    }

    let listener = UnixListener::bind(SOCKET_PATH).expect("Failed to bind Unix socket");
    // Make socket user-writable
    let _ = Command::new("chmod").args(["660", SOCKET_PATH]).status();

    println!("Unix socket listening at {}", SOCKET_PATH);

    // Spawn Watchdog Timer
    let state_wd = Arc::clone(&state);
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(1)).await;
            let mut s = state_wd.lock().await;

            let now = Instant::now();
            let elapsed = now.duration_since(s.last_heartbeat).as_secs();

            // Under Manual or Curve mode, if heartbeat is missed for 10s, restore Auto mode
            if s.mode != FanMode::Auto && elapsed >= 10 {
                println!("Watchdog: Heartbeat missed for {}s. Restoring auto control.", elapsed);
                audit_log(&format!("Watchdog: Timeout ({}s), reverting to Auto", elapsed));
                let _ = write_hardware_fan(&mut s, false, 0);
                s.mode = FanMode::Auto;
            }
        }
    });

    // Spawn Thermal Loop (1 second interval) to apply curves and read telemetry
    let state_thermal = Arc::clone(&state);
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(1)).await;
            let mut s = state_thermal.lock().await;

            let cpu_temp = read_sensor_temp(&s.hw_paths.cpu_temp_file).unwrap_or(0);
            let gpu_temp = get_nvidia_temp()
                .or_else(|| read_sensor_temp(&s.hw_paths.gpu_temp_file))
                .unwrap_or(0);

            let max_temp = std::cmp::max(cpu_temp, gpu_temp);

            if let FanMode::Curve { curve } = &s.mode {
                let target_speed = evaluate_curve(curve, max_temp);
                let _ = write_hardware_fan(&mut s, true, target_speed);
            }
        }
    });

    // Spawn Socket IPC Command Handler
    let state_ipc = Arc::clone(&state);
    let listener_handler = tokio::spawn(async move {
        while let Ok((mut stream, _)) = listener.accept().await {
            let state_client = Arc::clone(&state_ipc);
            tokio::spawn(async move {
                let mut buffer = [0; 4096];
                loop {
                    tokio::select! {
                        // 1. Read commands from client socket
                        read_res = stream.read(&mut buffer) => {
                            match read_res {
                                Ok(0) => break, // Socket closed
                                Ok(n) => {
                                    let req_str = String::from_utf8_lossy(&buffer[..n]);
                                    for line in req_str.lines() {
                                        if let Ok(cmd) = serde_json::from_str::<UiCommand>(line) {
                                            let mut s = state_client.lock().await;
                                            s.last_heartbeat = Instant::now(); // Any command acts as heartbeat

                                            let response = match cmd {
                                                UiCommand::Heartbeat => {
                                                    DaemonMessage::Ack { status: "ok".to_string(), reason: None }
                                                }
                                                UiCommand::SetAuto => {
                                                    s.mode = FanMode::Auto;
                                                    match write_hardware_fan(&mut s, false, 0) {
                                                        Ok(_) => DaemonMessage::Ack { status: "ok".to_string(), reason: None },
                                                        Err(e) => DaemonMessage::Ack { status: "error".to_string(), reason: Some(e) },
                                                    }
                                                }
                                                UiCommand::SetManual { speed } => {
                                                    s.mode = FanMode::Manual { speed };
                                                    match write_hardware_fan(&mut s, true, speed) {
                                                        Ok(_) => DaemonMessage::Ack { status: "ok".to_string(), reason: None },
                                                        Err(e) => DaemonMessage::Ack { status: "error".to_string(), reason: Some(e) },
                                                    }
                                                }
                                                UiCommand::SetCurve { curve } => {
                                                    s.mode = FanMode::Curve { curve: curve.clone() };
                                                    // Trigger thermal loop calculation immediately
                                                    let cpu_temp = read_sensor_temp(&s.hw_paths.cpu_temp_file).unwrap_or(0);
                                                    let gpu_temp = get_nvidia_temp()
                                                        .or_else(|| read_sensor_temp(&s.hw_paths.gpu_temp_file))
                                                        .unwrap_or(0);
                                                    let max_temp = std::cmp::max(cpu_temp, gpu_temp);
                                                    let target_speed = evaluate_curve(&curve, max_temp);

                                                    match write_hardware_fan(&mut s, true, target_speed) {
                                                        Ok(_) => DaemonMessage::Ack { status: "ok".to_string(), reason: None },
                                                        Err(e) => DaemonMessage::Ack { status: "error".to_string(), reason: Some(e) },
                                                    }
                                                }
                                            };

                                            if let Ok(resp_bytes) = serde_json::to_vec(&response) {
                                                let mut resp_bytes_nl = resp_bytes;
                                                resp_bytes_nl.push(b'\n');
                                                let _ = stream.write_all(&resp_bytes_nl).await;
                                            }
                                        }
                                    }
                                }
                                Err(_) => break,
                            }
                        }

                        // 2. Periodically send telemetry status back to client
                        _ = tokio::time::sleep(Duration::from_secs(1)) => {
                            let s = state_client.lock().await;
                            let cpu_temp = read_sensor_temp(&s.hw_paths.cpu_temp_file).unwrap_or(0);
                            let gpu_temp = get_nvidia_temp()
                                .or_else(|| read_sensor_temp(&s.hw_paths.gpu_temp_file))
                                .unwrap_or(0);
                            
                            let cpu_fan_rpm = read_sensor_rpm(&s.hw_paths.hp_dir, "fan1_input");
                            let gpu_fan_rpm = read_sensor_rpm(&s.hw_paths.hp_dir, "fan2_input");

                            let elapsed = Instant::now().duration_since(s.last_heartbeat).as_secs();
                            let watchdog_seconds = if elapsed >= 10 { 0 } else { 10 - elapsed };

                            let msg = DaemonMessage::Status {
                                mode: s.mode.clone(),
                                current_speed_pct: (s.last_speed_written as u32 * 100 / 255) as u8,
                                cpu_fan_rpm,
                                gpu_fan_rpm,
                                cpu_temp,
                                gpu_temp,
                                watchdog_seconds,
                            };

                            if let Ok(resp_bytes) = serde_json::to_vec(&msg) {
                                let mut resp_bytes_nl = resp_bytes;
                                resp_bytes_nl.push(b'\n');
                                if stream.write_all(&resp_bytes_nl).await.is_err() {
                                    break;
                                }
                            }
                        }
                    }
                }
            });
        }
    });

    // Gracefully handle shutdown signal
    let state_term = Arc::clone(&state);
    signal::ctrl_c().await.expect("failed to listen for ctrl_c signal");
    println!("\nShutdown signal received. Reverting fan control to auto (BIOS) mode...");
    audit_log("Daemon stopping (SIGINT/SIGTERM)");
    
    let mut s = state_term.lock().await;
    let _ = write_hardware_fan(&mut s, false, 0);

    // Cancel socket listener task
    listener_handler.abort();
    let _ = fs::remove_file(SOCKET_PATH);
    println!("Daemon stopped cleanly.");
}
