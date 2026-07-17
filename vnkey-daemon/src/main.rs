use rdev::{Event, EventType, Key, simulate, grab};
use std::cell::RefCell;
use std::thread;
use vnkey_engine::{Engine, EngineConfig, EngineResult, InputMethod};
use vnkey_engine::tone::ToneStyle;

thread_local! {
    static ENGINE: RefCell<Engine> = RefCell::new(Engine::new(EngineConfig {
        method: InputMethod::Telex,
        tone_style: ToneStyle::Modern,
        spelling_check: true,
    }));
    static SHIFT_PRESSED: RefCell<bool> = RefCell::new(false);
}

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

fn send_backspace() {
    let _ = simulate(&EventType::KeyPress(Key::Backspace));
    let _ = simulate(&EventType::KeyRelease(Key::Backspace));
}

fn send_unicode_char(c: char) {
    // Note: rdev doesn't support direct unicode input injection cleanly on all OSes,
    // but we can send keys or use OS-specific APIs. For a reliable mock/prototype, 
    // we can simulate the character or print it.
    // Let's implement Unicode simulation. On macOS/Windows, we can also type it.
    // Wait, rdev EventType has custom key simulation. Let's just output text 
    // or simulate keystrokes.
    // If rdev has no native Unicode inject, we can use platform-specific hacks, 
    // or just simulate keys for a-z/accents.
    // For now, let's write a helper that maps standard accent chars back to keystrokes 
    // or prints them.
    // Actually, on macOS, to type Unicode characters, we can post them.
    // Let's print for logging, and simulate simple key events.
    println!("Simulating unicode character: {}", c);
}

fn send_unicode_string(text: &str) {
    for c in text.chars() {
        send_unicode_char(c);
    }
}

fn callback(event: Event) -> Option<Event> {
    match event.event_type {
        EventType::KeyPress(key) => {
            if key == Key::ShiftLeft || key == Key::ShiftRight {
                SHIFT_PRESSED.with(|s| *s.borrow_mut() = true);
                return Some(event);
            }

            // Ignore shortcuts (Ctrl/Alt/Meta pressed)
            // Wait, we can't easily check Ctrl state in rdev without tracking KeyPress/Release for Ctrl.
            // Let's reset engine on Space, Return, Escape, Backspace, or non-alphanumeric
            if key == Key::Space || key == Key::Return || key == Key::Escape || key == Key::Backspace {
                ENGINE.with(|e| e.borrow_mut().reset());
                return Some(event);
            }

            let shift = SHIFT_PRESSED.with(|s| *s.borrow());
            if let Some(c) = key_to_char(key, shift) {
                let result = ENGINE.with(|e| e.borrow_mut().process_key(c));
                match result {
                    EngineResult::Keep => Some(event),
                    EngineResult::Replace { backspaces, text } => {
                        // In background thread to avoid deadlocks in some OS event loops
                        thread::spawn(move || {
                            for _ in 0..backspaces {
                                send_backspace();
                            }
                            send_unicode_string(&text);
                        });
                        None // Swallow the key event
                    }
                    EngineResult::Reset => Some(event),
                }
            } else {
                ENGINE.with(|e| e.borrow_mut().reset());
                Some(event)
            }
        }
        EventType::KeyRelease(key) => {
            if key == Key::ShiftLeft || key == Key::ShiftRight {
                SHIFT_PRESSED.with(|s| *s.borrow_mut() = false);
            }
            Some(event)
        }
        _ => Some(event),
    }
}

fn main() {
    println!("VNKey Daemon (rdev-powered) starting...");
    if let Err(error) = grab(callback) {
        println!("Error starting global hook: {:?}", error);
    }
}
