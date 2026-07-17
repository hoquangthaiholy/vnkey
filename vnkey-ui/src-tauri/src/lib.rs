use serde::{Deserialize, Serialize};
use std::sync::{Arc, RwLock};
use std::thread;
use lazy_static::lazy_static;
#[cfg(not(target_os = "macos"))]
use rdev::{Event, EventType, Key, simulate, grab};
#[cfg(target_os = "macos")]
use rdev::Key;
use tauri::{Manager, Emitter};
use tauri::tray::TrayIconBuilder;
use tauri::menu::{Menu, MenuItem};
use vnkey_engine::{Engine, EngineConfig, InputMethod};
use vnkey_engine::tone::ToneStyle;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    pub method: String,        // "Off", "Telex", "Vni"
    pub tone_style: String,    // "Modern", "Classic"
    pub spelling_check: bool,
}

lazy_static! {
    static ref SETTINGS: Arc<RwLock<AppSettings>> = Arc::new(RwLock::new(AppSettings {
        method: "Telex".to_string(),
        tone_style: "Modern".to_string(),
        spelling_check: true,
    }));
    static ref ENGINE: Arc<RwLock<Engine>> = Arc::new(RwLock::new(Engine::new(EngineConfig {
        method: InputMethod::Telex,
        tone_style: ToneStyle::Modern,
        spelling_check: true,
    })));
    static ref SHIFT_PRESSED: Arc<RwLock<bool>> = Arc::new(RwLock::new(false));
    static ref TRAY_TOGGLE_ITEM: Arc<RwLock<Option<MenuItem<tauri::Wry>>>> = Arc::new(RwLock::new(None));
    static ref NORMAL_ICON: Arc<RwLock<Option<tauri::image::Image<'static>>>> = Arc::new(RwLock::new(None));
    static ref DIMMED_ICON: Arc<RwLock<Option<tauri::image::Image<'static>>>> = Arc::new(RwLock::new(None));
}

// CMD_SENDER and KeyboardCmd are removed since execution is synchronous

static ACTIVE_LAYOUT_IS_ENGLISH: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
static ACTIVE_MODE_IS_VIETNAMESE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static INITIAL_RUN_DONE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static IS_SPOTLIGHT_OR_ELECTRON: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

#[tauri::command]
fn has_accessibility() -> bool {
    #[cfg(target_os = "macos")]
    {
        extern "C" {
            fn AXIsProcessTrusted() -> bool;
        }
        unsafe { AXIsProcessTrusted() }
    }
    #[cfg(not(target_os = "macos"))]
    {
        true
    }
}

#[tauri::command]
fn request_accessibility() {
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("open")
            .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            .status();
    }
}

#[tauri::command]
fn get_settings() -> AppSettings {
    let s = SETTINGS.read().unwrap();
    s.clone()
}

#[tauri::command]
fn update_settings(new_settings: AppSettings, app_handle: tauri::AppHandle) -> Result<(), String> {
    // 1. Update global settings state
    {
        let mut s = SETTINGS.write().unwrap();
        *s = new_settings.clone();
    }

    // 2. Map and update the Engine config
    let method = match new_settings.method.as_str() {
        "Telex" => InputMethod::Telex,
        "Vni" => InputMethod::Vni,
        _ => InputMethod::Off,
    };

    let tone_style = match new_settings.tone_style.as_str() {
        "Classic" => ToneStyle::Classic,
        _ => ToneStyle::Modern,
    };

    {
        let mut eng = ENGINE.write().unwrap();
        eng.update_config(EngineConfig {
            method,
            tone_style,
            spelling_check: new_settings.spelling_check,
        });
    }

    // Emit event to frontend if needed
    let _ = app_handle.emit("settings-changed", new_settings);

    Ok(())
}

// Low level simulated inputs
fn key_to_char(key: Key, shift: bool) -> Option<char> {
    let c = match key {
        Key::KeyA => 'a',
        Key::KeyB => 'b',
        Key::KeyC => 'c',
        Key::KeyD => 'd',
        Key::KeyE => 'e',
        Key::KeyF => 'f',
        Key::KeyG => 'g',
        Key::KeyH => 'h',
        Key::KeyI => 'i',
        Key::KeyJ => 'j',
        Key::KeyK => 'k',
        Key::KeyL => 'l',
        Key::KeyM => 'm',
        Key::KeyN => 'n',
        Key::KeyO => 'o',
        Key::KeyP => 'p',
        Key::KeyQ => 'q',
        Key::KeyR => 'r',
        Key::KeyS => 's',
        Key::KeyT => 't',
        Key::KeyU => 'u',
        Key::KeyV => 'v',
        Key::KeyW => 'w',
        Key::KeyX => 'x',
        Key::KeyY => 'y',
        Key::KeyZ => 'z',
        Key::Num1 => { if shift { return None; } else { '1' } },
        Key::Num2 => { if shift { return None; } else { '2' } },
        Key::Num3 => { if shift { return None; } else { '3' } },
        Key::Num4 => { if shift { return None; } else { '4' } },
        Key::Num5 => { if shift { return None; } else { '5' } },
        Key::Num6 => { if shift { return None; } else { '6' } },
        Key::Num7 => { if shift { return None; } else { '7' } },
        Key::Num8 => { if shift { return None; } else { '8' } },
        Key::Num9 => { if shift { return None; } else { '9' } },
        Key::Num0 => { if shift { return None; } else { '0' } },
        _ => return None,
    };
    if shift {
        Some(c.to_ascii_uppercase())
    } else {
        Some(c)
    }
}

#[cfg(not(target_os = "macos"))]
fn send_backspace() {
    let _ = simulate(&EventType::KeyPress(Key::Backspace));
    let _ = simulate(&EventType::KeyRelease(Key::Backspace));
}

#[cfg(not(target_os = "macos"))]
fn send_unicode_char(c: char) {
    println!("[Engine Out] {}", c);
}

#[cfg(not(target_os = "macos"))]
fn send_unicode_string(text: &str) {
    for c in text.chars() {
        send_unicode_char(c);
    }
}

#[cfg(not(target_os = "macos"))]
fn hook_callback(event: Event) -> Option<Event> {
    // If we are currently simulating keystrokes, do not intercept/modify them
    if *IS_SIMULATING.read().unwrap() {
        return Some(event);
    }

    match event.event_type {
        EventType::KeyPress(key) => {
            if key == Key::ShiftLeft || key == Key::ShiftRight {
                let mut s = SHIFT_PRESSED.write().unwrap();
                *s = true;
                return Some(event);
            }

            if key == Key::Space || key == Key::Return || key == Key::Escape || key == Key::Backspace {
                let mut eng = ENGINE.write().unwrap();
                eng.reset();
                return Some(event);
            }

            let shift = *SHIFT_PRESSED.read().unwrap();
            if let Some(c) = key_to_char(key, shift) {
                // Keep lock lifetime minimal by using an inner block
                let result = {
                    let mut eng = ENGINE.write().unwrap();
                    eng.process_key(c)
                };

                match result {
                    EngineResult::Keep => Some(event),
                    EngineResult::Replace { backspaces, text } => {
                        thread::spawn(move || {
                            // Set simulating flag to true to ignore these events
                            {
                                let mut sim = IS_SIMULATING.write().unwrap();
                                *sim = true;
                            }

                            for _ in 0..backspaces {
                                send_backspace();
                            }
                            send_unicode_string(&text);

                            // Done simulating, unset flag
                            {
                                let mut sim = IS_SIMULATING.write().unwrap();
                                *sim = false;
                            }
                        });
                        None
                    }
                    EngineResult::Reset => Some(event),
                }
            } else {
                let mut eng = ENGINE.write().unwrap();
                eng.reset();
                Some(event)
            }
        }
        EventType::KeyRelease(key) => {
            if key == Key::ShiftLeft || key == Key::ShiftRight {
                let mut s = SHIFT_PRESSED.write().unwrap();
                *s = false;
            }
            Some(event)
        }
        _ => Some(event),
    }
}

#[cfg(target_os = "macos")]
mod macos_tap {
    use std::ffi::c_void;
    use crate::{ENGINE, SHIFT_PRESSED, key_to_char, ACTIVE_LAYOUT_IS_ENGLISH};
    use vnkey_engine::EngineResult;
    use objc2_app_kit::NSWorkspace;
    use std::path::Path;

    type CGEventTapProxy = *mut c_void;
    type CGEventRef = *mut c_void;
    type CGEventTapRef = *mut c_void;

    #[repr(C)]
    #[derive(Clone, Copy, Debug)]
    pub struct CFRange {
        pub location: isize,
        pub length: isize,
    }

    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        fn CGEventSourceCreate(state_id: i32) -> *mut c_void;
        fn CGEventTapCreate(
            tap: u32,
            place: u32,
            options: u32,
            eventsOfInterest: u64,
            callback: unsafe extern "C" fn(CGEventTapProxy, u32, CGEventRef, *mut c_void) -> CGEventRef,
            refcon: *mut c_void,
        ) -> CGEventRef;
        fn CGEventTapEnable(tap: CGEventRef, enable: bool);
        fn CFMachPortCreateRunLoopSource(allocator: *mut c_void, port: CGEventRef, order: isize) -> *mut c_void;
        fn CFRunLoopGetCurrent() -> *mut c_void;
        fn CFRunLoopAddSource(rl: *mut c_void, source: *mut c_void, mode: *const c_void);
        fn CFRunLoopRun();
        fn CGEventGetIntegerValueField(event: CGEventRef, field: u32) -> i64;
        fn CGEventSetIntegerValueField(event: CGEventRef, field: u32, value: i64);
        fn CGEventGetFlags(event: CGEventRef) -> u64;
        fn CGEventPost(tap: u32, event: CGEventRef);
        fn CGEventTapPostEvent(proxy: CGEventTapProxy, event: CGEventRef);
        fn CGEventCreateKeyboardEvent(source: *mut c_void, key: u16, down: bool) -> CGEventRef;
        fn CGEventKeyboardSetUnicodeString(event: CGEventRef, length: usize, string: *const u16);
        fn CFRelease(obj: *const c_void);

        // Accessibility API
        fn AXUIElementCreateSystemWide() -> *mut c_void;
        fn AXUIElementCopyAttributeValue(
            element: *mut c_void,
            attribute: *const c_void,
            value: *mut *mut c_void,
        ) -> i32;
        fn AXUIElementSetAttributeValue(
            element: *mut c_void,
            attribute: *const c_void,
            value: *const c_void,
        ) -> i32;
        fn AXValueCreate(theType: u32, valuePtr: *const c_void) -> *mut c_void;
        fn AXValueGetValue(value: *mut c_void, theType: u32, valuePtr: *mut c_void) -> bool;
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        fn CFStringCreateWithBytes(
            alloc: *mut c_void,
            bytes: *const u8,
            numBytes: isize,
            encoding: u32,
            isExternalRepresentation: bool,
        ) -> *mut c_void;
    }


    const KCGSessionEventTap: u32 = 1;
    const KCGHeadInsertEventTap: u32 = 0;
    const KCGEventTapOptionDefault: u32 = 0;

    const KCGEventKeyDown: u32 = 10;
    const KCGEventFlagsChanged: u32 = 12;
    const KCGEventTapDisabledByTimeout: u32 = 0xFFFFFFFE;
    const KCGEventTapDisabledByUserInput: u32 = 0xFFFFFFFF;

    const KCGEventFieldKeyboardEventKeycode: u32 = 9;

    const FLAG_SHIFT: u64 = 0x00020000;
    const FLAG_CONTROL: u64 = 0x00040000;
    const FLAG_ALTERNATE: u64 = 0x00080000;
    const FLAG_COMMAND: u64 = 0x00100000;

    fn has_shift(flags: u64) -> bool {
        (flags & FLAG_SHIFT) != 0
    }

    const SIGNATURE: i64 = 0x12345678;
    static mut EVENT_SOURCE: *mut c_void = std::ptr::null_mut();
    static mut ACTIVE_TAP: CGEventTapRef = std::ptr::null_mut();

    fn send_backspaces(proxy: CGEventTapProxy, count: usize) {
        unsafe {
            let source = EVENT_SOURCE;
            for _ in 0..count {
                let down = CGEventCreateKeyboardEvent(source, 51, true);
                let up = CGEventCreateKeyboardEvent(source, 51, false);
                if !down.is_null() {
                    CGEventSetIntegerValueField(down, 42, SIGNATURE);
                    CGEventTapPostEvent(proxy, down);
                    CFRelease(down);
                }
                if !up.is_null() {
                    CGEventSetIntegerValueField(up, 42, SIGNATURE);
                    CGEventTapPostEvent(proxy, up);
                    CFRelease(up);
                }
            }
        }
    }

    fn char_to_keycode(c: char) -> u16 {
        let lower = c.to_lowercase().next().unwrap_or(c);
        match lower {
            'a' | 'á' | 'à' | 'ả' | 'ã' | 'ạ' |
            'â' | 'ấ' | 'ầ' | 'ẩ' | 'ẫ' | 'ậ' |
            'ă' | 'ắ' | 'ằ' | 'ẳ' | 'ẵ' | 'ặ' => 0, // Key A
            
            'b' => 11, // Key B
            'c' => 8,  // Key C
            
            'd' | 'đ' => 2, // Key D
            
            'e' | 'é' | 'è' | 'ẻ' | 'ẽ' | 'ẹ' |
            'ê' | 'ế' | 'ề' | 'ể' | 'ễ' | 'ệ' => 14, // Key E
            
            'f' => 3,  // Key F
            'g' => 5,  // Key G
            'h' => 4,  // Key H
            
            'i' | 'í' | 'ì' | 'ỉ' | 'ĩ' | 'ị' => 34, // Key I
            
            'j' => 38, // Key J
            'k' => 40, // Key K
            'l' => 37, // Key L
            'm' => 46, // Key M
            'n' => 45, // Key N
            
            'o' | 'ó' | 'ò' | 'ỏ' | 'õ' | 'ọ' |
            'ô' | 'ố' | 'ồ' | 'ổ' | 'ỗ' | 'ộ' |
            'ơ' | 'ớ' | 'ờ' | 'ở' | 'ỡ' | 'ợ' => 31, // Key O
            
            'p' => 35, // Key P
            'q' => 12, // Key Q
            'r' => 15, // Key R
            's' => 1,  // Key S
            't' => 17, // Key T
            
            'u' | 'ú' | 'ù' | 'ủ' | 'ũ' | 'ụ' |
            'ư' | 'ứ' | 'ừ' | 'ử' | 'ữ' | 'ự' => 32, // Key U
            
            'v' => 9,  // Key V
            'w' => 13, // Key W
            'x' => 7,  // Key X
            
            'y' | 'ý' | 'ỳ' | 'ỷ' | 'ỹ' | 'ỵ' => 16, // Key Y
            
            'z' => 6,  // Key Z
            
            _ => 0, // Default to A
        }
    }

    fn send_unicode_string(proxy: CGEventTapProxy, text: &str) {
        unsafe {
            let source = EVENT_SOURCE;
            for c in text.chars() {
                let s_str = c.to_string();
                let utf16: Vec<u16> = s_str.encode_utf16().collect();
                let keycode = char_to_keycode(c);
                
                let down = CGEventCreateKeyboardEvent(source, keycode, true);
                let up = CGEventCreateKeyboardEvent(source, keycode, false);
                if !down.is_null() {
                    CGEventKeyboardSetUnicodeString(down, utf16.len(), utf16.as_ptr());
                    CGEventSetIntegerValueField(down, 42, SIGNATURE);
                    CGEventTapPostEvent(proxy, down);
                    CFRelease(down);
                }
                if !up.is_null() {
                    CGEventKeyboardSetUnicodeString(up, utf16.len(), utf16.as_ptr());
                    CGEventSetIntegerValueField(up, 42, SIGNATURE);
                    CGEventTapPostEvent(proxy, up);
                    CFRelease(up);
                }
            }
        }
    }

    fn create_cf_string(s: &str) -> *mut c_void {
        unsafe {
            CFStringCreateWithBytes(
                std::ptr::null_mut(),
                s.as_ptr(),
                s.len() as isize,
                0x08000100, // UTF-8
                false,
            )
        }
    }

    fn is_spotlight_or_electron_app() -> bool {
        super::IS_SPOTLIGHT_OR_ELECTRON.load(std::sync::atomic::Ordering::Relaxed)
    }

    pub fn update_active_app_state() {
        let workspace = NSWorkspace::sharedWorkspace();
        let Some(app) = workspace.frontmostApplication() else {
            return;
        };

        let current_bundle_id = app.bundleIdentifier().map(|id| id.to_string());
        let mut is_electron = false;

        // 1. Check bundle identifier
        if let Some(ref bundle_id_str) = current_bundle_id {
            if bundle_id_str == "com.apple.Spotlight" {
                is_electron = true;
            } else {
                let known_electron_ids = [
                    "com.microsoft.VSCode",
                    "com.tinyspeck.slackmacgap",
                    "com.hnc.Discord",
                    "com.aversoft.Discord",
                    "md.obsidian",
                    "com.figma.Desktop",
                    "com.electron.native-host",
                ];
                if known_electron_ids.iter().any(|id| bundle_id_str.contains(id)) {
                    is_electron = true;
                }
            }
        }

        // 2. Check bundle URL for Electron framework or app.asar
        if !is_electron {
            if let Some(bundle_url) = app.bundleURL() {
                if let Some(path_ns) = bundle_url.path() {
                    let path_str = path_ns.to_string();
                    let path = Path::new(&path_str);
                    let electron_framework = path.join("Contents/Frameworks/Electron Framework.framework");
                    let app_asar = path.join("Contents/Resources/app.asar");
                    if electron_framework.exists() || app_asar.exists() {
                        is_electron = true;
                    }
                }
            }
        }

        super::IS_SPOTLIGHT_OR_ELECTRON.store(is_electron, std::sync::atomic::Ordering::Relaxed);
    }



    unsafe fn send_via_accessibility(backspaces: usize, text: &str) -> bool {
        let system_wide = AXUIElementCreateSystemWide();
        if system_wide.is_null() {
            return false;
        }

        let focused_attr = create_cf_string("AXFocusedUIElement");
        let mut focused_element: *mut c_void = std::ptr::null_mut();
        let err = AXUIElementCopyAttributeValue(system_wide, focused_attr, &mut focused_element);
        CFRelease(focused_attr);
        CFRelease(system_wide);

        if err != 0 || focused_element.is_null() {
            return false;
        }

        let range_attr = create_cf_string("AXSelectedTextRange");
        let mut selected_range_val: *mut c_void = std::ptr::null_mut();
        let err = AXUIElementCopyAttributeValue(focused_element, range_attr, &mut selected_range_val);

        if err != 0 || selected_range_val.is_null() {
            CFRelease(range_attr);
            CFRelease(focused_element);
            return false;
        }

        let mut range = CFRange { location: 0, length: 0 };
        let decoded = AXValueGetValue(selected_range_val, 4, &mut range as *mut _ as *mut c_void); // kAXValueTypeCFRange is 4
        CFRelease(selected_range_val);

        if !decoded {
            CFRelease(range_attr);
            CFRelease(focused_element);
            return false;
        }

        // Calculate new range to select and replace
        let new_location = if range.location >= backspaces as isize {
            range.location - backspaces as isize
        } else {
            0
        };
        let new_length = range.location - new_location + range.length;

        let new_range = CFRange {
            location: new_location,
            length: new_length,
        };

        let new_range_val = AXValueCreate(4, &new_range as *const _ as *const c_void);
        if new_range_val.is_null() {
            CFRelease(range_attr);
            CFRelease(focused_element);
            return false;
        }

        let err = AXUIElementSetAttributeValue(focused_element, range_attr, new_range_val);
        CFRelease(range_attr);
        CFRelease(new_range_val);

        if err != 0 {
            CFRelease(focused_element);
            return false;
        }

        // Set AXSelectedText to insert/replace selection
        let text_attr = create_cf_string("AXSelectedText");
        let text_val = create_cf_string(text);
        let err = AXUIElementSetAttributeValue(focused_element, text_attr, text_val);
        CFRelease(text_attr);
        CFRelease(text_val);

        CFRelease(focused_element);
        err == 0
    }

    unsafe extern "C" fn tap_callback(
        proxy: CGEventTapProxy,
        event_type: u32,
        event: CGEventRef,
        _refcon: *mut c_void,
    ) -> CGEventRef {
        if event_type == KCGEventTapDisabledByTimeout || event_type == KCGEventTapDisabledByUserInput {
            unsafe {
                if !ACTIVE_TAP.is_null() {
                    CGEventTapEnable(ACTIVE_TAP, true);
                }
            }
            return event;
        }

        let is_simulated = CGEventGetIntegerValueField(event, 42) == SIGNATURE;
        if is_simulated {
            return event;
        }

        if event_type == KCGEventFlagsChanged {
            let flags = CGEventGetFlags(event);
            let mut shift = SHIFT_PRESSED.write().unwrap();
            *shift = has_shift(flags);
            return event;
        }

        if event_type == KCGEventKeyDown {
            if !ACTIVE_LAYOUT_IS_ENGLISH.load(std::sync::atomic::Ordering::Relaxed) {
                return event;
            }
            let flags = CGEventGetFlags(event);
            if (flags & (FLAG_CONTROL | FLAG_ALTERNATE | FLAG_COMMAND)) != 0 {
                let mut eng = ENGINE.write().unwrap();
                eng.reset();
                return event;
            }

            let keycode = CGEventGetIntegerValueField(event, KCGEventFieldKeyboardEventKeycode) as u16;
            if keycode == 53 || keycode == 36 || keycode == 48 || keycode == 51 {
                let mut eng = ENGINE.write().unwrap();
                eng.reset();
                return event;
            }

            let rdev_key = match keycode {
                0 => rdev::Key::KeyA,
                1 => rdev::Key::KeyS,
                2 => rdev::Key::KeyD,
                3 => rdev::Key::KeyF,
                5 => rdev::Key::KeyG,
                4 => rdev::Key::KeyH,
                38 => rdev::Key::KeyJ,
                40 => rdev::Key::KeyK,
                37 => rdev::Key::KeyL,
                46 => rdev::Key::KeyM,
                45 => rdev::Key::KeyN,
                31 => rdev::Key::KeyO,
                35 => rdev::Key::KeyP,
                12 => rdev::Key::KeyQ,
                15 => rdev::Key::KeyR,
                11 => rdev::Key::KeyB,
                8 => rdev::Key::KeyC,
                14 => rdev::Key::KeyE,
                34 => rdev::Key::KeyI,
                17 => rdev::Key::KeyT,
                32 => rdev::Key::KeyU,
                9 => rdev::Key::KeyV,
                13 => rdev::Key::KeyW,
                7 => rdev::Key::KeyX,
                16 => rdev::Key::KeyY,
                6 => rdev::Key::KeyZ,
                18 => rdev::Key::Num1,
                19 => rdev::Key::Num2,
                20 => rdev::Key::Num3,
                21 => rdev::Key::Num4,
                23 => rdev::Key::Num5,
                22 => rdev::Key::Num6,
                26 => rdev::Key::Num7,
                28 => rdev::Key::Num8,
                25 => rdev::Key::Num9,
                29 => rdev::Key::Num0,
                _ => {
                    let mut eng = ENGINE.write().unwrap();
                    eng.reset();
                    return event;
                }
            };

            let shift_held = *SHIFT_PRESSED.read().unwrap();
            if let Some(c) = key_to_char(rdev_key, shift_held) {
                let result = {
                    let mut eng = ENGINE.write().unwrap();
                    eng.process_key(c)
                };

                match result {
                    EngineResult::Keep => event,
                    EngineResult::Replace { backspaces, text } => {
                        let mut success = false;
                        if is_spotlight_or_electron_app() {
                            unsafe {
                                success = send_via_accessibility(backspaces, &text);
                            }
                        }
                        if !success {
                            send_backspaces(proxy, backspaces);
                            send_unicode_string(proxy, &text);
                        }
                        std::ptr::null_mut()
                    }
                    EngineResult::Reset => event,
                }
            } else {
                let mut eng = ENGINE.write().unwrap();
                eng.reset();
                event
            }
        } else {
            event
        }
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        static kCFRunLoopDefaultMode: *const c_void;
    }

    pub fn start_macos_native_hook() {
        println!("Starting native macOS CGEventTap hook...");
        
        // No background thread needed for synchronous event execution

        unsafe {
            EVENT_SOURCE = CGEventSourceCreate(1);
            let mask = (1 << KCGEventKeyDown) | (1 << KCGEventFlagsChanged);
            let tap = CGEventTapCreate(
                KCGSessionEventTap,
                KCGHeadInsertEventTap,
                KCGEventTapOptionDefault,
                mask,
                tap_callback,
                std::ptr::null_mut(),
            );

            if tap.is_null() {
                eprintln!("Error: Cannot create CGEventTap! Ensure Accessibility permissions are granted.");
                return;
            }

            ACTIVE_TAP = tap;

            let source = CFMachPortCreateRunLoopSource(std::ptr::null_mut(), tap, 0);
            let run_loop = CFRunLoopGetCurrent();
            CFRunLoopAddSource(run_loop, source, kCFRunLoopDefaultMode);
            CGEventTapEnable(tap, true);
            CFRunLoopRun();
        }
    }

    #[allow(dead_code)]
    pub fn re_enable_tap() {
        unsafe {
            if !ACTIVE_TAP.is_null() {
                CGEventTapEnable(ACTIVE_TAP, true);
            }
        }
    }
}

#[cfg(target_os = "macos")]
#[link(name = "Carbon", kind = "framework")]
extern "C" {
    static kTISPropertyInputSourceID: *const std::ffi::c_void;
    fn TISCopyCurrentKeyboardInputSource() -> *mut std::ffi::c_void;
    fn TISGetInputSourceProperty(source: *mut std::ffi::c_void, property_key: *const std::ffi::c_void) -> *const std::ffi::c_void;
}

#[cfg(target_os = "macos")]
#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFStringGetCString(
        theString: *const std::ffi::c_void,
        buffer: *mut u8,
        bufferSize: isize,
        encoding: u32,
    ) -> bool;
    fn CFRelease(obj: *const std::ffi::c_void);
}

#[cfg(target_os = "macos")]
#[link(name = "AppKit", kind = "framework")]
extern "C" {
    static NSFontAttributeName: *mut objc2::runtime::AnyObject;
    static NSForegroundColorAttributeName: *mut objc2::runtime::AnyObject;
    static NSParagraphStyleAttributeName: *mut objc2::runtime::AnyObject;
}

#[cfg(target_os = "macos")]
fn generate_icon_image(is_eng: bool) -> tauri::image::Image<'static> {
    use objc2::msg_send;
    use objc2_foundation::{NSPoint, NSSize, NSRect};

    let size_18 = NSSize { width: 18.0, height: 18.0 };

    unsafe {
        // 1. Create NSImage of size 18x18
        let nsimage_class = objc2::class!(NSImage);
        let image: *mut objc2::runtime::AnyObject = msg_send![nsimage_class, alloc];
        let image: *mut objc2::runtime::AnyObject = msg_send![image, initWithSize: size_18];

        let _: () = msg_send![image, lockFocus];

        // 2. Draw rounded rect (16x16 box inside 18x18 canvas, centered: x=1, y=1)
        let rect = NSRect {
            origin: NSPoint { x: 1.0, y: 1.0 },
            size: NSSize { width: 16.0, height: 16.0 },
        };
        let nsbezierpath_class = objc2::class!(NSBezierPath);
        let path: *mut objc2::runtime::AnyObject = msg_send![
            nsbezierpath_class,
            bezierPathWithRoundedRect: rect,
            xRadius: 2.0f64,
            yRadius: 2.0f64
        ];

        let nscolor_class = objc2::class!(NSColor);
        let color_black: *mut objc2::runtime::AnyObject = msg_send![nscolor_class, blackColor];
        let _: () = msg_send![color_black, set];
        let _: () = msg_send![path, fill];

        // 3. Create string "E" or "V"
        let text_str = if is_eng { "E" } else { "V" };
        let nsstring_class = objc2::class!(NSString);
        let text: *mut objc2::runtime::AnyObject = msg_send![nsstring_class, alloc];
        let text: *mut objc2::runtime::AnyObject = msg_send![
            text,
            initWithBytes: text_str.as_ptr(),
            length: text_str.len(),
            encoding: 4usize // NSUTF8StringEncoding = 4
        ];

        // 4. Create font and paragraph style
        let nsfont_class = objc2::class!(NSFont);
        // systemFontOfSize: 13.0 with weight 0.23 (Medium) to match other system menu bar icons
        let font: *mut objc2::runtime::AnyObject = msg_send![nsfont_class, systemFontOfSize: 13.0f64, weight: 0.23f64];

        let nsmutableparagraphstyle_class = objc2::class!(NSMutableParagraphStyle);
        let style: *mut objc2::runtime::AnyObject = msg_send![nsmutableparagraphstyle_class, alloc];
        let style: *mut objc2::runtime::AnyObject = msg_send![style, init];
        // NSTextAlignmentCenter = 1
        let _: () = msg_send![style, setAlignment: 1isize];

        // 5. Create attributes dictionary
        let color_white: *mut objc2::runtime::AnyObject = msg_send![nscolor_class, whiteColor];
        let keys = [
            NSFontAttributeName,
            NSForegroundColorAttributeName,
            NSParagraphStyleAttributeName,
        ];
        let objects = [font, color_white, style];
        let nsdictionary_class = objc2::class!(NSDictionary);
        let attrs: *mut objc2::runtime::AnyObject = msg_send![
            nsdictionary_class,
            dictionaryWithObjects: objects.as_ptr(),
            forKeys: keys.as_ptr(),
            count: 3usize
        ];

        // 6. Calculate text size
        let text_size: NSSize = msg_send![text, sizeWithAttributes: attrs];

        // Center vertically inside the 16x16 box
        let text_y = rect.origin.y + (rect.size.height - text_size.height) * 0.5;
        let text_rect = NSRect {
            origin: NSPoint { x: rect.origin.x, y: text_y },
            size: NSSize { width: rect.size.width, height: text_size.height },
        };

        // Draw string (draws white text on black background)
        let _: () = msg_send![text, drawInRect: text_rect, withAttributes: attrs];

        let _: () = msg_send![image, unlockFocus];

        // 7. Create NSBitmapImageRep (36x36 pixels)
        let nsbitmapimagerep_class = objc2::class!(NSBitmapImageRep);
        let rep: *mut objc2::runtime::AnyObject = msg_send![nsbitmapimagerep_class, alloc];
        let color_space_name: *mut objc2::runtime::AnyObject = msg_send![nsstring_class, alloc];
        let color_space_name: *mut objc2::runtime::AnyObject = msg_send![color_space_name, initWithUTF8String: b"NSDeviceRGBColorSpace\0".as_ptr() as *const i8];
        
        let rep: *mut objc2::runtime::AnyObject = msg_send![
            rep,
            initWithBitmapDataPlanes: std::ptr::null_mut::<*mut u8>(),
            pixelsWide: 36isize,
            pixelsHigh: 36isize,
            bitsPerSample: 8isize,
            samplesPerPixel: 4isize,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: color_space_name,
            bytesPerRow: 144isize,
            bitsPerPixel: 32isize
        ];
        
        let _: () = msg_send![rep, setSize: size_18];

        let nsgraphicscontext_class = objc2::class!(NSGraphicsContext);
        let _: () = msg_send![nsgraphicscontext_class, saveGraphicsState];
        let bitmap_context: *mut objc2::runtime::AnyObject = msg_send![nsgraphicscontext_class, graphicsContextWithBitmapImageRep: rep];
        let _: () = msg_send![nsgraphicscontext_class, setCurrentContext: bitmap_context];

        // Draw NSImage into NSBitmapImageRep (NSCompositingOperationSourceOver = 2)
        let _: () = msg_send![
            image,
            drawInRect: NSRect {
                origin: NSPoint { x: 0.0, y: 0.0 },
                size: NSSize { width: 18.0, height: 18.0 },
            },
            fromRect: NSRect {
                origin: NSPoint { x: 0.0, y: 0.0 },
                size: NSSize { width: 0.0, height: 0.0 },
            },
            operation: 2usize,
            fraction: 1.0f64
        ];

        let _: () = msg_send![nsgraphicscontext_class, restoreGraphicsState];

        // 8. Extract and copy raw data, converting white text to transparent cutout
        let data_ptr: *mut u8 = msg_send![rep, bitmapData];
        let mut bytes = vec![0u8; 36 * 36 * 4];
        
        for i in (0..bytes.len()).step_by(4) {
            let r = *data_ptr.add(i) as f32;     // R channel (since text is white, R=255, box has R=0)
            let a = *data_ptr.add(i + 3) as f32; // A channel (box has A=255, background A=0)
            
            // Calculate final alpha (box_alpha * (1.0 - text_intensity))
            let final_a = (a * (255.0 - r) / 255.0).round() as u8;
            
            bytes[i] = 0;     // R = 0
            bytes[i + 1] = 0; // G = 0
            bytes[i + 2] = 0; // B = 0
            bytes[i + 3] = final_a; // A = final_a
        }

        // 9. Clean up allocated objects
        let _: () = msg_send![image, release];
        let _: () = msg_send![text, release];
        let _: () = msg_send![style, release];
        let _: () = msg_send![color_space_name, release];
        let _: () = msg_send![rep, release];

        tauri::image::Image::new_owned(bytes, 36, 36)
    }
}

#[cfg(not(target_os = "macos"))]
fn generate_icon_image(is_eng: bool) -> tauri::image::Image<'static> {
    let width = 36;
    let height = 36;
    let mut rgba = vec![0u8; (width * height * 4) as usize];
    
    // Helper function for rectangle
    fn rect_coverage(px: f32, py: f32, x1: f32, x2: f32, y1: f32, y2: f32) -> f32 {
        let cx = (x1 + x2) * 0.5;
        let cy = (y1 + y2) * 0.5;
        let rx = (x2 - x1) * 0.5;
        let ry = (y2 - y1) * 0.5;
        
        let cov_x = (0.5 + rx - (px - cx).abs()).clamp(0.0, 1.0);
        let cov_y = (0.5 + ry - (py - cy).abs()).clamp(0.0, 1.0);
        cov_x * cov_y
    }
    
    // Helper function for line segment
    fn line_coverage(px: f32, py: f32, ax: f32, ay: f32, bx: f32, by: f32, w: f32) -> f32 {
        let dx = bx - ax;
        let dy = by - ay;
        let len_sq = dx * dx + dy * dy;
        if len_sq == 0.0 {
            let dist = ((px - ax) * (px - ax) + (py - ay) * (py - ay)).sqrt();
            let r = w * 0.5;
            return (r + 0.5 - dist).clamp(0.0, 1.0);
        }
        
        let t = (((px - ax) * dx + (py - ay) * dy) / len_sq).clamp(0.0, 1.0);
        let cx = ax + t * dx;
        let cy = ay + t * dy;
        let dist = ((px - cx) * (px - cx) + (py - cy) * (py - cy)).sqrt();
        let r = w * 0.5;
        (r + 0.5 - dist).clamp(0.0, 1.0)
    }
    
    for y in 0..height {
        for x in 0..width {
            let px = x as f32 + 0.5;
            let py = y as f32 + 0.5;
            
            let mut box_coverage = 0.0f32;
            
            if px >= 4.0 && px <= 32.0 && py >= 4.0 && py <= 32.0 {
                let is_left = px < 12.0;
                let is_right = px > 24.0;
                let is_top = py < 12.0;
                let is_bottom = py > 24.0;
                
                if (is_left || is_right) && (is_top || is_bottom) {
                    let cx = if is_left { 12.0 } else { 24.0 };
                    let cy = if is_top { 12.0 } else { 24.0 };
                    let dx = px - cx;
                    let dy = py - cy;
                    let d = (dx * dx + dy * dy).sqrt();
                    let r = 8.0;
                    if d <= r - 0.5 {
                        box_coverage = 1.0;
                    } else if d >= r + 0.5 {
                        box_coverage = 0.0;
                    } else {
                        box_coverage = r + 0.5 - d;
                    }
                } else {
                    box_coverage = 1.0;
                }
            }
            
            let w = 3.5;
            let char_coverage = if is_eng {
                let cov_stem = rect_coverage(px, py, 11.0, 11.0 + w, 9.0, 27.0);
                let cov_top = rect_coverage(px, py, 11.0, 25.0, 9.0, 9.0 + w);
                let cov_bottom = rect_coverage(px, py, 11.0, 25.0, 27.0 - w, 27.0);
                let cov_middle = rect_coverage(px, py, 11.0, 23.0, 18.0 - w * 0.5, 18.0 + w * 0.5);
                cov_stem.max(cov_top).max(cov_bottom).max(cov_middle)
            } else {
                let cov_left = line_coverage(px, py, 12.75, 9.0, 18.0, 26.5, w);
                let cov_right = line_coverage(px, py, 23.25, 9.0, 18.0, 26.5, w);
                cov_left.max(cov_right)
            };
            
            let final_coverage = box_coverage * (1.0 - char_coverage);
            
            let idx = ((y * width + x) * 4) as usize;
            rgba[idx] = 0;
            rgba[idx + 1] = 0;
            rgba[idx + 2] = 0;
            rgba[idx + 3] = (final_coverage * 255.0).round() as u8;
        }
    }
    
    tauri::image::Image::new_owned(rgba, width, height)
}

#[cfg(target_os = "macos")]
fn is_english_ime() -> bool {
    unsafe {
        let source = TISCopyCurrentKeyboardInputSource();
        if source.is_null() {
            return true;
        }
        
        let source_id_ref = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
        if source_id_ref.is_null() {
            CFRelease(source);
            return true;
        }
        
        let mut buf = [0u8; 256];
        let mut is_eng = true;
        if CFStringGetCString(source_id_ref, buf.as_mut_ptr(), buf.len() as isize, 0x08000100) {
            let id_str = std::ffi::CStr::from_ptr(buf.as_ptr() as *const i8).to_string_lossy();
            let lower_id = id_str.to_lowercase();
            if lower_id.contains("vietnamese") || lower_id.contains("telex") || lower_id.contains("vni") {
                is_eng = false;
            }
        }
        CFRelease(source);
        is_eng
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Spawn background key grab loop
    thread::spawn(|| {
        println!("Initializing VNKey hook thread...");
        
        // On macOS, wait until accessibility permission is granted before starting the hook
        #[cfg(target_os = "macos")]
        {
            loop {
                if has_accessibility() {
                    break;
                }
                println!("Accessibility permission not granted yet. Checking again in 2s...");
                thread::sleep(std::time::Duration::from_secs(2));
            }
            macos_tap::start_macos_native_hook();
        }

        #[cfg(not(target_os = "macos"))]
        {
            if let Err(err) = grab(hook_callback) {
                eprintln!("Failed to start global input grab hook: {:?}", err);
            }
        }
    });

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            // Setup System Tray Icon (Tauri v2 Tray)
            let toggle = MenuItem::with_id(app, "toggle", "Bật/Tắt Gõ Tiếng Việt", true, None::<&str>).unwrap();
            let show = MenuItem::with_id(app, "show", "Bảng điều khiển", true, None::<&str>).unwrap();
            let exit = MenuItem::with_id(app, "exit", "Thoát VNKey", true, None::<&str>).unwrap();
            
            // Store toggle menu item in lazy static for background thread access
            {
                let mut guard = TRAY_TOGGLE_ITEM.write().unwrap();
                *guard = Some(toggle.clone());
            }

            // Generate and store normal and dimmed tray icons
            let normal_icon = generate_icon_image(false); // 'V'
            let dimmed_icon = generate_icon_image(true);  // 'E'

            {
                let mut norm_guard = NORMAL_ICON.write().unwrap();
                *norm_guard = Some(normal_icon.clone());
                let mut dim_guard = DIMMED_ICON.write().unwrap();
                *dim_guard = Some(dimmed_icon);
            }

            // Spawn background thread to monitor active system IME layout (macOS specific)
            let app_handle = app.handle().clone();
            thread::spawn(move || {
                loop {
                    let app_handle_clone = app_handle.clone();
                    let _ = app_handle.run_on_main_thread(move || {
                        #[cfg(target_os = "macos")]
                        {
                            macos_tap::update_active_app_state();
                        }
                        let is_eng_ime = {
                            #[cfg(target_os = "macos")]
                            { is_english_ime() }
                            #[cfg(not(target_os = "macos"))]
                            { true }
                        };

                        let method_is_off = {
                            let s = SETTINGS.read().unwrap();
                            s.method == "Off"
                        };

                        let is_active_vietnamese = is_eng_ime && !method_is_off;

                        let old_is_eng_ime = ACTIVE_LAYOUT_IS_ENGLISH.load(std::sync::atomic::Ordering::Relaxed);
                        let old_is_active_vietnamese = ACTIVE_MODE_IS_VIETNAMESE.load(std::sync::atomic::Ordering::Relaxed);
                        let first_run = !INITIAL_RUN_DONE.swap(true, std::sync::atomic::Ordering::Relaxed);

                        if is_eng_ime != old_is_eng_ime || first_run {
                            ACTIVE_LAYOUT_IS_ENGLISH.store(is_eng_ime, std::sync::atomic::Ordering::Relaxed);

                            if let Some(ref item) = *TRAY_TOGGLE_ITEM.read().unwrap() {
                                let _ = item.set_enabled(is_eng_ime);
                                let _ = item.set_text(if is_eng_ime {
                                    "Bật/Tắt Gõ Tiếng Việt"
                                } else {
                                    "Bật/Tắt Gõ Tiếng Việt (Chỉ hoạt động khi hệ thống ở English IME)"
                                });
                            }

                            // Also auto disable/enable in-memory engine based on active layout
                            if !is_eng_ime {
                                let mut eng = ENGINE.write().unwrap();
                                eng.update_config(EngineConfig {
                                    method: InputMethod::Off,
                                    tone_style: ToneStyle::Modern,
                                    spelling_check: true,
                                });
                            } else {
                                // Restore from settings
                                let current_settings = {
                                    let s = SETTINGS.read().unwrap();
                                    s.clone()
                                };
                                let method = match current_settings.method.as_str() {
                                    "Telex" => InputMethod::Telex,
                                    "Vni" => InputMethod::Vni,
                                    _ => InputMethod::Off,
                                };
                                let tone_style = match current_settings.tone_style.as_str() {
                                    "Classic" => ToneStyle::Classic,
                                    _ => ToneStyle::Modern,
                                };
                                let mut eng = ENGINE.write().unwrap();
                                eng.update_config(EngineConfig {
                                    method,
                                    tone_style,
                                    spelling_check: current_settings.spelling_check,
                                });
                            }
                        }

                        if is_active_vietnamese != old_is_active_vietnamese || first_run {
                            ACTIVE_MODE_IS_VIETNAMESE.store(is_active_vietnamese, std::sync::atomic::Ordering::Relaxed);

                            // Set tray title, status, and icon dynamically on macOS
                            #[cfg(target_os = "macos")]
                            {
                                if let Some(tray) = app_handle_clone.tray_by_id("main_tray") {
                                    let _ = tray.set_title(None::<&str>);
                                    
                                    if is_active_vietnamese {
                                        if let Some(ref icon) = *NORMAL_ICON.read().unwrap() {
                                            let _ = tray.set_icon(Some(icon.clone()));
                                        }
                                    } else {
                                        if let Some(ref icon) = *DIMMED_ICON.read().unwrap() {
                                            let _ = tray.set_icon(Some(icon.clone()));
                                        }
                                    }
                                    let _ = tray.set_icon_as_template(true);
                                }
                            }
                        }
                    });

                    thread::sleep(std::time::Duration::from_millis(200));
                }
            });
            
            let tray_menu = Menu::with_items(app, &[&toggle, &show, &exit]).unwrap();

            let _tray = TrayIconBuilder::with_id("main_tray")
                .icon(normal_icon.clone())
                .icon_as_template(true)
                .menu(&tray_menu)
                .on_menu_event(|app, event| {
                    match event.id.as_ref() {
                        "toggle" => {
                            let mut current = {
                                let s = SETTINGS.read().unwrap();
                                s.clone()
                            };
                            current.method = if current.method == "Off" { "Telex".to_string() } else { "Off".to_string() };
                            let _ = update_settings(current, app.clone());
                        }
                        "show" => {
                            if let Some(window) = app.get_webview_window("main") {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                        "exit" => {
                            app.exit(0);
                        }
                        _ => {}
                    }
                })
                .build(app)
                .unwrap();

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_settings, 
            update_settings,
            has_accessibility,
            request_accessibility
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
