#[cfg(target_os = "windows")]
use std::cell::RefCell;
#[cfg(target_os = "windows")]
use std::mem;
#[cfg(target_os = "windows")]
use windows_sys::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
#[cfg(target_os = "windows")]
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
#[cfg(target_os = "windows")]
use windows_sys::Win32::UI::Input::KeyboardAndMouse::*;
#[cfg(target_os = "windows")]
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, DispatchMessageW, GetMessageW, SetWindowsHookExW, UnhookWindowsHookEx,
    HC_ACTION, MSG, WH_KEYBOARD_LL, WM_KEYDOWN, WM_SYSKEYDOWN,
};
#[cfg(target_os = "windows")]
use vnkey_engine::{Engine, EngineConfig, EngineResult, InputMethod};
#[cfg(target_os = "windows")]
use vnkey_engine::tone::ToneStyle;

#[cfg(target_os = "windows")]
thread_local! {
    static ENGINE: RefCell<Engine> = RefCell::new(Engine::new(EngineConfig {
        method: InputMethod::Telex,
        tone_style: ToneStyle::Modern,
        spelling_check: true,
    }));
}

#[cfg(target_os = "windows")]
static mut HOOK: HHOOK = 0;

#[cfg(target_os = "windows")]
fn send_backspaces(count: usize) {
    let mut inputs = Vec::new();
    for _ in 0..count {
        // Press Backspace
        inputs.push(INPUT {
            r#type: INPUT_KEYBOARD,
            Anonymous: INPUT_Anonymous {
                ki: KEYBDINPUT {
                    wVk: VK_BACK,
                    wScan: 0,
                    dwFlags: 0,
                    time: 0,
                    dwExtraInfo: 0,
                },
            },
        });
        // Release Backspace
        inputs.push(INPUT {
            r#type: INPUT_KEYBOARD,
            Anonymous: INPUT_Anonymous {
                ki: KEYBDINPUT {
                    wVk: VK_BACK,
                    wScan: 0,
                    dwFlags: KEYEVENTF_KEYUP,
                    time: 0,
                    dwExtraInfo: 0,
                },
            },
        });
    }
    unsafe {
        SendInput(
            inputs.len() as u32,
            inputs.as_ptr() as *const INPUT,
            mem::size_of::<INPUT>() as i32,
        );
    }
}

#[cfg(target_os = "windows")]
fn send_unicode_string(text: &str) {
    let mut inputs = Vec::new();
    for c in text.encode_utf16() {
        // Press Unicode char
        inputs.push(INPUT {
            r#type: INPUT_KEYBOARD,
            Anonymous: INPUT_Anonymous {
                ki: KEYBDINPUT {
                    wVk: 0,
                    wScan: c,
                    dwFlags: KEYEVENTF_UNICODE,
                    time: 0,
                    dwExtraInfo: 0,
                },
            },
        });
        // Release Unicode char
        inputs.push(INPUT {
            r#type: INPUT_KEYBOARD,
            Anonymous: INPUT_Anonymous {
                ki: KEYBDINPUT {
                    wVk: 0,
                    wScan: c,
                    dwFlags: KEYEVENTF_UNICODE | KEYEVENTF_KEYUP,
                    time: 0,
                    dwExtraInfo: 0,
                },
            },
        });
    }
    unsafe {
        SendInput(
            inputs.len() as u32,
            inputs.as_ptr() as *const INPUT,
            mem::size_of::<INPUT>() as i32,
        );
    }
}

#[cfg(target_os = "windows")]
unsafe extern "system" fn low_level_keyboard_proc(
    n_code: i32,
    w_param: WPARAM,
    l_param: LPARAM,
) -> LRESULT {
    if n_code == HC_ACTION as i32 {
        let kb = *(l_param as *const KBDLLHOOKSTRUCT);
        let is_key_down = w_param == WM_KEYDOWN as usize || w_param == WM_SYSKEYDOWN as usize;

        // Only handle keydown events
        if is_key_down {
            // Ignore injected events to avoid infinite loops from SendInput
            if (kb.flags & LLKHF_INJECTED) != 0 {
                return CallNextHookEx(HOOK, n_code, w_param, l_param);
            }

            // Read modifiers
            let shift = (GetKeyState(VK_SHIFT as i32) & 0x8000) != 0;
            let ctrl = (GetKeyState(VK_CONTROL as i32) & 0x8000) != 0;
            let alt = (GetKeyState(VK_MENU as i32) & 0x8000) != 0;

            if ctrl || alt {
                ENGINE.with(|e| e.borrow_mut().reset());
                return CallNextHookEx(HOOK, n_code, w_param, l_param);
            }

            // Map Virtual Key to Char
            let vk = kb.vkCode as u32;
            let char_opt = match vk {
                // a-z
                0x41..=0x5A => {
                    let base = (vk - 0x41) as u8 + b'a';
                    let c = base as char;
                    Some(if shift { c.to_ascii_uppercase() } else { c })
                }
                // 0-9
                0x30..=0x39 => {
                    if shift {
                        None
                    } else {
                        let base = (vk - 0x30) as u8 + b'0';
                        Some(base as char)
                    }
                }
                VK_SPACE => Some(' '),
                VK_BACK | VK_RETURN | VK_ESCAPE => {
                    ENGINE.with(|e| e.borrow_mut().reset());
                    None
                }
                _ => {
                    ENGINE.with(|e| e.borrow_mut().reset());
                    None
                }
            };

            if let Some(c) = char_opt {
                let result = ENGINE.with(|e| e.borrow_mut().process_key(c));
                match result {
                    EngineResult::Keep => {}
                    EngineResult::Replace { backspaces, text } => {
                        send_backspaces(backspaces);
                        send_unicode_string(&text);
                        return 1; // Swallow key event
                    }
                    EngineResult::Reset => {}
                }
            }
        }
    }
    CallNextHookEx(HOOK, n_code, w_param, l_param)
}

pub fn start_windows_hook() {
    #[cfg(target_os = "windows")]
    unsafe {
        println!("Starting Windows Hook keyboard hook...");
        let h_instance = GetModuleHandleW(std::ptr::null());
        HOOK = SetWindowsHookExW(
            WH_KEYBOARD_LL,
            Some(low_level_keyboard_proc),
            h_instance,
            0,
        );

        if HOOK == 0 {
            eprintln!("Failed to install SetWindowsHookEx");
            return;
        }

        let mut msg: MSG = mem::zeroed();
        while GetMessageW(&mut msg, 0, 0, 0) > 0 {
            // Keep message loop running
            DispatchMessageW(&msg);
        }

        UnhookWindowsHookEx(HOOK);
    }
}

// Fallback functions when not on Windows
#[cfg(not(target_os = "windows"))]
pub fn start_windows_hook() {
    panic!("Windows hook is not supported on this platform!");
}
