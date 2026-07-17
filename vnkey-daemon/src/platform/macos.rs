use core_foundation::run_loop::{CFRunLoop, CFRunLoopMode};
use core_graphics::event::{
    CGEvent, CGEventFlags, CGEventTap, CGEventTapLocation, CGEventTapOptions,
    CGEventTapPlacement, CGEventType, CGEventField,
};
use std::cell::RefCell;
use std::os::raw::c_void;
use vnkey_engine::{Engine, EngineConfig, EngineResult, InputMethod};
use vnkey_engine::tone::ToneStyle;
use objc2_app_kit::NSWorkspace;
use std::path::Path;

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct CFRange {
    pub location: isize,
    pub length: isize,
}

#[link(name = "ApplicationServices", kind = "framework")]
extern "C" {
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
    fn CFRelease(obj: *const c_void);
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


thread_local! {
    static ENGINE: RefCell<Engine> = RefCell::new(Engine::new(EngineConfig {
        method: InputMethod::Telex,
        tone_style: ToneStyle::Modern,
        spelling_check: true,
    }));
}

/// Convert macOS keyboard keycode to character (assuming US QWERTY layout for Telex/VNI)
fn keycode_to_char(keycode: i64, shift: bool) -> Option<char> {
    let c = match keycode {
        0 => 'a',
        1 => 's',
        2 => 'd',
        3 => 'f',
        4 => 'h',
        5 => 'g',
        6 => 'z',
        7 => 'x',
        8 => 'c',
        9 => 'v',
        11 => 'b',
        12 => 'q',
        13 => 'w',
        14 => 'e',
        15 => 'r',
        16 => 'y',
        17 => 't',
        18 => { if shift { return None; } else { '1' } },
        19 => { if shift { return None; } else { '2' } },
        20 => { if shift { return None; } else { '3' } },
        21 => { if shift { return None; } else { '4' } },
        22 => { if shift { return None; } else { '6' } },
        23 => { if shift { return None; } else { '5' } },
        24 => { if shift { return None; } else { '=' } },
        25 => { if shift { return None; } else { '9' } },
        26 => { if shift { return None; } else { '7' } },
        28 => { if shift { return None; } else { '8' } },
        29 => { if shift { return None; } else { '0' } },
        31 => 'o',
        32 => 'u',
        34 => 'i',
        35 => 'p',
        37 => 'l',
        38 => 'j',
        40 => 'k',
        41 => { if shift { return None; } else { ';' } },
        45 => 'n',
        46 => 'm',
        47 => { if shift { return None; } else { '.' } },
        _ => return None,
    };
    if shift {
        Some(c.to_ascii_uppercase())
    } else {
        Some(c)
    }
}

// Low-level Backspace and Unicode simulation functions
fn send_backspaces(count: usize) {
    let source = core_graphics::event::CGEventSource::new(core_graphics::event::CGEventSourceStateID::CombinedSessionState).unwrap();
    
    for _ in 0..count {
        // key down backspace (keycode 51)
        if let Ok(down) = CGEvent::new_keyboard_event(source.clone(), 51, true) {
            down.post(CGEventTapLocation::HIDEventTap);
        }
        // key up backspace
        if let Ok(up) = CGEvent::new_keyboard_event(source.clone(), 51, false) {
            up.post(CGEventTapLocation::HIDEventTap);
        }
    }
}

fn send_unicode_string(text: &str) {
    let source = core_graphics::event::CGEventSource::new(core_graphics::event::CGEventSourceStateID::CombinedSessionState).unwrap();
    // macOS CGEvent supports creating keyboard event with string directly
    if let Ok(event) = CGEvent::new_keyboard_event(source, 0, true) {
        event.set_string(text);
        event.post(CGEventTapLocation::HIDEventTap);
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
    let workspace = NSWorkspace::sharedWorkspace();
    let Some(app) = workspace.frontmostApplication() else {
        return false;
    };

    // 1. Check bundle identifier
    if let Some(bundle_id) = app.bundleIdentifier() {
        let bundle_id_str = bundle_id.to_string();
        if bundle_id_str == "com.apple.Spotlight" {
            return true;
        }
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
            return true;
        }
    }

    // 2. Check bundle URL for Electron framework or app.asar
    if let Some(bundle_url) = app.bundleURL() {
        if let Some(path_ns) = bundle_url.path() {
            let path_str = path_ns.to_string();
            let path = Path::new(&path_str);
            let electron_framework = path.join("Contents/Frameworks/Electron Framework.framework");
            let app_asar = path.join("Contents/Resources/app.asar");
            if electron_framework.exists() || app_asar.exists() {
                return true;
            }
        }
    }

    false
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

/// The callback function registered with CGEventTap
fn event_tap_callback(
    _proxy: CGEventTapProxy,
    event_type: CGEventType,
    event: &CGEvent,
) -> Option<CGEvent> {
    if event_type != CGEventType::KeyDown {
        return Some(event.clone());
    }

    let flags = event.get_flags();
    // If Command, Control, or Option (Alt) flags are pressed, ignore typing engine
    if flags.contains(CGEventFlags::CGEventFlagCommand)
        || flags.contains(CGEventFlags::CGEventFlagControl)
        || flags.contains(CGEventFlags::CGEventFlagAlternate)
    {
        ENGINE.with(|e| e.borrow_mut().reset());
        return Some(event.clone());
    }

    let keycode = event.get_integer_value_field(CGEventField::KeyboardEventKeycode);

    // Escape or Return or Tab or Backspace resets the engine buffer
    if keycode == 53 || keycode == 36 || keycode == 48 || keycode == 51 {
        ENGINE.with(|e| e.borrow_mut().reset());
        return Some(event.clone());
    }

    let shift = flags.contains(CGEventFlags::CGEventFlagShift);
    let c_opt = keycode_to_char(keycode, shift);

    if let Some(c) = c_opt {
        let result = ENGINE.with(|e| e.borrow_mut().process_key(c));
        match result {
            EngineResult::Keep => Some(event.clone()),
            EngineResult::Replace { backspaces, text } => {
                let mut success = false;
                if is_spotlight_or_electron_app() {
                    unsafe {
                        success = send_via_accessibility(backspaces, &text);
                    }
                }
                if !success {
                    // Delete previous characters
                    send_backspaces(backspaces);
                    // Inject new characters
                    send_unicode_string(&text);
                }
                // Swallow the original keystroke
                None
            }
            EngineResult::Reset => {
                Some(event.clone())
            }
        }
    } else {
        // Non-character key (like arrow keys, function keys, etc.) resets buffer
        ENGINE.with(|e| e.borrow_mut().reset());
        Some(event.clone())
    }
}


type CGEventTapProxy = *mut c_void;

pub fn start_macos_hook() {
    println!("Starting macOS EventTap keyboard hook...");
    
    let current_loop = CFRunLoop::get_current();
    
    // Create event tap for KeyDown events
    let tap = match CGEventTap::new(
        CGEventTapLocation::SessionEventTap,
        CGEventTapPlacement::HeadInsertEventTap,
        CGEventTapOptions::Default,
        vec![CGEventType::KeyDown],
        move |proxy, event_type, event| {
            event_tap_callback(proxy, event_type, event)
        }
    ) {
        Ok(t) => t,
        Err(_) => {
            eprintln!("Failed to create CGEventTap. Please make sure the app has Accessibility permissions.");
            return;
        }
    };

    unsafe {
        let loop_source = tap.controller.create_run_loop_source(0).unwrap();
        current_loop.add_source(&loop_source, CFRunLoopMode::default());
        tap.controller.enable();
    }
    
    CFRunLoop::run_current();
}
