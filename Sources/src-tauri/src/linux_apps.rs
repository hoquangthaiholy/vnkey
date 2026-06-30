#![cfg(target_os = "linux")]

use std::process::Command;
use std::fs;
use std::path::Path;
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;

fn get_icon_base64_from_name(app_name: &str) -> String {
    let lower_name = app_name.to_lowercase();
    // Common icon locations on Linux
    let search_paths = vec![
        "/usr/share/pixmaps",
        "/usr/share/icons/hicolor/48x48/apps",
        "/usr/share/icons/hicolor/64x64/apps",
        "/usr/share/icons/hicolor/128x128/apps",
        "/usr/share/icons/hicolor/scalable/apps",
    ];

    for path in search_paths {
        // Try png
        let png_path = format!("{}/{}.png", path, lower_name);
        if Path::new(&png_path).exists() {
            if let Ok(bytes) = fs::read(&png_path) {
                return BASE64_STANDARD.encode(&bytes);
            }
        }
        // Try svg
        let svg_path = format!("{}/{}.svg", path, lower_name);
        if Path::new(&svg_path).exists() {
            if let Ok(bytes) = fs::read(&svg_path) {
                return BASE64_STANDARD.encode(&bytes);
            }
        }
    }
    String::new()
}

pub fn get_running_applications_json() -> Option<String> {
    let mut apps = Vec::new();

    // Check if xprop works (X11)
    if let Ok(output) = Command::new("xprop").args(&["-root", "_NET_CLIENT_LIST"]).output() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        // Output format is like: _NET_CLIENT_LIST(WINDOW): window id # 0x2000003, 0x3800001
        if let Some(pos) = stdout.find('#') {
            let ids_str = &stdout[pos + 1..];
            let win_ids: Vec<&str> = ids_str.split(',').map(|id| id.trim()).collect();
            
            for id in win_ids {
                if id.is_empty() { continue; }
                
                // Get WM_CLASS and PID for each window ID
                if let Ok(win_info) = Command::new("xprop").args(&["-id", id, "WM_CLASS", "_NET_WM_PID"]).output() {
                    let win_stdout = String::from_utf8_lossy(&win_info.stdout);
                    
                    let mut app_class = String::new();
                    let mut pid = String::new();

                    for line in win_stdout.lines() {
                        if line.contains("WM_CLASS") {
                            // Format: WM_CLASS(STRING) = "google-chrome", "Google-chrome"
                            if let Some(eq_pos) = line.find('=') {
                                let parts: Vec<&str> = line[eq_pos + 1..].split(',').collect();
                                if let Some(first) = parts.first() {
                                    app_class = first.replace('"', "").trim().to_string();
                                }
                            }
                        } else if line.contains("_NET_WM_PID") {
                            // Format: _NET_WM_PID(CARDINAL) = 12345
                            if let Some(eq_pos) = line.find('=') {
                                pid = line[eq_pos + 1..].trim().to_string();
                            }
                        }
                    }

                    if !app_class.is_empty() {
                        if app_class.to_lowercase().contains("vnkey") {
                            continue;
                        }

                        let bundle_id = if !pid.is_empty() {
                            let exe_link = format!("/proc/{}/exe", pid);
                            if let Ok(path) = fs::read_link(&exe_link) {
                                path.to_string_lossy().to_string()
                            } else {
                                app_class.clone()
                            }
                        } else {
                            app_class.clone()
                        };

                        if !apps.iter().any(|app: &serde_json::Value| app["bundle_id"] == bundle_id) {
                            let icon = get_icon_base64_from_name(&app_class);
                            apps.push(serde_json::json!({
                                "bundle_id": bundle_id,
                                "name": app_class,
                                "icon": icon
                            }));
                        }
                    }
                }
            }
        }
    }

    // Fallback: if X11 list is empty, scan /proc for graphical/user processes
    if apps.is_empty() {
        if let Ok(entries) = fs::read_dir("/proc") {
            for entry in entries.filter_map(Result::ok) {
                let name = entry.file_name();
                if let Some(pid_str) = name.to_str() {
                    if pid_str.chars().all(|c| c.is_digit(10)) {
                        let exe_link = format!("/proc/{}/exe", pid_str);
                        if let Ok(path) = fs::read_link(&exe_link) {
                            let path_str = path.to_string_lossy().to_string();
                            // Only include common user space apps, avoid kernel and daemons
                            if path_str.starts_with("/usr/bin/") || path_str.starts_with("/opt/") || path_str.starts_with("/usr/lib/") {
                                let app_name = path.file_name().unwrap_or(&name).to_string_lossy().to_string();
                                
                                if app_name.to_lowercase().contains("vnkey") {
                                    continue;
                                }

                                if !apps.iter().any(|app: &serde_json::Value| app["bundle_id"] == path_str) {
                                    let icon = get_icon_base64_from_name(&app_name);
                                    apps.push(serde_json::json!({
                                        "bundle_id": path_str,
                                        "name": app_name,
                                        "icon": icon
                                    }));
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Some(serde_json::to_string(&apps).unwrap_or_default())
}

pub fn get_frontmost_app_bundle_id() -> Option<String> {
    // Check X11 first
    if let Ok(output) = Command::new("xprop").args(&["-root", "_NET_ACTIVE_WINDOW"]).output() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        // Format: _NET_ACTIVE_WINDOW(WINDOW): window id # 0x2000003
        if let Some(pos) = stdout.find('#') {
            let win_id = stdout[pos + 1..].trim();
            if !win_id.is_empty() && win_id != "0x0" {
                if let Ok(win_info) = Command::new("xprop").args(&["-id", win_id, "_NET_WM_PID", "WM_CLASS"]).output() {
                    let win_stdout = String::from_utf8_lossy(&win_info.stdout);
                    let mut pid = String::new();
                    let mut app_class = String::new();

                    for line in win_stdout.lines() {
                        if line.contains("_NET_WM_PID") {
                            if let Some(eq_pos) = line.find('=') {
                                pid = line[eq_pos + 1..].trim().to_string();
                            }
                        } else if line.contains("WM_CLASS") {
                            if let Some(eq_pos) = line.find('=') {
                                let parts: Vec<&str> = line[eq_pos + 1..].split(',').collect();
                                if let Some(first) = parts.first() {
                                    app_class = first.replace('"', "").trim().to_string();
                                }
                            }
                        }
                    }

                    if !pid.is_empty() {
                        let exe_link = format!("/proc/{}/exe", pid);
                        if let Ok(path) = fs::read_link(&exe_link) {
                            return Some(path.to_string_lossy().to_string());
                        }
                    }
                    if !app_class.is_empty() {
                        return Some(app_class);
                    }
                }
            }
        }
    }
    None
}

pub fn get_frontmost_app_name() -> Option<String> {
    get_frontmost_app_bundle_id().map(|id| {
        if id.starts_with('/') {
            Path::new(&id)
                .file_name()
                .and_then(|f| f.to_str())
                .unwrap_or(&id)
                .to_string()
        } else {
            id
        }
    })
}

pub fn get_application_info_by_path_json(path: &str) -> Option<String> {
    let name = if path.starts_with('/') {
        Path::new(path)
            .file_name()
            .and_then(|f| f.to_str())
            .unwrap_or(path)
            .to_string()
    } else {
        path.to_string()
    };

    let icon = get_icon_base64_from_name(&name);
    let app = serde_json::json!({
        "bundle_id": path,
        "name": name,
        "icon": icon
    });

    Some(app.to_string())
}

pub fn get_application_info_by_bundle_id_json(bundle_id: &str) -> Option<String> {
    get_application_info_by_path_json(bundle_id)
}

pub fn get_application_info_by_name_json(name: &str) -> Option<String> {
    get_application_info_by_path_json(name)
}
