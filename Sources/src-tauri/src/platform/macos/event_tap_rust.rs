#![allow(dead_code, unused_imports)]
use std::os::raw::c_void;

use std::sync::atomic::{AtomicBool, Ordering};

pub type CGEventTapProxy = *mut c_void;
pub type CGEventRef = *mut c_void;
pub type CGEventMask = u64;
pub type CFMachPortRef = *mut c_void;
pub type CFRunLoopSourceRef = *mut c_void;

static IS_EVENT_TAP_RUNNING: AtomicBool = AtomicBool::new(false);

#[link(name = "CoreGraphics", kind = "framework")]
extern "C" {
    pub fn CGEventTapCreate(
        tap: u32,
        place: u32,
        options: u32,
        events_of_interest: CGEventMask,
        callback: extern "C" fn(
            proxy: CGEventTapProxy,
            event_type: u32,
            event: CGEventRef,
            user_info: *mut c_void,
        ) -> CGEventRef,
        user_info: *mut c_void,
    ) -> CFMachPortRef;
    pub fn CGEventTapEnable(tap: CFMachPortRef, enable: bool);
}

pub unsafe fn start_rust_event_tap() -> bool {
    IS_EVENT_TAP_RUNNING.store(true, Ordering::Relaxed);
    true
}

pub unsafe fn stop_rust_event_tap() {
    IS_EVENT_TAP_RUNNING.store(false, Ordering::Relaxed);
}

pub fn is_rust_event_tap_running() -> bool {
    IS_EVENT_TAP_RUNNING.load(Ordering::Relaxed)
}
