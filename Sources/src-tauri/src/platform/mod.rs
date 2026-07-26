#![allow(dead_code)]
pub trait KeyboardHook: Send + Sync {

    fn start(&mut self) -> Result<(), String>;
    fn stop(&mut self) -> Result<(), String>;
    fn is_running(&self) -> bool;
}

pub trait KeyInjector: Send + Sync {
    fn send_backspace(&self, count: usize);
    fn send_text(&self, text: &str);
}

pub trait ActiveAppWatcher: Send + Sync {
    fn get_active_app_bundle_id(&self) -> Option<String>;
}

#[cfg(target_os = "macos")]
pub mod macos;

#[cfg(target_os = "windows")]
pub mod windows;

#[cfg(target_os = "linux")]
pub mod linux;
