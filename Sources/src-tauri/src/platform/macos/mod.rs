#![allow(dead_code, unused_imports)]
pub mod event_tap_rust;

use super::{ActiveAppWatcher, KeyInjector, KeyboardHook};


pub struct MacOSKeyboardHook;

impl KeyboardHook for MacOSKeyboardHook {
    fn start(&mut self) -> Result<(), String> {
        unsafe {
            if crate::legacy_engine::start_event_tap() {
                Ok(())
            } else {
                Err("Failed to start macOS event tap".into())
            }
        }
    }

    fn stop(&mut self) -> Result<(), String> {
        unsafe {
            crate::legacy_engine::stop_event_tap();
        }
        Ok(())
    }

    fn is_running(&self) -> bool {
        true
    }
}



pub struct MacOSKeyInjector;

impl KeyInjector for MacOSKeyInjector {
    fn send_backspace(&self, _count: usize) {
        // macOS handles backspaces natively within event tap via CGEvent
    }

    fn send_text(&self, _text: &str) {
        // macOS handles text injection natively within event tap
    }
}

pub struct MacOSAppWatcher;

impl ActiveAppWatcher for MacOSAppWatcher {
    fn get_active_app_bundle_id(&self) -> Option<String> {
        // Interops with native macOS Cocoa APIs
        None
    }
}
