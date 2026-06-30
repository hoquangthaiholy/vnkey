#![cfg(target_os = "windows")]

use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;
use std::ptr;
use std::sync::Mutex;
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use image::{ImageEncoder, ExtendedColorType};

use windows::Win32::Foundation::{HWND, LPARAM, BOOL, HANDLE};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, IsWindowVisible, GetWindowThreadProcessId, GetWindowLongW,
    GetWindowTextW, GetClassNameW, GetIconInfo, DestroyIcon, HICON,
    GWL_EXSTYLE, WS_EX_TOOLWINDOW
};
use windows::Win32::System::Threading::{
    OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION
};
use windows::Win32::System::ProcessStatus::GetModuleFileNameExW;
use windows::Win32::Graphics::Gdi::{
    GetDC, ReleaseDC, GetDIBits, GetObjectW, BITMAP, BITMAPINFOHEADER, DIB_RGB_COLORS, DeleteObject
};
use windows::Win32::UI::Shell::{SHGetFileInfoW, SHGFI_ICON, SHGFI_LARGEICON, SHFILEINFOW};

unsafe fn hicon_to_rgba(hicon: HICON) -> Option<(u32, u32, Vec<u8>)> {
    let mut icon_info = std::mem::zeroed();
    if !GetIconInfo(hicon, &mut icon_info).as_bool() {
        return None;
    }

    let hbm_mask = icon_info.hbmMask;
    let hbm_color = icon_info.hbmColor;

    let hdc = GetDC(HWND(ptr::null_mut()));
    let mut bmp: BITMAP = std::mem::zeroed();
    
    if GetObjectW(
        hbm_color.0 as _,
        std::mem::size_of::<BITMAP>() as i32,
        Some(&mut bmp as *mut _ as *mut _)
    ) == 0 {
        ReleaseDC(HWND(ptr::null_mut()), hdc);
        if !hbm_color.is_invalid() { DeleteObject(hbm_color); }
        if !hbm_mask.is_invalid() { DeleteObject(hbm_mask); }
        return None;
    }

    let width = bmp.bmWidth;
    let height = bmp.bmHeight;

    let mut bmi = BITMAPINFOHEADER {
        biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
        biWidth: width,
        biHeight: -height, // top-down
        biPlanes: 1,
        biBitCount: 32,
        biCompression: windows::Win32::Graphics::Gdi::BI_RGB.0,
        ..std::mem::zeroed()
    };

    let mut buffer = vec![0u8; (width * height * 4) as usize];
    GetDIBits(
        hdc,
        hbm_color,
        0,
        height as u32,
        Some(buffer.as_mut_ptr() as *mut _),
        &mut bmi as *mut _ as *mut _,
        DIB_RGB_COLORS
    );

    ReleaseDC(HWND(ptr::null_mut()), hdc);
    if !hbm_color.is_invalid() { DeleteObject(hbm_color); }
    if !hbm_mask.is_invalid() { DeleteObject(hbm_mask); }

    // Windows GDI BGRA to RGBA
    for chunk in buffer.chunks_exact_mut(4) {
        chunk.swap(0, 2);
    }

    Some((width as u32, height as u32, buffer))
}

fn get_icon_base64_from_path(path: &str) -> String {
    unsafe {
        let path_wide: Vec<u16> = OsStr::new(path).encode_wide().chain(std::iter::once(0)).collect();
        let mut shfi: SHFILEINFOW = std::mem::zeroed();
        let flags = SHGFI_ICON | SHGFI_LARGEICON;
        
        let res = SHGetFileInfoW(
            windows::core::PCWSTR(path_wide.as_ptr()),
            windows::Win32::Storage::FileSystem::FILE_FLAGS_AND_ATTRIBUTES(0),
            Some(&mut shfi),
            std::mem::size_of::<SHFILEINFOW>() as u32,
            flags
        );

        if res == 0 || shfi.hIcon.is_invalid() {
            return String::new();
        }

        let base64_str = if let Some((w, h, rgba)) = hicon_to_rgba(shfi.hIcon) {
            let mut png_bytes = Vec::new();
            let encoder = image::codecs::png::PngEncoder::new(&mut png_bytes);
            if encoder.write_image(&rgba, w, h, ExtendedColorType::Rgba8).is_ok() {
                BASE64_STANDARD.encode(&png_bytes)
            } else {
                String::new()
            }
        } else {
            String::new()
        };

        let _ = DestroyIcon(shfi.hIcon);
        base64_str
    }
}

struct AppInfo {
    bundle_id: String,
    name: String,
    icon: String,
}

lazy_static! {
    static ref ENUM_APPS: Mutex<Vec<AppInfo>> = Mutex::new(Vec::new());
}

unsafe extern "system" fn enum_windows_proc(hwnd: HWND, _: LPARAM) -> BOOL {
    if !IsWindowVisible(hwnd).as_bool() {
        return BOOL(1);
    }

    let ex_style = GetWindowLongW(hwnd, GWL_EXSTYLE);
    if (ex_style as u32 & WS_EX_TOOLWINDOW.0) != 0 {
        return BOOL(1);
    }

    let mut process_id = 0;
    GetWindowThreadProcessId(hwnd, Some(&mut process_id));
    if process_id == 0 {
        return BOOL(1);
    }

    let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, process_id);
    if let Ok(process_handle) = handle {
        let mut buffer = [0u16; 1024];
        let length = GetModuleFileNameExW(process_handle, None, &mut buffer);
        let _ = windows::Win32::Foundation::CloseHandle(process_handle);

        if length > 0 {
            let path = String::from_utf16_lossy(&buffer[..length as usize]);
            
            // Get file/app name
            let name = std::path::Path::new(&path)
                .file_name()
                .and_then(|f| f.to_str())
                .unwrap_or("Unknown")
                .to_string();

            // Skip helper processes or vnkey itself
            if name.to_lowercase().contains("vnkey") {
                return BOOL(1);
            }

            let mut apps = ENUM_APPS.lock().unwrap();
            if !apps.iter().any(|a| a.bundle_id == path) {
                let icon = get_icon_base64_from_path(&path);
                apps.push(AppInfo {
                    bundle_id: path,
                    name,
                    icon,
                });
            }
        }
    }

    BOOL(1)
}

pub fn get_running_applications_json() -> Option<String> {
    {
        let mut apps = ENUM_APPS.lock().unwrap();
        apps.clear();
    }

    unsafe {
        let _ = EnumWindows(Some(enum_windows_proc), LPARAM(0));
    }

    let apps = ENUM_APPS.lock().unwrap();
    let json_array: Vec<serde_json::Value> = apps.iter().map(|app| {
        serde_json::json!({
            "bundle_id": app.bundle_id,
            "name": app.name,
            "icon": app.icon
        })
    }).collect();

    Some(serde_json::to_string(&json_array).unwrap_or_default())
}

pub fn get_frontmost_app_bundle_id() -> Option<String> {
    unsafe {
        let hwnd = windows::Win32::UI::WindowsAndMessaging::GetForegroundWindow();
        if hwnd.is_invalid() {
            return None;
        }

        let mut process_id = 0;
        GetWindowThreadProcessId(hwnd, Some(&mut process_id));
        if process_id == 0 {
            return None;
        }

        let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, process_id).ok()?;
        let mut buffer = [0u16; 1024];
        let length = GetModuleFileNameExW(handle, None, &mut buffer);
        let _ = windows::Win32::Foundation::CloseHandle(handle);

        if length > 0 {
            Some(String::from_utf16_lossy(&buffer[..length as usize]))
        } else {
            None
        }
    }
}

pub fn get_frontmost_app_name() -> Option<String> {
    get_frontmost_app_bundle_id().map(|path| {
        std::path::Path::new(&path)
            .file_name()
            .and_then(|f| f.to_str())
            .unwrap_or("Unknown")
            .to_string()
    })
}

pub fn get_application_info_by_path_json(path: &str) -> Option<String> {
    let name = std::path::Path::new(path)
        .file_name()
        .and_then(|f| f.to_str())
        .unwrap_or("Unknown")
        .to_string();

    let icon = get_icon_base64_from_path(path);
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
    // If it's already a path, use it. Otherwise return a basic object
    if std::path::Path::new(name).exists() {
        get_application_info_by_path_json(name)
    } else {
        let app = serde_json::json!({
            "bundle_id": name,
            "name": name,
            "icon": ""
        });
        Some(app.to_string())
    }
}
