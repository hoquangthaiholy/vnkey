#[cfg(target_os = "macos")]
pub mod macos;

#[cfg(target_os = "windows")]
pub mod windows;

pub fn start_hook() {
    #[cfg(target_os = "macos")]
    macos::start_macos_hook();

    #[cfg(target_os = "windows")]
    windows::start_windows_hook();

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        println!("Global hooks are currently not supported on this platform. Linux implementation will be integrated with IBus/Fcitx.");
    }
}
