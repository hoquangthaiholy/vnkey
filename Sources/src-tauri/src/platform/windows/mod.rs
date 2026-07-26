use super::{ActiveAppWatcher, KeyInjector, KeyboardHook};

pub struct WindowsKeyboardHook;

impl KeyboardHook for WindowsKeyboardHook {
    fn start(&mut self) -> Result<(), String> {
        // Ready for Windows LowLevelKeyboardProc hook (SetWindowsHookExW)
        Ok(())
    }

    fn stop(&mut self) -> Result<(), String> {
        // UnhookWindowsHookEx
        Ok(())
    }

    fn is_running(&self) -> bool {
        false
    }
}

pub struct WindowsKeyInjector;

impl KeyInjector for WindowsKeyInjector {
    fn send_backspace(&self, _count: usize) {
        // SendInput with VK_BACK
    }

    fn send_text(&self, _text: &str) {
        // SendInput with KEYEVENTF_UNICODE
    }
}

pub struct WindowsAppWatcher;

impl ActiveAppWatcher for WindowsAppWatcher {
    fn get_active_app_bundle_id(&self) -> Option<String> {
        // GetForegroundWindow & GetWindowThreadProcessId
        None
    }
}
