use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread::sleep;
use std::time::{Duration, Instant};

use serde_json::Value;
use tauri::Manager;

const SIDECAR_ADDR: &str = "127.0.0.1:8765";
const SIDECAR_OPENAPI_PATH: &str = "/openapi.json";
const REQUIRED_SIDECAR_ROUTES: [(&str, &str); 5] = [
    ("GET", "/meta"),
    ("GET", "/plot-contract"),
    ("POST", "/inspect-file"),
    ("POST", "/compose-preview"),
    ("POST", "/preprocess-tensile-replicates"),
];

struct SidecarState {
    child: Arc<Mutex<Option<Child>>>,
}

struct SidecarProbe {
    routes: Vec<(String, String)>,
    missing_routes: Vec<(String, String)>,
}

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}

fn sidecar_port_open() -> bool {
    TcpStream::connect_timeout(
        &SIDECAR_ADDR.parse().expect("valid sidecar address"),
        Duration::from_millis(250),
    )
    .is_ok()
}

fn fetch_sidecar_body(path: &str) -> Result<String, String> {
    let mut stream = TcpStream::connect_timeout(
        &SIDECAR_ADDR.parse().expect("valid sidecar address"),
        Duration::from_secs(1),
    )
    .map_err(|error| format!("could not connect to sidecar: {error}"))?;
    stream
        .set_read_timeout(Some(Duration::from_secs(2)))
        .map_err(|error| format!("could not set sidecar read timeout: {error}"))?;
    stream
        .set_write_timeout(Some(Duration::from_secs(2)))
        .map_err(|error| format!("could not set sidecar write timeout: {error}"))?;
    let request = format!(
        "GET {path} HTTP/1.1\r\nHost: {SIDECAR_ADDR}\r\nConnection: close\r\n\r\n"
    );
    stream
        .write_all(request.as_bytes())
        .map_err(|error| format!("could not query sidecar {path}: {error}"))?;

    let mut response = String::new();
    stream
        .read_to_string(&mut response)
        .map_err(|error| format!("could not read sidecar {path}: {error}"))?;

    let (headers, body) = response
        .split_once("\r\n\r\n")
        .ok_or_else(|| format!("sidecar {path} returned an invalid HTTP response"))?;
    if !headers.contains("200 OK") {
        let status_line = headers.lines().next().unwrap_or("HTTP status unavailable");
        return Err(format!("sidecar {path} returned {status_line}"));
    }
    Ok(body.to_string())
}

fn parse_openapi_routes(body: &str) -> Result<Vec<(String, String)>, String> {
    let payload: Value =
        serde_json::from_str(body).map_err(|error| format!("invalid sidecar openapi json: {error}"))?;
    let paths = payload
        .get("paths")
        .and_then(Value::as_object)
        .ok_or_else(|| "sidecar openapi is missing the `paths` object".to_string())?;

    let mut routes = Vec::new();
    for (path, methods) in paths {
        if let Some(method_map) = methods.as_object() {
            for method in method_map.keys() {
                routes.push((method.to_uppercase(), path.to_string()));
            }
        }
    }
    routes.sort_by(|left, right| left.1.cmp(&right.1).then(left.0.cmp(&right.0)));
    Ok(routes)
}

fn probe_running_sidecar() -> Result<SidecarProbe, String> {
    let openapi_body = fetch_sidecar_body(SIDECAR_OPENAPI_PATH)?;
    let routes = parse_openapi_routes(&openapi_body)?;
    let missing_routes = REQUIRED_SIDECAR_ROUTES
        .iter()
        .filter(|(method, path)| {
            !routes
                .iter()
                .any(|(registered_method, registered_path)| registered_method == method && registered_path == path)
        })
        .map(|(method, path)| (method.to_string(), path.to_string()))
        .collect::<Vec<_>>();

    Ok(SidecarProbe {
        routes,
        missing_routes,
    })
}

fn summarize_routes(routes: &[(String, String)]) -> String {
    routes
        .iter()
        .map(|(method, path)| format!("{method} {path}"))
        .collect::<Vec<_>>()
        .join(", ")
}

#[cfg(unix)]
fn listener_pids_for_sidecar_port() -> Vec<String> {
    let output = Command::new("lsof")
        .args(["-t", "-iTCP:8765", "-sTCP:LISTEN"])
        .output();
    let Ok(output) = output else {
        return Vec::new();
    };
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

#[cfg(not(unix))]
fn listener_pids_for_sidecar_port() -> Vec<String> {
    Vec::new()
}

#[cfg(unix)]
fn terminate_stale_sidecar_listeners() {
    let listener_pids = listener_pids_for_sidecar_port();
    if listener_pids.is_empty() {
        eprintln!("[desktop] no existing sidecar listener was found on {SIDECAR_ADDR}.");
        return;
    }
    eprintln!(
        "[desktop] replacing stale sidecar listener(s) on {SIDECAR_ADDR}: {}",
        listener_pids.join(", ")
    );
    for pid in &listener_pids {
        let _ = Command::new("kill").args(["-TERM", pid]).status();
    }
    let deadline = Instant::now() + Duration::from_secs(3);
    while Instant::now() < deadline && sidecar_port_open() {
        sleep(Duration::from_millis(150));
    }
    if sidecar_port_open() {
        for pid in &listener_pids {
            let _ = Command::new("kill").args(["-KILL", pid]).status();
        }
        let final_deadline = Instant::now() + Duration::from_secs(2);
        while Instant::now() < final_deadline && sidecar_port_open() {
            sleep(Duration::from_millis(100));
        }
    }
}

#[cfg(not(unix))]
fn terminate_stale_sidecar_listeners() {
    eprintln!(
        "[desktop] an incompatible sidecar is already bound to {SIDECAR_ADDR}, but automatic replacement is not implemented on this platform."
    );
}

fn wait_for_compatible_sidecar(timeout: Duration) -> bool {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if let Ok(probe) = probe_running_sidecar() {
            if probe.missing_routes.is_empty() {
                eprintln!(
                    "[desktop] sidecar routes ready on http://{SIDECAR_ADDR}: {}",
                    summarize_routes(&probe.routes)
                );
                return true;
            }
        }
        sleep(Duration::from_millis(200));
    }
    false
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
    if sidecar_port_open() {
        match probe_running_sidecar() {
            Ok(probe) if probe.missing_routes.is_empty() => {
                eprintln!(
                    "[desktop] reusing running sidecar on http://{SIDECAR_ADDR}: {}",
                    summarize_routes(&probe.routes)
                );
                return None;
            }
            Ok(probe) => {
                eprintln!(
                    "[desktop] incompatible sidecar detected on http://{SIDECAR_ADDR}; missing routes: {}",
                    summarize_routes(&probe.missing_routes)
                );
                eprintln!(
                    "[desktop] currently registered routes: {}",
                    summarize_routes(&probe.routes)
                );
                terminate_stale_sidecar_listeners();
            }
            Err(error) => {
                eprintln!(
                    "[desktop] could not verify the running sidecar on http://{SIDECAR_ADDR}: {error}"
                );
                terminate_stale_sidecar_listeners();
            }
        }
    }

    let root = workspace_root();
    for candidate in python_candidates() {
        if !candidate.exists() {
            continue;
        }
        eprintln!(
            "[desktop] starting sidecar with {} -m app.sidecar.server",
            candidate.display()
        );
        let child = Command::new(&candidate)
            .arg("-m")
            .arg("app.sidecar.server")
            .current_dir(&root)
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .spawn();
        if let Ok(mut process) = child {
            if wait_for_compatible_sidecar(Duration::from_secs(15)) {
                return Some(process);
            }
            eprintln!(
                "[desktop] sidecar launched with {} but did not expose the required routes in time.",
                candidate.display()
            );
            let _ = process.kill();
            let _ = process.wait();
        }
    }

    eprintln!(
        "[desktop] failed to start a compatible sidecar. Core workbench routes will stay unavailable."
    );
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
