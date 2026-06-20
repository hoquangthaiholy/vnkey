use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};

#[derive(serde::Serialize)]
pub struct MacroEntry {
    pub shortcut: String,
    pub content: String,
}

extern "C" {
    pub static mut vLanguage: c_int;
    pub static mut vInputType: c_int;
    pub static mut vFreeMark: c_int;
    pub static mut vCodeTable: c_int;
    pub static mut vSwitchKeyStatus: c_int;
    pub static mut vCheckSpelling: c_int;
    pub static mut vUseModernOrthography: c_int;
    pub static mut vQuickTelex: c_int;
    pub static mut vRestoreIfWrongSpelling: c_int;
    pub static mut vUseEnglishDictionary: c_int;
    pub static mut vFixRecommendBrowser: c_int;
    pub static mut vUseMacro: c_int;
    pub static mut vUseMacroInEnglishMode: c_int;
    pub static mut vAutoCapsMacro: c_int;
    pub static mut vUseSmartSwitchKey: c_int;
    pub static mut vUpperCaseFirstChar: c_int;
    pub static mut vTempOffSpelling: c_int;
    pub static mut vAllowConsonantZFWJ: c_int;
    pub static mut vQuickStartConsonant: c_int;
    pub static mut vQuickEndConsonant: c_int;
    pub static mut vRememberCode: c_int;
    pub static mut vOtherLanguage: c_int;
    pub static mut vTempOffVNKey: c_int;
    pub static mut vSendKeyStepByStep: c_int;
    pub static mut vFixChromiumBrowser: c_int;
    pub static mut vPerformLayoutCompat: c_int;

    pub fn vKeyInit() -> *mut c_void;
    pub fn startNewSession();
    pub fn start_event_tap() -> bool;
    pub fn stop_event_tap();
    pub fn do_quick_convert() -> bool;
    pub fn is_accessibility_granted() -> bool;
    pub fn request_accessibility_permission();
    fn vnkey_macro_count() -> c_int;
    fn vnkey_macro_text_at(index: c_int) -> *mut c_char;
    fn vnkey_macro_content_at(index: c_int) -> *mut c_char;
    fn vnkey_add_macro(shortcut: *const c_char, content: *const c_char) -> bool;
    fn vnkey_delete_macro(shortcut: *const c_char) -> bool;
    fn vnkey_on_code_table_changed();
    fn vnkey_save_macros(path: *const c_char);
    fn vnkey_load_macros(path: *const c_char);
    fn vnkey_convert_text(
        source: *const c_char,
        from_code: c_int,
        to_code: c_int,
        all_caps: bool,
        all_non_caps: bool,
        caps_first_letter: bool,
        caps_each_word: bool,
        remove_mark: bool,
    ) -> *mut c_char;
    fn vnkey_free_string(value: *mut c_char);

    #[cfg(target_os = "macos")]
    fn get_macos_status_icon(vietnamese: bool, gray: bool, len: *mut c_int) -> *const u8;
    #[cfg(target_os = "macos")]
    fn free_macos_status_icon(bytes: *const u8);
}

pub fn init() {
    unsafe {
        vKeyInit();
    }
}

unsafe fn take_string(value: *mut c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    let result = CStr::from_ptr(value).to_string_lossy().into_owned();
    vnkey_free_string(value);
    Some(result)
}

pub fn macros() -> Vec<MacroEntry> {
    unsafe {
        let count = vnkey_macro_count().max(0);
        (0..count)
            .filter_map(|index| {
                let shortcut = take_string(vnkey_macro_text_at(index))?;
                let content = take_string(vnkey_macro_content_at(index))?;
                Some(MacroEntry { shortcut, content })
            })
            .collect()
    }
}

pub fn add_macro(shortcut: &str, content: &str) -> bool {
    let Ok(shortcut) = CString::new(shortcut) else {
        return false;
    };
    let Ok(content) = CString::new(content) else {
        return false;
    };
    unsafe { vnkey_add_macro(shortcut.as_ptr(), content.as_ptr()) }
}

pub fn delete_macro(shortcut: &str) -> bool {
    let Ok(shortcut) = CString::new(shortcut) else {
        return false;
    };
    unsafe { vnkey_delete_macro(shortcut.as_ptr()) }
}

pub fn code_table_changed() {
    unsafe { vnkey_on_code_table_changed() };
}

pub fn save_macros(path: &str) {
    if let Ok(path) = CString::new(path) {
        unsafe { vnkey_save_macros(path.as_ptr()) };
    }
}

pub fn load_macros(path: &str) {
    if let Ok(path) = CString::new(path) {
        unsafe { vnkey_load_macros(path.as_ptr()) };
    }
}

pub fn convert_text(
    source: &str,
    from_code: i32,
    to_code: i32,
    all_caps: bool,
    all_non_caps: bool,
    caps_first_letter: bool,
    caps_each_word: bool,
    remove_mark: bool,
) -> Option<String> {
    let source = CString::new(source).ok()?;
    unsafe {
        take_string(vnkey_convert_text(
            source.as_ptr(),
            from_code,
            to_code,
            all_caps,
            all_non_caps,
            caps_first_letter,
            caps_each_word,
            remove_mark,
        ))
    }
}

#[cfg(target_os = "macos")]
pub fn macos_status_icon(vietnamese: bool, gray: bool) -> Option<Vec<u8>> {
    unsafe {
        let mut len: c_int = 0;
        let ptr = get_macos_status_icon(vietnamese, gray, &mut len);
        if ptr.is_null() || len <= 0 {
            return None;
        }
        let slice = std::slice::from_raw_parts(ptr, len as usize);
        let vec = slice.to_vec();
        free_macos_status_icon(ptr);
        Some(vec)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    static TEST_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn conversion_preserves_case_by_default() {
        let _guard = TEST_LOCK.lock().unwrap();
        init();
        let converted = convert_text("VNKey Tiếng Việt", 0, 0, false, false, false, false, false);
        assert_eq!(converted.as_deref(), Some("VNKey Tiếng Việt"));
    }

    #[test]
    fn macro_can_be_added_listed_and_removed() {
        let _guard = TEST_LOCK.lock().unwrap();
        init();
        let shortcut = "__vnkey_test_macro__";
        assert!(add_macro(shortcut, "Nội dung thử"));
        assert!(macros().iter().any(|entry| entry.shortcut == shortcut));
        assert!(delete_macro(shortcut));
    }
}
