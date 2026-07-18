use std::os::unix::net::UnixStream;
use std::io::{BufRead, BufReader, Write};
use std::thread;
use std::time::Duration;
use tauri::Emitter;

const SOCKET_PATH: &str = "/run/user/1000/lightning-fan.sock";

#[tauri::command]
fn send_command(cmd: String) -> Result<(), String> {
    let mut stream = UnixStream::connect(SOCKET_PATH)
        .map_err(|e| format!("Failed to connect to daemon: {}", e))?;
    
    let cmd_with_nl = format!("{}\n", cmd);
    stream.write_all(cmd_with_nl.as_bytes())
        .map_err(|e| format!("Failed to write to daemon: {}", e))?;
        
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let app_handle = app.handle().clone();
            
            // Spawn background thread to continuously read from the Unix domain socket
            // and emit events containing telemetry back to the webview
            thread::spawn(move || {
                loop {
                    if let Ok(stream) = UnixStream::connect(SOCKET_PATH) {
                        let reader = BufReader::new(stream);
                        for line in reader.lines().flatten() {
                            let _ = app_handle.emit("telemetry", line);
                        }
                    }
                    // If connection fails or drops, sleep 2 seconds before retrying
                    thread::sleep(Duration::from_secs(2));
                }
            });
            
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![send_command])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
