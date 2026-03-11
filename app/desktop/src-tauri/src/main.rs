use std::net::TcpStream;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tauri::Manager;

struct SidecarState {
    child: Arc<Mutex<Option<Child>>>,
}

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}

fn sidecar_running() -> bool {
    TcpStream::connect_timeout(
        &"127.0.0.1:8765".parse().expect("valid sidecar address"),
        Duration::from_millis(250),
    )
    .is_ok()
}

fn python_candidates() -> Vec<PathBuf> {
    let root = workspace_root();
    vec![
        root.join(".venv/bin/python"),
        PathBuf::from("/opt/homebrew/bin/python3"),
        PathBuf::from("/usr/bin/python3"),
    ]
}

fn start_sidecar() -> Option<Child> {
    if sidecar_running() {
        return None;
    }
    let root = workspace_root();
    for candidate in python_candidates() {
        if !candidate.exists() {
            continue;
        }
        let child = Command::new(candidate)
            .arg("-m")
            .arg("app.sidecar.server")
            .current_dir(&root)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
        if let Ok(process) = child {
            return Some(process);
        }
    }
    None
}

fn main() {
    let sidecar_child = start_sidecar();
    let state = SidecarState {
        child: Arc::new(Mutex::new(sidecar_child)),
    };

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(state)
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::Destroyed = event {
                if let Some(state) = window.app_handle().try_state::<SidecarState>() {
                    if let Ok(mut guard) = state.child.lock() {
                        if let Some(child) = guard.as_mut() {
                            let _ = child.kill();
                        }
                        *guard = None;
                    }
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
