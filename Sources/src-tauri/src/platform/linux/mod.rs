use super::{ActiveAppWatcher, KeyInjector, KeyboardHook};

pub struct LinuxKeyboardHook;

impl KeyboardHook for LinuxKeyboardHook {
    fn start(&mut self) -> Result<(), String> {
        // Ready for Linux X11 XRecord or evdev hook
        Ok(())
    }

    fn stop(&mut self) -> Result<(), String> {
        Ok(())
    }

    fn is_running(&self) -> bool {
        false
    }
}

pub struct LinuxKeyInjector;

impl KeyInjector for LinuxKeyInjector {
    fn send_backspace(&self, _count: usize) {
        // uinput or xdotool/ydotool keycode injection
    }

    fn send_text(&self, _text: &str) {
        // uinput or xdotool/ydotool unicode text injection
    }
}

pub struct LinuxAppWatcher;

impl ActiveAppWatcher for LinuxAppWatcher {
    fn get_active_app_bundle_id(&self) -> Option<String> {
        // XGetInputFocus / Wayland active window info
        None
    }
}
