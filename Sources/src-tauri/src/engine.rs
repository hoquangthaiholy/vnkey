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

    pub static mut vCodeTable: c_int;
    pub static mut vSwitchKeyStatus: c_int;
    pub static mut vCheckSpelling: c_int;
    pub static mut vUseModernOrthography: c_int;
    pub static mut vQuickTelex: c_int;
    pub static mut vUseEnglishDictionary: c_int;
    pub static mut vFixRecommendBrowser: c_int;
    pub static mut vFixSpotlight: c_int;
    pub static mut vUseMacro: c_int;
    pub static mut vUseMacroInEnglishMode: c_int;
    pub static mut vAutoCapsMacro: c_int;
    pub static mut vUseSmartSwitchKey: c_int;
    pub static mut vUpperCaseFirstChar: c_int;

    pub static mut vQuickStartConsonant: c_int;
    pub static mut vQuickEndConsonant: c_int;
    pub static mut vRememberCode: c_int;
    pub static mut vDisableHotkeys: c_int;
    pub static mut vSendKeyStepByStep: c_int;
    pub static mut vFixChromiumBrowser: c_int;
    pub static mut vPerformLayoutCompat: c_int;
    pub static mut vCheckProgrammingKeywords: c_int;
    pub static mut vLateAccentTransformation: c_int;
    pub static mut vAllCapsAutoEscape: c_int;
    pub static mut vUsePasteWorkaround: c_int;
    pub static mut vTelexWAsU: c_int;
    pub static mut vTelexBracketAsO: c_int;

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

    fn vnkey_load_macros(path: *const c_char);
    fn vnkey_set_custom_english_words(content: *const c_char);
    fn vnkey_set_custom_vietnamese_words(content: *const c_char);
    fn vnkey_set_custom_programming_keywords(content: *const c_char);
    fn vnkey_set_fsm_priority_order(a: c_int, b: c_int, c: c_int);
    fn vnkey_get_fsm_priority_order(a: *mut c_int, b: *mut c_int, c: *mut c_int);
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

    pub fn get_convert_tool_dont_alert() -> c_int;
    pub fn set_convert_tool_dont_alert(val: c_int);
    pub fn get_convert_tool_to_all_caps() -> c_int;
    pub fn set_convert_tool_to_all_caps(val: c_int);
    pub fn get_convert_tool_to_all_non_caps() -> c_int;
    pub fn set_convert_tool_to_all_non_caps(val: c_int);
    pub fn get_convert_tool_to_caps_first_letter() -> c_int;
    pub fn set_convert_tool_to_caps_first_letter(val: c_int);
    pub fn get_convert_tool_to_caps_each_word() -> c_int;
    pub fn set_convert_tool_to_caps_each_word(val: c_int);
    pub fn get_convert_tool_remove_mark() -> c_int;
    pub fn set_convert_tool_remove_mark(val: c_int);
    pub fn get_convert_tool_from_code() -> c_int;
    pub fn set_convert_tool_from_code(val: c_int);
    pub fn get_convert_tool_to_code() -> c_int;
    pub fn set_convert_tool_to_code(val: c_int);
    pub fn get_convert_tool_hotkey() -> c_int;
    pub fn set_convert_tool_hotkey(val: c_int);

    #[cfg(target_os = "macos")]
    fn get_macos_status_icon(vietnamese: bool, gray: bool, input_type: c_int, len: *mut c_int) -> *const u8;
    #[cfg(target_os = "macos")]
    fn free_macos_status_icon(bytes: *const u8);

    #[cfg(target_os = "macos")]
    pub fn macos_clipboard_get_change_count() -> i64;
    #[cfg(target_os = "macos")]
    pub fn macos_clipboard_is_sensitive() -> bool;
    #[cfg(target_os = "macos")]
    pub fn macos_clipboard_read_text() -> *mut c_char;
    #[cfg(target_os = "macos")]
    pub fn macos_clipboard_read_html() -> *mut c_char;
    #[cfg(target_os = "macos")]
    pub fn macos_clipboard_read_file_urls() -> *mut c_char;
    #[cfg(target_os = "macos")]
    pub fn macos_clipboard_get_image_png(len: *mut c_int) -> *const u8;
    #[cfg(target_os = "macos")]
    pub fn macos_clipboard_paste(
        prev_pid: c_int,
        text: *const c_char,
        html: *const c_char,
        image_file_path: *const c_char,
        file_paths_joined: *const c_char,
    );
    #[cfg(target_os = "macos")]
    #[allow(dead_code)]
    pub fn macos_configure_clipboard_window(ns_window_ptr: *mut c_void, pin_on_top: bool);
    #[cfg(target_os = "macos")]
    pub fn macos_configure_hud_window(ns_window_ptr: *mut c_void);
    #[cfg(target_os = "macos")]
    pub fn macos_get_frontmost_app_pid() -> c_int;
    #[cfg(target_os = "macos")]
    pub fn macos_get_mouse_position(x: *mut f64, y: *mut f64);
    #[cfg(target_os = "macos")]
    pub fn macos_set_clipboard_hotkey(val: c_int);
    pub fn macos_set_panel_hotkey(val: c_int);
    pub fn macos_set_clipboard_enabled(enabled: bool);

    #[cfg(target_os = "macos")]
    pub fn macos_get_frontmost_app_bundle_id() -> *mut c_char;
    #[cfg(target_os = "macos")]
    pub fn macos_get_frontmost_app_name() -> *mut c_char;
    #[cfg(target_os = "macos")]
    pub fn macos_get_running_applications_json() -> *mut c_char;
    #[cfg(target_os = "macos")]
    pub fn macos_get_application_info_by_path_json(path_cstr: *const c_char) -> *mut c_char;
    #[cfg(target_os = "macos")]
    pub fn macos_get_application_info_by_bundle_id_json(bundle_id_cstr: *const c_char) -> *mut c_char;
    pub fn macos_get_application_info_by_name_json(name_cstr: *const c_char) -> *mut c_char;
    #[cfg(target_os = "macos")]
    pub fn macos_is_another_instance_running() -> bool;
    pub fn macos_activate_other_instance();
    pub fn macos_is_current_input_source_english() -> bool;
    #[cfg(target_os = "macos")]
    pub fn get_caret_position(x: *mut f64, y: *mut f64, success: *mut bool);
}

#[cfg(target_os = "macos")]
pub fn is_another_instance_running() -> bool {
    unsafe { macos_is_another_instance_running() }
}

#[cfg(target_os = "macos")]
pub fn activate_other_instance() {
    unsafe { macos_activate_other_instance(); }
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

pub fn load_macros(path: &str) {
    if let Ok(path) = CString::new(path) {
        unsafe { vnkey_load_macros(path.as_ptr()) };
    }
}

#[allow(clippy::too_many_arguments)]
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

pub fn set_custom_english_words(content: &str) {
    if let Ok(c_content) = CString::new(content) {
        unsafe { vnkey_set_custom_english_words(c_content.as_ptr()) };
    }
}

pub fn set_custom_vietnamese_words(content: &str) {
    if let Ok(c_content) = CString::new(content) {
        unsafe { vnkey_set_custom_vietnamese_words(c_content.as_ptr()) };
    }
}

pub fn set_custom_programming_keywords(content: &str) {
    if let Ok(c_content) = CString::new(content) {
        unsafe { vnkey_set_custom_programming_keywords(c_content.as_ptr()) };
    }
}

pub fn set_fsm_priority_order(order: &[i32; 3]) {
    unsafe {
        vnkey_set_fsm_priority_order(order[0], order[1], order[2]);
    }
}

pub fn get_fsm_priority_order(order: &mut [i32; 3]) {
    unsafe {
        vnkey_get_fsm_priority_order(&mut order[0], &mut order[1], &mut order[2]);
    }
}


#[cfg(target_os = "macos")]
pub fn macos_status_icon(vietnamese: bool, gray: bool, input_type: i32) -> Option<Vec<u8>> {
    unsafe {
        let mut len: c_int = 0;
        let ptr = get_macos_status_icon(vietnamese, gray, input_type, &mut len);
        if ptr.is_null() || len <= 0 {
            return None;
        }
        let slice = std::slice::from_raw_parts(ptr, len as usize);
        let vec = slice.to_vec();
        free_macos_status_icon(ptr);
        Some(vec)
    }
}

#[cfg(target_os = "macos")]
pub fn clipboard_get_change_count() -> i64 {
    unsafe { macos_clipboard_get_change_count() }
}

#[cfg(target_os = "macos")]
pub fn clipboard_is_sensitive() -> bool {
    unsafe { macos_clipboard_is_sensitive() }
}

#[cfg(target_os = "macos")]
pub fn clipboard_read_text() -> Option<String> {
    unsafe { take_string(macos_clipboard_read_text()) }
}

#[cfg(target_os = "macos")]
pub fn clipboard_read_html() -> Option<String> {
    unsafe { take_string(macos_clipboard_read_html()) }
}

#[cfg(target_os = "macos")]
pub fn clipboard_read_file_urls() -> Option<String> {
    unsafe { take_string(macos_clipboard_read_file_urls()) }
}

#[cfg(target_os = "macos")]
pub fn clipboard_get_image_png() -> Option<Vec<u8>> {
    unsafe {
        let mut len: c_int = 0;
        let ptr = macos_clipboard_get_image_png(&mut len);
        if ptr.is_null() || len <= 0 {
            return None;
        }
        let slice = std::slice::from_raw_parts(ptr, len as usize);
        let vec = slice.to_vec();
        free_macos_status_icon(ptr);
        Some(vec)
    }
}

#[cfg(target_os = "macos")]
pub fn clipboard_paste_item(
    prev_pid: i32,
    text: Option<&str>,
    html: Option<&str>,
    image_file_path: Option<&str>,
    file_paths_joined: Option<&str>,
) {
    let text_c = text.and_then(|s| CString::new(s).ok());
    let html_c = html.and_then(|s| CString::new(s).ok());
    let img_c = image_file_path.and_then(|s| CString::new(s).ok());
    let files_c = file_paths_joined.and_then(|s| CString::new(s).ok());

    unsafe {
        macos_clipboard_paste(
            prev_pid,
            text_c.as_ref().map_or(std::ptr::null(), |c| c.as_ptr()),
            html_c.as_ref().map_or(std::ptr::null(), |c| c.as_ptr()),
            img_c.as_ref().map_or(std::ptr::null(), |c| c.as_ptr()),
            files_c.as_ref().map_or(std::ptr::null(), |c| c.as_ptr()),
        );
    }
}

#[cfg(target_os = "macos")]
#[allow(dead_code)]
pub fn configure_clipboard_window(ns_window_ptr: *mut std::ffi::c_void, pin_on_top: bool) {
    unsafe {
        macos_configure_clipboard_window(ns_window_ptr, pin_on_top);
    }
}

#[cfg(target_os = "macos")]
pub fn get_frontmost_app_pid() -> i32 {
    unsafe { macos_get_frontmost_app_pid() }
}

#[cfg(target_os = "macos")]
pub fn macos_set_clipboard_hotkey_val(val: i32) {
    unsafe { macos_set_clipboard_hotkey(val) }
}

#[cfg(target_os = "macos")]
pub fn macos_set_panel_hotkey_val(val: i32) {
    unsafe { macos_set_panel_hotkey(val) }
}

#[cfg(target_os = "macos")]
pub fn macos_set_clipboard_enabled_val(enabled: bool) {
    unsafe { macos_set_clipboard_enabled(enabled) }
}

#[cfg(target_os = "macos")]
pub fn get_frontmost_app_bundle_id() -> Option<String> {
    unsafe { take_string(macos_get_frontmost_app_bundle_id()) }
}

#[cfg(target_os = "macos")]
pub fn get_frontmost_app_name() -> Option<String> {
    unsafe { take_string(macos_get_frontmost_app_name()) }
}

#[cfg(target_os = "macos")]
pub fn get_running_applications_json() -> Option<String> {
    unsafe { take_string(macos_get_running_applications_json()) }
}

#[cfg(target_os = "macos")]
pub fn get_application_info_by_path_json(path: &str) -> Option<String> {
    let path_c = CString::new(path).ok()?;
    unsafe { take_string(macos_get_application_info_by_path_json(path_c.as_ptr())) }
}

#[cfg(target_os = "macos")]
pub fn get_application_info_by_bundle_id_json(bundle_id: &str) -> Option<String> {
    let id_c = std::ffi::CString::new(bundle_id).ok()?;
    unsafe { take_string(macos_get_application_info_by_bundle_id_json(id_c.as_ptr())) }
}

pub fn get_application_info_by_name_json(name: &str) -> Option<String> {
    let name_c = std::ffi::CString::new(name).ok()?;
    unsafe { take_string(macos_get_application_info_by_name_json(name_c.as_ptr())) }
}

pub fn get_mouse_position() -> (f64, f64) {
    #[cfg(target_os = "macos")]
    {
        let mut x = 0.0;
        let mut y = 0.0;
        unsafe {
            macos_get_mouse_position(&mut x, &mut y);
        }
        (x, y)
    }
    #[cfg(not(target_os = "macos"))]
    (0.0, 0.0)
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
