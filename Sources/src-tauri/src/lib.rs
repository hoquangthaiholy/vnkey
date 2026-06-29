mod engine;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

mod db;
mod cloud_sync;
mod google_sync;

use std::fs::{create_dir_all, File};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::OnceLock;
use tauri::menu::{
    CheckMenuItemBuilder, Menu, MenuItemBuilder, PredefinedMenuItem, SubmenuBuilder,
};
use tauri::tray::{TrayIcon, TrayIconBuilder};
use tauri::{Emitter, Manager};
use std::sync::Mutex;
static APP_HANDLE: OnceLock<tauri::AppHandle> = OnceLock::new();

pub fn get_app_handle() -> Option<tauri::AppHandle> {
    APP_HANDLE.get().cloned()
}
static TRAY_ICON: OnceLock<TrayIcon<tauri::Wry>> = OnceLock::new();
static GRAY_ICON: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
static SHOW_INPUT_TYPE_ON_TRAY: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
static AUTOSTART: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
static OPEN_PANEL_ON_START: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);

static CLIPBOARD_ENABLED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static CLIPBOARD_PIN_ON_TOP: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(true);
static CLIPBOARD_AUTO_HIDE: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(true);
static CLIPBOARD_MAX_ITEMS: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(10);
static CLIPBOARD_HOTKEY: std::sync::atomic::AtomicI32 =
    std::sync::atomic::AtomicI32::new(0x56000C09); // Default: Command + Shift + V
static PANEL_HOTKEY: std::sync::atomic::AtomicI32 =
    std::sync::atomic::AtomicI32::new(0x50000C23); // Default: Command + Shift + P
static LAST_CHANGE_COUNT: std::sync::atomic::AtomicI64 = std::sync::atomic::AtomicI64::new(0);
pub static IS_INTERNAL_COPY: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
pub static USE_HUD: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);

#[allow(dead_code)]
extern "C" {
    fn macos_get_mouse_position(x: *mut f64, y: *mut f64);
}

fn default_switch_key() -> i32 {
    #[cfg(target_os = "macos")]
    {
        0x20000C31 // cmd + shift + space
    }
    #[cfg(not(target_os = "macos"))]
    {
        0x20000920 // ctrl + shift + space
    }
}

fn default_settings() -> Settings {
    Settings {
        language: 1,
        input_type: 0,

        code_table: 0,
        switch_key_status: default_switch_key(),
        check_spelling: 1,
        use_modern_orthography: 0,
        quick_telex: 0,
        use_english_dictionary: 1,
        fix_recommend_browser: 1,
        fix_spotlight: 1,
        use_macro: 1,
        use_macro_in_english_mode: 0,
        auto_caps_macro: 1,
        use_smart_switch_key: 1,
        upper_case_first_char: 1,
        allow_consonant_zfwj: 1,
        quick_start_consonant: 0,
        quick_end_consonant: 0,
        remember_code: 1,
        send_key_step_by_step: 0,
        fix_chromium_browser: 0,
        perform_layout_compat: 0,
        gray_icon: 1,
        show_input_type_on_tray: 1,
        convert_tool_dont_alert: 0,
        convert_tool_to_all_caps: 0,
        convert_tool_to_all_non_caps: 0,
        convert_tool_to_caps_first_letter: 0,
        convert_tool_to_caps_each_word: 0,
        convert_tool_remove_mark: 0,
        convert_tool_from_code: 0,
        convert_tool_to_code: 0,
        convert_tool_hotkey: 0xFE0000FEu32 as i32,
        clipboard_enabled: 0,
        clipboard_pin_on_top: 1,
        clipboard_auto_hide: 1,
        clipboard_max_items: 10,
        clipboard_hotkey: 0x56000C09,
        check_programming_keywords: 1,
        fsm_priority_order: vec![2, 0, 1],
        telex_w_as_u: 0,
        telex_bracket_as_o: 0,
        autostart: 1,
        open_panel_on_start: 1,
        panel_hotkey: 0x50000C23,
        late_accent_transformation: 0,
        all_caps_auto_escape: 1,
        use_paste_workaround: 1,
        use_hud: 1,
        smart_punct_check: 1,
        use_perceptron_context: 1,
    }
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct Settings {
    pub language: i32,
    pub input_type: i32,

    pub code_table: i32,
    pub switch_key_status: i32,
    pub check_spelling: i32,
    pub use_modern_orthography: i32,
    pub quick_telex: i32,
    pub use_english_dictionary: i32,
    pub check_programming_keywords: i32,
    pub fix_recommend_browser: i32,
    pub fix_spotlight: i32,
    pub use_macro: i32,
    pub use_macro_in_english_mode: i32,
    pub auto_caps_macro: i32,
    pub use_smart_switch_key: i32,
    pub upper_case_first_char: i32,
    pub allow_consonant_zfwj: i32,
    pub quick_start_consonant: i32,
    pub quick_end_consonant: i32,
    pub remember_code: i32,
    pub send_key_step_by_step: i32,
    pub fix_chromium_browser: i32,
    pub perform_layout_compat: i32,
    pub gray_icon: i32,
    pub show_input_type_on_tray: i32,
    pub convert_tool_dont_alert: i32,
    pub convert_tool_to_all_caps: i32,
    pub convert_tool_to_all_non_caps: i32,
    pub convert_tool_to_caps_first_letter: i32,
    pub convert_tool_to_caps_each_word: i32,
    pub convert_tool_remove_mark: i32,
    pub convert_tool_from_code: i32,
    pub convert_tool_to_code: i32,
    pub convert_tool_hotkey: i32,
    pub clipboard_enabled: i32,
    pub clipboard_pin_on_top: i32,
    pub clipboard_auto_hide: i32,
    pub clipboard_max_items: i32,
    pub clipboard_hotkey: i32,
    #[serde(default = "default_fsm_priority_order")]
    pub fsm_priority_order: Vec<i32>,
    #[serde(default = "default_zero")]
    pub telex_w_as_u: i32,
    #[serde(default = "default_zero")]
    pub telex_bracket_as_o: i32,
    #[serde(default = "default_zero")]
    pub autostart: i32,
    #[serde(default = "default_one")]
    pub open_panel_on_start: i32,
    #[serde(default = "default_zero")]
    pub late_accent_transformation: i32,
    #[serde(default = "default_panel_hotkey")]
    pub panel_hotkey: i32,
    #[serde(default = "default_one")]
    pub all_caps_auto_escape: i32,
    #[serde(default = "default_one")]
    pub use_paste_workaround: i32,
    #[serde(default = "default_one")]
    pub use_hud: i32,
    #[serde(default = "default_one")]
    pub smart_punct_check: i32,
    #[serde(default = "default_one")]
    pub use_perceptron_context: i32,
}

fn default_one() -> i32 { 1 }
fn default_zero() -> i32 { 0 }
fn default_panel_hotkey() -> i32 { 0x50000C23 }

fn default_fsm_priority_order() -> Vec<i32> {
    vec![2, 0, 1]
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct ClipboardItem {
    pub id: String,
    pub timestamp: i64,
    pub content_type: String, // "text" | "html" | "image" | "file"
    pub text: Option<String>,
    pub html: Option<String>,
    pub image_path: Option<String>,
    pub file_paths: Option<Vec<String>>,
    pub app_name: Option<String>,
    pub app_pid: Option<i32>,
}

#[derive(serde::Serialize)]
struct EnglishDictionary {
    custom_words: Vec<String>,
}

#[derive(serde::Serialize)]
struct ProgrammingKeywordDictionary {
    custom_keywords: Vec<String>,
}

static CLIPBOARD_HISTORY: OnceLock<Mutex<Vec<ClipboardItem>>> = OnceLock::new();

fn get_clipboard_path(handle: &tauri::AppHandle) -> Option<PathBuf> {
    if let Ok(mut path) = handle.path().app_config_dir() {
        let _ = create_dir_all(&path);
        path.push("clipboard.json");
        Some(path)
    } else {
        None
    }
}

fn get_clipboard_images_dir(handle: &tauri::AppHandle) -> Option<PathBuf> {
    if let Ok(mut path) = handle.path().app_config_dir() {
        path.push("clipboard_images");
        let _ = create_dir_all(&path);
        Some(path)
    } else {
        None
    }
}

fn load_clipboard_from_disk(handle: &tauri::AppHandle) {
    if let Some(path) = get_clipboard_path(handle) {
        if path.exists() {
            if let Ok(content) = std::fs::read_to_string(&path) {
                if let Ok(items) = serde_json::from_str::<Vec<ClipboardItem>>(&content) {
                    db::db_insert_clipboard_items(&items);
                    let _ = std::fs::remove_file(&path); // delete legacy file
                }
            }
        }
    }
    
    let items = db::db_get_clipboard_items();
    let _ = CLIPBOARD_HISTORY.set(Mutex::new(items));
}

fn save_clipboard_to_disk_internal(_handle: &tauri::AppHandle, items: &[ClipboardItem]) {
    db::db_clear_clipboard();
    db::db_insert_clipboard_items(items);
    auto_sync_to_cloud();
}

fn process_new_clipboard_item(handle: &tauri::AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(target_os = "macos")]
    {
        // 1. Read app info
        let app_name = engine::get_frontmost_app_name(); // Keep this as name for clipboard items
        let app_pid = engine::get_frontmost_app_pid();

        // 2. Read content type and data
        let mut content_type = String::new();
        let mut text = None;
        let mut html = None;
        let mut file_paths = None;
        let mut png_bytes = None;

        if let Some(files_joined) = engine::clipboard_read_file_urls() {
            if !files_joined.trim().is_empty() {
                let paths: Vec<String> = files_joined.split('\n').map(|s| s.to_string()).collect();
                if !paths.is_empty() {
                    content_type = "file".to_string();
                    file_paths = Some(paths);
                    // Try to get thumbnail icon
                    png_bytes = engine::clipboard_get_image_png();
                }
            }
        }

        if content_type.is_empty() {
            if let Some(img_data) = engine::clipboard_get_image_png() {
                if !img_data.is_empty() {
                    content_type = "image".to_string();
                    png_bytes = Some(img_data);
                }
            }
        }

        if content_type.is_empty() {
            if let Some(txt) = engine::clipboard_read_text() {
                if !txt.is_empty() {
                    content_type = "text".to_string();
                    text = Some(txt);
                    html = engine::clipboard_read_html();
                }
            }
        }

        if content_type.is_empty() {
            return Ok(()); // Nothing to save
        }

        // 3. Save png bytes if present
        let mut image_path = None;
        let item_uuid = uuid::Uuid::new_v4().to_string();
        if let Some(ref bytes) = png_bytes {
            if let Some(mut img_dir) = get_clipboard_images_dir(handle) {
                let file_name = format!("{}.png", item_uuid);
                img_dir.push(&file_name);
                if let Ok(mut f) = File::create(&img_dir) {
                    if f.write_all(bytes).is_ok() {
                        image_path = Some(img_dir.to_string_lossy().into_owned());
                    }
                }
            }
        }

        // 4. Create item
        let timestamp = chrono::Local::now().timestamp_millis();
        let new_item = ClipboardItem {
            id: item_uuid,
            timestamp,
            content_type,
            text,
            html,
            image_path,
            file_paths,
            app_name,
            app_pid: Some(app_pid),
        };

        // 5. Update history (deduplicate & trim)
        if let Some(history_mutex) = CLIPBOARD_HISTORY.get() {
            let mut history = history_mutex.lock().unwrap();

            // Find if duplicate exists
            let mut duplicate_index = None;
            for (idx, item) in history.iter().enumerate() {
                if item.content_type == new_item.content_type {
                    match new_item.content_type.as_str() {
                        "text" => {
                            if item.text == new_item.text {
                                duplicate_index = Some(idx);
                                break;
                            }
                        }
                        "file" => {
                            if item.file_paths == new_item.file_paths {
                                duplicate_index = Some(idx);
                                break;
                            }
                        }
                        "image" => {
                            if let (Some(ref new_p), Some(ref old_p)) =
                                (&new_item.image_path, &item.image_path)
                            {
                                if let (Ok(new_data), Ok(old_data)) =
                                    (std::fs::read(new_p), std::fs::read(old_p))
                                {
                                    if new_data == old_data {
                                        duplicate_index = Some(idx);
                                        break;
                                    }
                                }
                            }
                        }
                        _ => {}
                    }
                }
            }

            let mut final_item = new_item;
            if let Some(idx) = duplicate_index {
                let old_item = history.remove(idx);
                if final_item.content_type == "image" || final_item.content_type == "file" {
                    if let (Some(new_img), Some(old_img)) =
                        (&final_item.image_path, &old_item.image_path)
                    {
                        let _ = std::fs::remove_file(new_img);
                        final_item.image_path = Some(old_img.clone());
                    }
                }
            }

            history.insert(0, final_item);

            let max_items = CLIPBOARD_MAX_ITEMS.load(std::sync::atomic::Ordering::Relaxed) as usize;
            while history.len() > max_items {
                if let Some(removed_item) = history.pop() {
                    if let Some(ref path) = removed_item.image_path {
                        let _ = std::fs::remove_file(path);
                    }
                }
            }

            save_clipboard_to_disk_internal(handle, &history);
            let _ = handle.emit("clipboard-changed", ());
        }
    }
    Ok(())
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConvertRequest {
    source: String,
    from_code: i32,
    to_code: i32,
    all_caps: bool,
    all_non_caps: bool,
    caps_first_letter: bool,
    caps_each_word: bool,
    remove_mark: bool,
}

fn update_autostart_config(enabled: bool) {
    if let Ok(home) = std::env::var("HOME") {
        let mut path = PathBuf::from(home);
        path.push("Library");
        path.push("LaunchAgents");
        path.push("com.hoquangthaiholy.vnkey.plist");

        if enabled {
            if let Ok(exe_path) = std::env::current_exe() {
                let exe_str = exe_path.to_string_lossy();
                let plist_content = format!(
                    r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hoquangthaiholy.vnkey</string>
    <key>ProgramArguments</key>
    <array>
        <string>{}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>"#,
                    exe_str
                );
                
                if let Some(parent) = path.parent() {
                    let _ = std::fs::create_dir_all(parent);
                }

                if let Ok(mut file) = File::create(&path) {
                    let _ = file.write_all(plist_content.as_bytes());
                }
            }
        } else {
            if path.exists() {
                let _ = std::fs::remove_file(path);
            }
        }
    }
}

#[tauri::command]
fn get_settings() -> Settings {
    unsafe {
        let mut switch_key = engine::vSwitchKeyStatus;
        if switch_key == 0 {
            switch_key = default_switch_key();
            engine::vSwitchKeyStatus = switch_key;
        }
        let mut convert_hotkey = engine::get_convert_tool_hotkey();
        if convert_hotkey == 0 {
            convert_hotkey = 0xFE0000FEu32 as i32; // EMPTY_HOTKEY
            engine::set_convert_tool_hotkey(convert_hotkey);
        }
        let mut fsm_order = [0, 1, 2];
        engine::get_fsm_priority_order(&mut fsm_order);

        Settings {
            language: engine::vLanguage,
            input_type: engine::vInputType,

            code_table: engine::vCodeTable,
            switch_key_status: switch_key,
            check_spelling: engine::vCheckSpelling,
            use_modern_orthography: engine::vUseModernOrthography,
            quick_telex: engine::vQuickTelex,
            use_english_dictionary: engine::vUseEnglishDictionary,
            check_programming_keywords: engine::vCheckProgrammingKeywords,
            fix_recommend_browser: engine::vFixRecommendBrowser,
            fix_spotlight: engine::vFixSpotlight,
            use_macro: engine::vUseMacro,
            use_macro_in_english_mode: engine::vUseMacroInEnglishMode,
            auto_caps_macro: engine::vAutoCapsMacro,
            use_smart_switch_key: engine::vUseSmartSwitchKey,
            upper_case_first_char: engine::vUpperCaseFirstChar,
            allow_consonant_zfwj: 1,
            quick_start_consonant: engine::vQuickStartConsonant,
            quick_end_consonant: engine::vQuickEndConsonant,
            remember_code: engine::vRememberCode,
            send_key_step_by_step: engine::vSendKeyStepByStep,
            fix_chromium_browser: engine::vFixChromiumBrowser,
            perform_layout_compat: engine::vPerformLayoutCompat,
            gray_icon: if GRAY_ICON.load(std::sync::atomic::Ordering::Relaxed) {
                1
            } else {
                0
            },
            show_input_type_on_tray: if SHOW_INPUT_TYPE_ON_TRAY.load(std::sync::atomic::Ordering::Relaxed) {
                1
            } else {
                0
            },
            convert_tool_dont_alert: engine::get_convert_tool_dont_alert(),
            convert_tool_to_all_caps: engine::get_convert_tool_to_all_caps(),
            convert_tool_to_all_non_caps: engine::get_convert_tool_to_all_non_caps(),
            convert_tool_to_caps_first_letter: engine::get_convert_tool_to_caps_first_letter(),
            convert_tool_to_caps_each_word: engine::get_convert_tool_to_caps_each_word(),
            convert_tool_remove_mark: engine::get_convert_tool_remove_mark(),
            convert_tool_from_code: engine::get_convert_tool_from_code(),
            convert_tool_to_code: engine::get_convert_tool_to_code(),
            convert_tool_hotkey: convert_hotkey,
            clipboard_enabled: if CLIPBOARD_ENABLED.load(std::sync::atomic::Ordering::Relaxed) {
                1
            } else {
                0
            },
            clipboard_pin_on_top: if CLIPBOARD_PIN_ON_TOP.load(std::sync::atomic::Ordering::Relaxed)
            {
                1
            } else {
                0
            },
            clipboard_auto_hide: if CLIPBOARD_AUTO_HIDE.load(std::sync::atomic::Ordering::Relaxed) {
                1
            } else {
                0
            },
            clipboard_max_items: CLIPBOARD_MAX_ITEMS.load(std::sync::atomic::Ordering::Relaxed),
            clipboard_hotkey: CLIPBOARD_HOTKEY.load(std::sync::atomic::Ordering::Relaxed),
            fsm_priority_order: fsm_order.to_vec(),
            telex_w_as_u: engine::vTelexWAsU,
            telex_bracket_as_o: engine::vTelexBracketAsO,
            autostart: if AUTOSTART.load(std::sync::atomic::Ordering::Relaxed) {
                1
            } else {
                0
            },
            open_panel_on_start: if OPEN_PANEL_ON_START.load(std::sync::atomic::Ordering::Relaxed) {
                1
            } else {
                0
            },
            late_accent_transformation: engine::vLateAccentTransformation,
            panel_hotkey: PANEL_HOTKEY.load(std::sync::atomic::Ordering::Relaxed),
            all_caps_auto_escape: engine::vAllCapsAutoEscape,
            use_paste_workaround: engine::vUsePasteWorkaround,
            use_hud: if USE_HUD.load(std::sync::atomic::Ordering::Relaxed) { 1 } else { 0 },
            smart_punct_check: engine::vSmartPunctCheck,
            use_perceptron_context: engine::vUsePerceptronContext,
        }
    }
}

pub fn get_settings_path(handle: &tauri::AppHandle) -> Option<PathBuf> {
    if let Ok(mut path) = handle.path().app_config_dir() {
        let _ = create_dir_all(&path);
        path.push("settings.json");
        Some(path)
    } else {
        None
    }
}

fn load_settings_from_disk(handle: &tauri::AppHandle) {
    if let Some(path) = get_settings_path(handle) {
        if !path.exists() {
            // If settings.json doesn't exist, save the default settings so that they can be loaded properly.
            let default_settings = default_settings();
            save_settings_to_disk(handle, &default_settings);
        }
        if let Ok(mut file) = File::open(path) {
            let mut content = String::new();
            if file.read_to_string(&mut content).is_ok() {
                if let Ok(settings) = serde_json::from_str::<Settings>(&content) {
                    let mut switch_key = settings.switch_key_status;
                    if switch_key == 0 {
                        switch_key = default_switch_key();
                    }
                    unsafe {
                        engine::vLanguage = settings.language;
                        engine::vInputType = settings.input_type;

                        engine::vCodeTable = settings.code_table;
                        engine::vSwitchKeyStatus = switch_key;
                        engine::vCheckSpelling = settings.check_spelling;
                        engine::vUseModernOrthography = settings.use_modern_orthography;
                        engine::vQuickTelex = settings.quick_telex;
                        engine::vUseEnglishDictionary = settings.use_english_dictionary;
                        engine::vCheckProgrammingKeywords = settings.check_programming_keywords;
                        engine::vLateAccentTransformation = settings.late_accent_transformation;
                        engine::vAllCapsAutoEscape = settings.all_caps_auto_escape;
                        engine::vUsePasteWorkaround = settings.use_paste_workaround;
                        engine::vSmartPunctCheck = settings.smart_punct_check;
                        engine::vUsePerceptronContext = settings.use_perceptron_context;
                        USE_HUD.store(settings.use_hud == 1, std::sync::atomic::Ordering::Relaxed);
                        engine::vTelexWAsU = settings.telex_w_as_u;
                        engine::vTelexBracketAsO = settings.telex_bracket_as_o;
                        let order = &settings.fsm_priority_order;
                        let fsm_order: [i32; 3] = [
                            order.get(0).copied().unwrap_or(0),
                            order.get(1).copied().unwrap_or(2),
                            order.get(2).copied().unwrap_or(1),
                        ];
                        engine::set_fsm_priority_order(&fsm_order);
                        engine::vFixRecommendBrowser = settings.fix_recommend_browser;
                        engine::vFixSpotlight = settings.fix_spotlight;
                        engine::vUseMacro = settings.use_macro;
                        engine::vUseMacroInEnglishMode = settings.use_macro_in_english_mode;
                        engine::vAutoCapsMacro = settings.auto_caps_macro;
                        engine::vUseSmartSwitchKey = settings.use_smart_switch_key;
                        engine::vUpperCaseFirstChar = settings.upper_case_first_char;
                        engine::vQuickStartConsonant = settings.quick_start_consonant;
                        engine::vRememberCode = settings.remember_code;
                        engine::vSendKeyStepByStep = settings.send_key_step_by_step;
                        engine::vFixChromiumBrowser = settings.fix_chromium_browser;
                        engine::vPerformLayoutCompat = settings.perform_layout_compat;
                        engine::set_convert_tool_dont_alert(settings.convert_tool_dont_alert);
                        engine::set_convert_tool_to_all_caps(settings.convert_tool_to_all_caps);
                        engine::set_convert_tool_to_all_non_caps(
                            settings.convert_tool_to_all_non_caps,
                        );
                        engine::set_convert_tool_to_caps_first_letter(
                            settings.convert_tool_to_caps_first_letter,
                        );
                        engine::set_convert_tool_to_caps_each_word(
                            settings.convert_tool_to_caps_each_word,
                        );
                        engine::set_convert_tool_remove_mark(settings.convert_tool_remove_mark);
                        engine::set_convert_tool_from_code(settings.convert_tool_from_code);
                        engine::set_convert_tool_to_code(settings.convert_tool_to_code);
                        PANEL_HOTKEY.store(settings.panel_hotkey, std::sync::atomic::Ordering::Relaxed);
                        #[cfg(target_os = "macos")]
                        {
                            if settings.panel_hotkey != 0 {
                                engine::macos_set_panel_hotkey_val(settings.panel_hotkey);
                            }
                        }
                        engine::set_convert_tool_hotkey(settings.convert_tool_hotkey);
                        engine::startNewSession();
                    }
                    GRAY_ICON.store(
                        settings.gray_icon == 1,
                        std::sync::atomic::Ordering::Relaxed,
                    );
                    SHOW_INPUT_TYPE_ON_TRAY.store(
                        settings.show_input_type_on_tray == 1,
                        std::sync::atomic::Ordering::Relaxed,
                    );
                    CLIPBOARD_ENABLED.store(
                        settings.clipboard_enabled == 1,
                        std::sync::atomic::Ordering::Relaxed,
                    );
                    CLIPBOARD_PIN_ON_TOP.store(
                        settings.clipboard_pin_on_top == 1,
                        std::sync::atomic::Ordering::Relaxed,
                    );
                    CLIPBOARD_AUTO_HIDE.store(
                        settings.clipboard_auto_hide == 1,
                        std::sync::atomic::Ordering::Relaxed,
                    );
                    CLIPBOARD_MAX_ITEMS.store(
                        settings.clipboard_max_items,
                        std::sync::atomic::Ordering::Relaxed,
                    );
                    if let Some(window) = handle.get_webview_window("clipboard") {
                        let _ = window.set_always_on_top(settings.clipboard_pin_on_top == 1);
                    }
                    if settings.clipboard_hotkey != 0 {
                        CLIPBOARD_HOTKEY.store(
                            settings.clipboard_hotkey,
                            std::sync::atomic::Ordering::Relaxed,
                        );
                    }
                    #[cfg(target_os = "macos")]
                    {
                        engine::macos_set_clipboard_enabled_val(
                            settings.clipboard_enabled == 1,
                        );
                        if settings.clipboard_hotkey != 0 {
                            engine::macos_set_clipboard_hotkey_val(settings.clipboard_hotkey);
                        }
                    }
                    let autostart_val = settings.autostart == 1;
                    AUTOSTART.store(autostart_val, std::sync::atomic::Ordering::Relaxed);
                    update_autostart_config(autostart_val);
                    OPEN_PANEL_ON_START.store(
                        settings.open_panel_on_start == 1,
                        std::sync::atomic::Ordering::Relaxed,
                    );
                }
            }
        }
    }
}

fn save_settings_to_disk(handle: &tauri::AppHandle, settings: &Settings) {
    if let Some(path) = get_settings_path(handle) {
        if let Ok(content) = serde_json::to_string_pretty(settings) {
            if let Ok(mut file) = File::create(path) {
                let _ = file.write_all(content.as_bytes());
            }
        }
    }
}

#[tauri::command]
fn update_settings(mut settings: Settings, handle: tauri::AppHandle) {

    settings.allow_consonant_zfwj = 1;
    if settings.switch_key_status == 0 {
        settings.switch_key_status = default_switch_key();
    }
    settings.input_type = settings.input_type.clamp(0, 3);
    settings.code_table = settings.code_table.clamp(0, 4);
    settings.clipboard_max_items = settings.clipboard_max_items.clamp(5, 200);
    let previous_code_table = unsafe { engine::vCodeTable };
    unsafe {
        engine::vLanguage = settings.language;
        engine::vInputType = settings.input_type;

        engine::vCodeTable = settings.code_table;
        engine::vSwitchKeyStatus = settings.switch_key_status;
        engine::vCheckSpelling = settings.check_spelling;
        engine::vUseModernOrthography = settings.use_modern_orthography;
        engine::vQuickTelex = settings.quick_telex;
        engine::vUseEnglishDictionary = settings.use_english_dictionary;
        engine::vCheckProgrammingKeywords = settings.check_programming_keywords;
        engine::vLateAccentTransformation = settings.late_accent_transformation;
        engine::vAllCapsAutoEscape = settings.all_caps_auto_escape;
        engine::vUsePasteWorkaround = settings.use_paste_workaround;
        engine::vSmartPunctCheck = settings.smart_punct_check;
        engine::vUsePerceptronContext = settings.use_perceptron_context;
        USE_HUD.store(settings.use_hud == 1, std::sync::atomic::Ordering::Relaxed);
        engine::vTelexWAsU = settings.telex_w_as_u;
        engine::vTelexBracketAsO = settings.telex_bracket_as_o;
        let order = &settings.fsm_priority_order;
        let fsm_order: [i32; 3] = [
            order.get(0).copied().unwrap_or(0),
            order.get(1).copied().unwrap_or(2),
            order.get(2).copied().unwrap_or(1),
        ];
        engine::set_fsm_priority_order(&fsm_order);
        engine::vFixRecommendBrowser = settings.fix_recommend_browser;
        engine::vFixSpotlight = settings.fix_spotlight;
        engine::vUseMacro = settings.use_macro;
        engine::vUseMacroInEnglishMode = settings.use_macro_in_english_mode;
        engine::vAutoCapsMacro = settings.auto_caps_macro;
        engine::vUseSmartSwitchKey = settings.use_smart_switch_key;
        engine::vUpperCaseFirstChar = settings.upper_case_first_char;
        engine::vQuickStartConsonant = settings.quick_start_consonant;
        engine::vRememberCode = settings.remember_code;
        engine::vSendKeyStepByStep = settings.send_key_step_by_step;
        engine::vFixChromiumBrowser = settings.fix_chromium_browser;
        engine::vPerformLayoutCompat = settings.perform_layout_compat;
        engine::set_convert_tool_dont_alert(settings.convert_tool_dont_alert);
        engine::set_convert_tool_to_all_caps(settings.convert_tool_to_all_caps);
        engine::set_convert_tool_to_all_non_caps(settings.convert_tool_to_all_non_caps);
        engine::set_convert_tool_to_caps_first_letter(settings.convert_tool_to_caps_first_letter);
        engine::set_convert_tool_to_caps_each_word(settings.convert_tool_to_caps_each_word);
        engine::set_convert_tool_remove_mark(settings.convert_tool_remove_mark);
        engine::set_convert_tool_from_code(settings.convert_tool_from_code);
        engine::set_convert_tool_to_code(settings.convert_tool_to_code);
        engine::set_convert_tool_hotkey(settings.convert_tool_hotkey);
        engine::startNewSession();
    }
    GRAY_ICON.store(
        settings.gray_icon == 1,
        std::sync::atomic::Ordering::Relaxed,
    );
    SHOW_INPUT_TYPE_ON_TRAY.store(
        settings.show_input_type_on_tray == 1,
        std::sync::atomic::Ordering::Relaxed,
    );
    CLIPBOARD_ENABLED.store(
        settings.clipboard_enabled == 1,
        std::sync::atomic::Ordering::Relaxed,
    );
    CLIPBOARD_PIN_ON_TOP.store(
        settings.clipboard_pin_on_top == 1,
        std::sync::atomic::Ordering::Relaxed,
    );
    CLIPBOARD_AUTO_HIDE.store(
        settings.clipboard_auto_hide == 1,
        std::sync::atomic::Ordering::Relaxed,
    );
    CLIPBOARD_MAX_ITEMS.store(
        settings.clipboard_max_items,
        std::sync::atomic::Ordering::Relaxed,
    );
    if let Some(window) = handle.get_webview_window("clipboard") {
        let _ = window.set_always_on_top(settings.clipboard_pin_on_top == 1);
    }
    if settings.clipboard_hotkey != 0 {
        CLIPBOARD_HOTKEY.store(
            settings.clipboard_hotkey,
            std::sync::atomic::Ordering::Relaxed,
        );
    }
    #[cfg(target_os = "macos")]
    {
        engine::macos_set_clipboard_enabled_val(settings.clipboard_enabled == 1);
        if settings.clipboard_hotkey != 0 {
            engine::macos_set_clipboard_hotkey_val(settings.clipboard_hotkey);
        }
        PANEL_HOTKEY.store(settings.panel_hotkey, std::sync::atomic::Ordering::Relaxed);
        if settings.panel_hotkey != 0 {
            engine::macos_set_panel_hotkey_val(settings.panel_hotkey);
        }
    }
    if previous_code_table != settings.code_table {
        engine::code_table_changed();
    }
    let previous_autostart = AUTOSTART.load(std::sync::atomic::Ordering::Relaxed);
    let new_autostart = settings.autostart == 1;
    if previous_autostart != new_autostart {
        AUTOSTART.store(new_autostart, std::sync::atomic::Ordering::Relaxed);
        update_autostart_config(new_autostart);
    }
    OPEN_PANEL_ON_START.store(
        settings.open_panel_on_start == 1,
        std::sync::atomic::Ordering::Relaxed,
    );
    save_settings_to_disk(&handle, &settings);
    let _ = handle.emit("settings-changed", settings.clone());
    update_tray_icon(&handle);
}

#[tauri::command]
fn reset_settings(handle: tauri::AppHandle) {
    let settings = default_settings();
    unsafe {
        engine::vLanguage = settings.language;
        engine::vInputType = settings.input_type;

        engine::vCodeTable = settings.code_table;
        engine::vSwitchKeyStatus = settings.switch_key_status;
        engine::vCheckSpelling = settings.check_spelling;
        engine::vUseModernOrthography = settings.use_modern_orthography;
        engine::vQuickTelex = settings.quick_telex;
        engine::vUseEnglishDictionary = settings.use_english_dictionary;
        engine::vCheckProgrammingKeywords = settings.check_programming_keywords;
        engine::vTelexWAsU = settings.telex_w_as_u;
        engine::vTelexBracketAsO = settings.telex_bracket_as_o;
        let order = &settings.fsm_priority_order;
        let fsm_order: [i32; 3] = [
            order.get(0).copied().unwrap_or(0),
            order.get(1).copied().unwrap_or(2),
            order.get(2).copied().unwrap_or(1),
        ];
        engine::set_fsm_priority_order(&fsm_order);
        engine::vFixRecommendBrowser = settings.fix_recommend_browser;
        engine::vFixSpotlight = settings.fix_spotlight;
        engine::vUseMacro = settings.use_macro;
        engine::vUseMacroInEnglishMode = settings.use_macro_in_english_mode;
        engine::vAutoCapsMacro = settings.auto_caps_macro;
        engine::vUseSmartSwitchKey = settings.use_smart_switch_key;
        engine::vUpperCaseFirstChar = settings.upper_case_first_char;
        engine::vQuickStartConsonant = settings.quick_start_consonant;
        engine::vRememberCode = settings.remember_code;
        engine::vSendKeyStepByStep = settings.send_key_step_by_step;
        engine::vFixChromiumBrowser = settings.fix_chromium_browser;
        engine::vPerformLayoutCompat = settings.perform_layout_compat;
        engine::vLateAccentTransformation = settings.late_accent_transformation;
        engine::vAllCapsAutoEscape = settings.all_caps_auto_escape;
        engine::vUsePasteWorkaround = settings.use_paste_workaround;
        engine::vSmartPunctCheck = settings.smart_punct_check;
        engine::set_convert_tool_dont_alert(settings.convert_tool_dont_alert);
        engine::set_convert_tool_to_all_caps(settings.convert_tool_to_all_caps);
        engine::set_convert_tool_to_all_non_caps(settings.convert_tool_to_all_non_caps);
        engine::set_convert_tool_to_caps_first_letter(settings.convert_tool_to_caps_first_letter);
        engine::set_convert_tool_to_caps_each_word(settings.convert_tool_to_caps_each_word);
        engine::set_convert_tool_remove_mark(settings.convert_tool_remove_mark);
        engine::set_convert_tool_from_code(settings.convert_tool_from_code);
        engine::set_convert_tool_to_code(settings.convert_tool_to_code);
        engine::set_convert_tool_hotkey(settings.convert_tool_hotkey);
        engine::startNewSession();
    }
    GRAY_ICON.store(settings.gray_icon == 1, std::sync::atomic::Ordering::Relaxed);
    CLIPBOARD_ENABLED.store(settings.clipboard_enabled == 1, std::sync::atomic::Ordering::Relaxed);
    CLIPBOARD_PIN_ON_TOP.store(settings.clipboard_pin_on_top == 1, std::sync::atomic::Ordering::Relaxed);
    CLIPBOARD_AUTO_HIDE.store(settings.clipboard_auto_hide == 1, std::sync::atomic::Ordering::Relaxed);
    CLIPBOARD_MAX_ITEMS.store(settings.clipboard_max_items, std::sync::atomic::Ordering::Relaxed);
    if let Some(window) = handle.get_webview_window("clipboard") {
        let _ = window.set_always_on_top(settings.clipboard_pin_on_top == 1);
    }
    if settings.clipboard_hotkey != 0 {
        CLIPBOARD_HOTKEY.store(settings.clipboard_hotkey, std::sync::atomic::Ordering::Relaxed);
    }
    #[cfg(target_os = "macos")]
    {
        engine::macos_set_clipboard_enabled_val(settings.clipboard_enabled == 1);
        if settings.clipboard_hotkey != 0 {
            engine::macos_set_clipboard_hotkey_val(settings.clipboard_hotkey);
        }
    }
    if 0 != settings.code_table {
        engine::code_table_changed();
    }
    AUTOSTART.store(settings.autostart == 1, std::sync::atomic::Ordering::Relaxed);
    update_autostart_config(settings.autostart == 1);
    OPEN_PANEL_ON_START.store(settings.open_panel_on_start == 1, std::sync::atomic::Ordering::Relaxed);
    save_settings_to_disk(&handle, &settings);
    db::db_reset_english_words();
    let words = db::db_get_english_words();
    engine::set_custom_english_words(&words.join("\n"));
    db::db_clear_vietnamese_words();
    engine::set_custom_vietnamese_words("");
    db::db_reset_programming_keywords();
    let prog_words = db::db_get_programming_keywords();
    engine::set_custom_programming_keywords(&prog_words.join("\n"));
    let _ = handle.emit("settings-changed", settings.clone());
    let _ = handle.emit("english-dict-reset", true);
    let _ = handle.emit("programming-keywords-reset", true);
    update_tray_icon(&handle);
}

fn get_macro_path(handle: &tauri::AppHandle) -> Option<PathBuf> {
    let mut path = handle.path().app_config_dir().ok()?;
    create_dir_all(&path).ok()?;
    path.push("macros.dat");
    Some(path)
}

fn save_macros_to_disk(_handle: &tauri::AppHandle) {
    let macros = engine::macros();
    let tuples: Vec<(String, String)> = macros.into_iter()
        .map(|m| (m.shortcut, m.content))
        .collect();
    db::db_clear_macros();
    db::db_insert_macros(&tuples);
}

fn load_macros_from_disk(handle: &tauri::AppHandle) {
    if let Some(path) = get_macro_path(handle) {
        if path.exists() {
            // legacy migration
            engine::load_macros(&path.to_string_lossy());
            save_macros_to_disk(handle);
            let _ = std::fs::remove_file(&path);
            return;
        }
    }
    
    let macros = db::db_get_macros();
    for (shortcut, content) in macros {
        engine::add_macro(&shortcut, &content);
    }
}

fn get_english_dict_path(handle: &tauri::AppHandle) -> Option<PathBuf> {
    let mut path = handle.path().app_config_dir().ok()?;
    create_dir_all(&path).ok()?;
    path.push("english.txt");
    Some(path)
}

fn load_english_dict_from_disk(handle: &tauri::AppHandle) {
    if let Some(path) = get_english_dict_path(handle) {
        if path.exists() {
            if let Ok(content) = std::fs::read_to_string(&path) {
                let mut merged_words = parse_english_words(&content);
                merged_words.sort_unstable();
                merged_words.dedup();
                db::db_insert_english_words(&merged_words);
                let _ = std::fs::remove_file(&path); // delete legacy file
            }
        }
    }
    
    let words = db::db_get_english_words();
    engine::set_custom_english_words(&words.join("\n"));
}

fn load_vietnamese_dict_from_disk(_handle: &tauri::AppHandle) {
    let words = db::db_get_vietnamese_words();
    engine::set_custom_vietnamese_words(&words.join("\n"));
}

#[tauri::command]
fn get_english_dictionary() -> Result<EnglishDictionary, String> {
    let custom_words = db::db_get_english_words();
    Ok(EnglishDictionary {
        custom_words,
    })
}

fn parse_english_words(content: &str) -> Vec<String> {
    let mut words: Vec<String> = content
        .lines()
        .filter(|line| !line.trim_start().starts_with('#'))
        .flat_map(str::split_whitespace)
        .filter_map(|word| {
            let normalized = word.to_ascii_lowercase();
            normalized
                .bytes()
                .all(|byte| byte.is_ascii_alphabetic())
                .then_some(normalized)
        })
        .collect();
    words.sort_unstable();
    words.dedup();
    words
}

#[tauri::command]
fn save_custom_english_words(words: String) -> Result<(), String> {
    let normalized = parse_english_words(&words);
    db::db_clear_english_words();
    db::db_insert_english_words(&normalized);
    engine::set_custom_english_words(&normalized.join("\n"));
    auto_sync_to_cloud();
    Ok(())
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct VietnameseDictionary {
    pub custom_words: Vec<String>,
}

#[tauri::command]
fn get_vietnamese_dictionary() -> Result<VietnameseDictionary, String> {
    let custom_words = db::db_get_vietnamese_words();
    Ok(VietnameseDictionary {
        custom_words,
    })
}

#[tauri::command]
fn save_custom_vietnamese_words(words: String) -> Result<(), String> {
    let mut normalized: Vec<String> = words
        .lines()
        .flat_map(str::split_whitespace)
        .map(|w| w.to_lowercase())
        .filter(|w| !w.is_empty())
        .collect();
    normalized.sort_unstable();
    normalized.dedup();
    db::db_clear_vietnamese_words();
    db::db_insert_vietnamese_words(&normalized);
    engine::set_custom_vietnamese_words(&normalized.join("\n"));
    auto_sync_to_cloud();
    Ok(())
}

fn load_programming_keywords_from_disk(_handle: &tauri::AppHandle) {
    let keywords = db::db_get_programming_keywords();
    engine::set_custom_programming_keywords(&keywords.join("\n"));
}

#[tauri::command]
fn get_programming_keywords() -> Result<ProgrammingKeywordDictionary, String> {
    let custom_keywords = db::db_get_programming_keywords();
    Ok(ProgrammingKeywordDictionary { custom_keywords })
}

fn parse_programming_keywords(content: &str) -> Vec<String> {
    let mut keywords: Vec<String> = content
        .lines()
        .filter(|line| !line.trim_start().starts_with('#'))
        .flat_map(str::split_whitespace)
        .filter_map(|word| {
            let w = word.trim().to_string();
            if w.is_empty() { None } else { Some(w) }
        })
        .collect();
    keywords.sort_unstable();
    keywords.dedup();
    keywords
}

#[tauri::command]
fn save_custom_programming_keywords(keywords: String) -> Result<(), String> {
    let normalized = parse_programming_keywords(&keywords);
    db::db_clear_programming_keywords();
    db::db_insert_programming_keywords(&normalized);
    engine::set_custom_programming_keywords(&normalized.join("\n"));
    auto_sync_to_cloud();
    Ok(())
}

#[tauri::command]
fn list_macros() -> Vec<engine::MacroEntry> {
    engine::macros()
}

#[tauri::command]
fn upsert_macro(
    shortcut: String,
    content: String,
    handle: tauri::AppHandle,
) -> Result<Vec<engine::MacroEntry>, String> {
    let shortcut = shortcut.trim();
    if shortcut.is_empty() {
        return Err("Từ gõ tắt không được để trống.".into());
    }
    if content.is_empty() {
        return Err("Nội dung thay thế không được để trống.".into());
    }
    if !engine::add_macro(shortcut, &content) {
        return Err("Không thể lưu mục gõ tắt. Hãy kiểm tra độ dài dữ liệu.".into());
    }
    save_macros_to_disk(&handle);
    auto_sync_to_cloud();
    Ok(engine::macros())
}

#[tauri::command]
fn remove_macro(
    shortcut: String,
    handle: tauri::AppHandle,
) -> Result<Vec<engine::MacroEntry>, String> {
    if !engine::delete_macro(&shortcut) {
        return Err("Không tìm thấy mục gõ tắt.".into());
    }
    save_macros_to_disk(&handle);
    auto_sync_to_cloud();
    Ok(engine::macros())
}

#[tauri::command]
fn convert_text(request: ConvertRequest) -> Result<String, String> {
    engine::convert_text(
        &request.source,
        request.from_code,
        request.to_code,
        request.all_caps,
        request.all_non_caps,
        request.caps_first_letter,
        request.caps_each_word,
        request.remove_mark,
    )
    .ok_or_else(|| "Không thể chuyển đổi văn bản với cấu hình hiện tại.".into())
}

#[tauri::command]
fn check_accessibility() -> bool {
    unsafe { engine::is_accessibility_granted() }
}

#[tauri::command]
fn request_accessibility() {
    unsafe { engine::request_accessibility_permission() }
}

#[tauri::command]
fn quit(handle: tauri::AppHandle) {
    unsafe {
        engine::stop_event_tap();
    }
    handle.exit(0);
}

fn get_tray_icon(language: i32) -> tauri::image::Image<'static> {
    #[cfg(target_os = "macos")]
    {
        let is_vietnamese = language == 1;
        let is_gray = GRAY_ICON.load(std::sync::atomic::Ordering::Relaxed);
        let show_label = SHOW_INPUT_TYPE_ON_TRAY.load(std::sync::atomic::Ordering::Relaxed);
        let input_type = if show_label {
            unsafe { engine::vInputType }
        } else {
            -1 // signal to ObjC: don't show label
        };
        if let Some(png_bytes) = engine::macos_status_icon(is_vietnamese, is_gray, input_type) {
            if let Ok(img) = tauri::image::Image::from_bytes(&png_bytes) {
                return img;
            }
        }
    }

    let bytes = if language == 1 {
        include_bytes!("../icons/Status.png").as_slice()
    } else {
        include_bytes!("../icons/StatusEng.png").as_slice()
    };
    tauri::image::Image::from_bytes(bytes).expect("Failed to parse status icon")
}

fn hotkey_to_accelerator(status: i32) -> Option<String> {
    let key_code = status & 0xff;
    if key_code == 0xfe {
        return None;
    }

    let ctrl = (status & 0x100) != 0;
    let option = (status & 0x200) != 0;
    let command = (status & 0x400) != 0;
    let shift = (status & 0x800) != 0;

    let mut parts = Vec::new();

    if command {
        parts.push("Cmd");
    }
    if ctrl {
        parts.push("Ctrl");
    }
    if option {
        parts.push("Alt");
    }
    if shift {
        parts.push("Shift");
    }

    let char_code = (status >> 24) & 0xff;
    let key_str = if key_code == 49 {
        "Space".to_string()
    } else if char_code > 0 {
        let c = char_code as u8 as char;
        if c.is_ascii_alphanumeric() {
            c.to_string().to_uppercase()
        } else {
            match c {
                '`' | '~' => "Backquote".to_string(),
                '-' | '_' => "Minus".to_string(),
                '=' | '+' => "Equal".to_string(),
                '[' | '{' => "BracketLeft".to_string(),
                ']' | '}' => "BracketRight".to_string(),
                '\\' | '|' => "Backslash".to_string(),
                ';' | ':' => "Semicolon".to_string(),
                '\'' | '"' => "Quote".to_string(),
                ',' | '<' => "Comma".to_string(),
                '.' | '>' => "Period".to_string(),
                '/' | '?' => "Slash".to_string(),
                _ => c.to_string().to_uppercase(),
            }
        }
    } else {
        match key_code {
            49 => "Space".to_string(),
            36 => "Enter".to_string(),
            48 => "Tab".to_string(),
            51 => "Backspace".to_string(),
            53 => "Escape".to_string(),
            115 => "Home".to_string(),
            119 => "End".to_string(),
            116 => "PageUp".to_string(),
            121 => "PageDown".to_string(),
            123 => "Left".to_string(),
            124 => "Right".to_string(),
            125 => "Down".to_string(),
            126 => "Up".to_string(),
            _ => match key_code {
                0 => "A".to_string(),
                1 => "S".to_string(),
                2 => "D".to_string(),
                3 => "F".to_string(),
                4 => "H".to_string(),
                5 => "G".to_string(),
                6 => "Z".to_string(),
                7 => "X".to_string(),
                8 => "C".to_string(),
                9 => "V".to_string(),
                11 => "B".to_string(),
                12 => "Q".to_string(),
                13 => "W".to_string(),
                14 => "E".to_string(),
                15 => "R".to_string(),
                16 => "Y".to_string(),
                17 => "T".to_string(),
                18 => "1".to_string(),
                19 => "2".to_string(),
                20 => "3".to_string(),
                21 => "4".to_string(),
                22 => "6".to_string(),
                23 => "5".to_string(),
                24 => "Equal".to_string(),
                25 => "9".to_string(),
                26 => "7".to_string(),
                27 => "Minus".to_string(),
                28 => "8".to_string(),
                29 => "0".to_string(),
                30 => "BracketRight".to_string(),
                31 => "O".to_string(),
                32 => "U".to_string(),
                33 => "BracketLeft".to_string(),
                34 => "I".to_string(),
                35 => "P".to_string(),
                37 => "L".to_string(),
                38 => "J".to_string(),
                39 => "Quote".to_string(),
                40 => "K".to_string(),
                41 => "Semicolon".to_string(),
                42 => "Backslash".to_string(),
                43 => "Comma".to_string(),
                44 => "Slash".to_string(),
                45 => "N".to_string(),
                46 => "M".to_string(),
                47 => "Period".to_string(),
                50 => "Backquote".to_string(),
                _ => return None,
            },
        }
    };
    parts.push(&key_str);
    Some(parts.join("+"))
}

fn build_tray_menu<R: tauri::Runtime>(handle: &tauri::AppHandle<R>) -> Menu<R> {
    let has_access = unsafe { engine::is_accessibility_granted() };
    if !has_access {
        let request_access = MenuItemBuilder::new("Cấp quyền truy cập Trợ năng...")
            .id("request_accessibility")
            .build(handle)
            .unwrap();

        let quit = MenuItemBuilder::new("Thoát")
            .id("quit")
            .build(handle)
            .unwrap();

        let menu = Menu::new(handle).unwrap();
        let _ = menu.append(&request_access);
        let _ = menu.append(&PredefinedMenuItem::separator(handle).unwrap());
        let _ = menu.append(&quit);
        return menu;
    }

    let is_vietnamese = unsafe { engine::vLanguage == 1 };
    let switch_key = unsafe { engine::vSwitchKeyStatus };
    let switch_key_accel = hotkey_to_accelerator(switch_key);

    let mut toggle_lang_builder = CheckMenuItemBuilder::new("Bật Tiếng Việt")
        .id("toggle_language")
        .checked(is_vietnamese);
    if let Some(ref accel) = switch_key_accel {
        toggle_lang_builder = toggle_lang_builder.accelerator(accel);
    }
    let toggle_lang = match toggle_lang_builder.build(handle) {
        Ok(item) => item,
        Err(e) => {
            eprintln!(
                "Failed to build toggle_language menu item with accelerator: {:?}",
                e
            );
            CheckMenuItemBuilder::new("Bật Tiếng Việt")
                .id("toggle_language")
                .checked(is_vietnamese)
                .build(handle)
                .unwrap()
        }
    };

    let input_type_menu = SubmenuBuilder::new(handle, "Kiểu gõ").build().unwrap();
    let current_input_type = unsafe { engine::vInputType };
    let it_labels = ["Telex", "VNI"];
    for (i, label) in it_labels.iter().enumerate() {
        let checked = current_input_type == i as i32;
        let item = CheckMenuItemBuilder::new(*label)
            .id(format!("input_type_{}", i))
            .checked(checked)
            .build(handle)
            .unwrap();
        let _ = input_type_menu.append(&item);
    }

    let code_table_menu = SubmenuBuilder::new(handle, "Bảng mã").build().unwrap();
    let current_code_table = unsafe { engine::vCodeTable };
    let ct_labels = [
        ("Unicode dựng sẵn", 0),
        ("TCVN3 (ABC)", 1),
        ("VNI Windows", 2),
        ("Unicode tổ hợp", 3),
        ("Vietnamese Locale CP1258", 4),
    ];
    for (label, i) in ct_labels.iter() {
        let checked = current_code_table == *i;
        let item = CheckMenuItemBuilder::new(*label)
            .id(format!("code_table_{}", i))
            .checked(checked)
            .build(handle)
            .unwrap();
        let _ = code_table_menu.append(&item);
    }

    let convert_tool = MenuItemBuilder::new("Công cụ chuyển mã...")
        .id("convert_tool")
        .build(handle)
        .unwrap();

    let convert_hotkey = unsafe { engine::get_convert_tool_hotkey() };
    let convert_hotkey_accel = hotkey_to_accelerator(convert_hotkey);
    let mut quick_convert_builder = MenuItemBuilder::new("Chuyển mã nhanh").id("quick_convert");
    if let Some(ref accel) = convert_hotkey_accel {
        quick_convert_builder = quick_convert_builder.accelerator(accel);
    }
    let quick_convert = match quick_convert_builder.build(handle) {
        Ok(item) => item,
        Err(e) => {
            eprintln!(
                "Failed to build quick_convert menu item with accelerator: {:?}",
                e
            );
            MenuItemBuilder::new("Chuyển mã nhanh")
                .id("quick_convert")
                .build(handle)
                .unwrap()
        }
    };

    let panel_hotkey = PANEL_HOTKEY.load(std::sync::atomic::Ordering::Relaxed);
    let panel_hotkey_accel = hotkey_to_accelerator(panel_hotkey);
    let mut control_panel_builder = MenuItemBuilder::new("Bảng điều khiển...").id("control_panel");
    if let Some(ref accel) = panel_hotkey_accel {
        control_panel_builder = control_panel_builder.accelerator(accel);
    }
    let control_panel = match control_panel_builder.build(handle) {
        Ok(item) => item,
        Err(e) => {
            eprintln!(
                "Failed to build control_panel menu item with accelerator: {:?}",
                e
            );
            MenuItemBuilder::new("Bảng điều khiển...")
                .id("control_panel")
                .build(handle)
                .unwrap()
        }
    };

    let macro_settings = MenuItemBuilder::new("Gõ tắt...")
        .id("macro_settings")
        .build(handle)
        .unwrap();

    let about = MenuItemBuilder::new("Giới thiệu")
        .id("about")
        .build(handle)
        .unwrap();

    let check_updates = MenuItemBuilder::new("Kiểm tra cập nhật...")
        .id("check_updates")
        .build(handle)
        .unwrap();

    let quit = MenuItemBuilder::new("Thoát")
        .id("quit")
        .build(handle)
        .unwrap();

    let clipboard_hotkey = CLIPBOARD_HOTKEY.load(std::sync::atomic::Ordering::Relaxed);
    let clipboard_hotkey_accel = hotkey_to_accelerator(clipboard_hotkey);
    let mut clipboard_menu_builder = MenuItemBuilder::new("Bảng ghi nhớ...").id("clipboard_history");
    if CLIPBOARD_ENABLED.load(std::sync::atomic::Ordering::Relaxed) {
        if let Some(ref accel) = clipboard_hotkey_accel {
            clipboard_menu_builder = clipboard_menu_builder.accelerator(accel);
        }
    }
    let clipboard_menu = match clipboard_menu_builder.build(handle) {
        Ok(item) => item,
        Err(e) => {
            eprintln!("Failed to build clipboard_history menu item: {:?}", e);
            MenuItemBuilder::new("Bảng ghi nhớ...")
                .id("clipboard_history")
                .build(handle)
                .unwrap()
        }
    };

    let menu = Menu::new(handle).unwrap();
    let _ = menu.append(&toggle_lang);
    let _ = menu.append(&PredefinedMenuItem::separator(handle).unwrap());

    let _ = menu.append(&input_type_menu);
    let _ = menu.append(&code_table_menu);
    let _ = menu.append(&PredefinedMenuItem::separator(handle).unwrap());

    let _ = menu.append(&convert_tool);
    let _ = menu.append(&quick_convert);
    let _ = menu.append(&clipboard_menu);
    let _ = menu.append(&PredefinedMenuItem::separator(handle).unwrap());

    let _ = menu.append(&control_panel);
    let _ = menu.append(&macro_settings);
    let _ = menu.append(&check_updates);
    let _ = menu.append(&about);
    let _ = menu.append(&PredefinedMenuItem::separator(handle).unwrap());

    let _ = menu.append(&quit);

    menu
}

static LAST_TRAY_STATE: OnceLock<Mutex<(i32, bool, bool, i32, i32, bool, bool)>> = OnceLock::new();

fn update_tray_icon<R: tauri::Runtime>(handle: &tauri::AppHandle<R>) {
    if let Some(tray) = TRAY_ICON.get() {
        let lang = unsafe { engine::vLanguage };
        let gray = GRAY_ICON.load(std::sync::atomic::Ordering::Relaxed);
        let show_label = SHOW_INPUT_TYPE_ON_TRAY.load(std::sync::atomic::Ordering::Relaxed);
        let input_type = unsafe { engine::vInputType };
        let code_table = unsafe { engine::vCodeTable };
        let is_english = unsafe { engine::macos_is_current_input_source_english() };
        let has_access = unsafe { engine::is_accessibility_granted() };

        let state_mutex = LAST_TRAY_STATE.get_or_init(|| Mutex::new((-1, false, false, -1, -1, false, false)));
        if let Ok(mut last_state) = state_mutex.lock() {
            if *last_state == (lang, gray, show_label, input_type, code_table, is_english, has_access) {
                return;
            }
            *last_state = (lang, gray, show_label, input_type, code_table, is_english, has_access);
        }

        let icon = get_tray_icon(lang);
        let _ = tray.set_icon(Some(icon));
        let _ = tray.set_icon_as_template(gray);
        let menu = build_tray_menu(handle);
        let _ = tray.set_menu(Some(menu));
    }
}

fn notify_frontend() {
    if let Some(handle) = APP_HANDLE.get() {
        let settings = get_settings();
        let handle_clone = handle.clone();
        let settings_clone = settings.clone();
        std::thread::spawn(move || {
            save_settings_to_disk(&handle_clone, &settings_clone);
        });
        let _ = handle.emit("settings-changed", settings);
    }
}

fn trigger_hud(handle: &tauri::AppHandle, val: i32) {
    if !USE_HUD.load(std::sync::atomic::Ordering::Relaxed) {
        return;
    }

    // Only show HUD when the system input source is English —
    // that is the only state where VNKey is actively intercepting keystrokes.
    let is_english = unsafe { engine::macos_is_current_input_source_english() };
    if !is_english {
        return;
    }

    // Mode string format: "V|Telex", "V|VNI", or "E|English"
    let input_type = unsafe { engine::vInputType };
    let mode_str = if val == 1 {
        let type_name = if input_type == 1 { "VNI" } else { "Telex" };
        format!("V|{type_name}")
    } else {
        "E|English".to_string()
    };

    // Increment trigger ID to debounce/cancel previous fade-out timers
    let trigger_id = LAST_HUD_TRIGGER_ID.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;

    // Dispatch only the fast UI drawing commands to the main thread
    let handle_clone = handle.clone();
    let _ = handle.run_on_main_thread(move || {
        if let Some(hud) = handle_clone.get_webview_window("hud") {
            const HUD_W: f64 = 240.0;
            const HUD_H: f64 = 80.0;

            // Position fixed at the bottom-center of the primary screen
            let mut hud_x = 0.0;
            let mut hud_y = 0.0;
            if let Ok(Some(monitor)) = hud.primary_monitor() {
                let size = monitor.size();
                let scale_factor = monitor.scale_factor();
                let screen_w = size.width as f64 / scale_factor;
                let screen_h = size.height as f64 / scale_factor;
                hud_x = (screen_w - HUD_W) / 2.0;
                hud_y = screen_h - HUD_H - 80.0; // 80px above screen bottom
            }

            // 1. Move to the fixed position
            let _ = hud.set_position(tauri::Position::Logical(tauri::LogicalPosition {
                x: hud_x,
                y: hud_y,
            }));
            
            // 2. Emit the update to Svelte (which triggers CSS fade-in)
            let _ = hud.emit("hud-update", mode_str);

            // 3. Show the window ONLY if it's not already visible.
            if !hud.is_visible().unwrap_or(false) {
                let _ = hud.show();
            }

            let hud_clone = hud.clone();
            tauri::async_runtime::spawn(async move {
                // Let Svelte trigger the CSS fade-out animation after 2.0 seconds.
                // The window stays natively shown (transparent & click-through),
                // completely bypassing the laggy native macOS show/hide cycles.
                tokio::time::sleep(tokio::time::Duration::from_millis(2000)).await;
                if LAST_HUD_TRIGGER_ID.load(std::sync::atomic::Ordering::Relaxed) == trigger_id {
                    let _ = hud_clone.emit("hud-hide", ());
                }
            });
        }
    });
}

use std::sync::atomic::{AtomicI32, AtomicI64};
static LAST_HUD_VAL: AtomicI32 = AtomicI32::new(-1);
static LAST_HUD_TIME: AtomicI64 = AtomicI64::new(0);
static LAST_HUD_TRIGGER_ID: AtomicU64 = AtomicU64::new(0);

#[no_mangle]
pub extern "C" fn rust_onInputMethodChanged(val: std::os::raw::c_int) {
    unsafe {
        engine::vLanguage = val;
    }
    
    // Deduplicate and throttle HUD triggers to prevent CPU spike and system lag
    // when the engine sends input method changes rapidly during typing.
    let old_val = LAST_HUD_VAL.swap(val, std::sync::atomic::Ordering::Relaxed);
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;
    let last_time = LAST_HUD_TIME.swap(now, std::sync::atomic::Ordering::Relaxed);

    if old_val == val && (now - last_time) < 1500 {
        // Redundant state change within 1.5 seconds, skip HUD trigger to avoid thread spam
        return;
    }

    if let Some(handle) = APP_HANDLE.get() {
        let handle_clone = handle.clone();
        
        // Update tray icon on the main thread
        let _ = handle.run_on_main_thread(move || {
            update_tray_icon(&handle_clone);
        });

        // Query caret and trigger HUD on a background thread
        let handle_clone_hud = handle.clone();
        std::thread::spawn(move || {
            trigger_hud(&handle_clone_hud, val);
        });
    }
    notify_frontend();
}

#[no_mangle]
pub extern "C" fn rust_onCodeTableChanged(val: std::os::raw::c_int) {
    unsafe {
        engine::vCodeTable = val;
    }
    if let Some(handle) = APP_HANDLE.get() {
        update_tray_icon(handle);
    }
    notify_frontend();
}

#[no_mangle]
pub extern "C" fn rust_onAccessibilityRevoked() {
    // Called from the macOS main thread (dispatched via dispatch_async in ObjC).
    // 1. Stop the event tap cleanly and immediately to release the event delivery queue
    //    and prevent deadlock with WindowServer/TCC daemon.
    unsafe { engine::stop_event_tap(); }

    let Some(handle) = APP_HANDLE.get() else { return };

    // 2. Defer TCC checking and UI updates to a background thread to prevent blocking
    //    the main thread while the OS processes the privacy database changes.
    let handle_clone = handle.clone();
    std::thread::spawn(move || {
        // Sleep a short moment to let OS process the revocation state
        std::thread::sleep(std::time::Duration::from_millis(100));

        if unsafe { engine::is_accessibility_granted() } {
            // Permission is actually still valid! The event tap was probably disabled
            // temporarily (e.g. secure input active). Re-enable it on the main thread.
            let _ = handle_clone.run_on_main_thread(move || {
                unsafe { engine::start_event_tap(); }
            });
        } else {
            // Permission was truly revoked. Let's do UI teardown and start the watcher.
            let handle_clone_2 = handle_clone.clone();
            let handle_for_ui = handle_clone_2.clone();
            let _ = handle_clone.run_on_main_thread(move || {
                update_tray_icon(&handle_for_ui);
                if let Some(onboarding_win) = handle_for_ui.get_webview_window("onboarding") {
                    let _ = onboarding_win.show();
                }
                update_dock_icon(&handle_for_ui);
                let _ = handle_for_ui.emit("accessibility-revoked", ());
            });

            // Monitor in the background for re-grant
            loop {
                std::thread::sleep(std::time::Duration::from_millis(1500));
                if unsafe { engine::is_accessibility_granted() } {
                    let handle_clone_3 = handle_clone_2.clone();
                    // Load configuration and dictionaries in the background thread
                    load_settings_from_disk(&handle_clone_3);
                    load_macros_from_disk(&handle_clone_3);
                    load_english_dict_from_disk(&handle_clone_3);
                    load_vietnamese_dict_from_disk(&handle_clone_3);
                    load_programming_keywords_from_disk(&handle_clone_3);

                    // Dispatch UI operations and start event tap to the main thread
                    let handle_for_regrant_ui = handle_clone_2.clone();
                    let _ = handle_for_regrant_ui.run_on_main_thread(move || {
                        unsafe { engine::start_event_tap(); }
                        update_tray_icon(&handle_clone_3);
                        if let Some(hud) = handle_clone_3.get_webview_window("hud") {
                            let _ = hud.set_ignore_cursor_events(true);
                            #[cfg(target_os = "macos")]
                            if let Ok(ns_win) = hud.ns_window() {
                                unsafe { engine::macos_configure_hud_window(ns_win); }
                            }
                        }
                        if let Some(onboarding_win) = handle_clone_3.get_webview_window("onboarding") {
                            let _ = onboarding_win.close();
                        }
                        if let Some(main_win) = handle_clone_3.get_webview_window("main") {
                            let _ = main_win.show();
                            let _ = main_win.set_focus();
                        }
                        update_dock_icon(&handle_clone_3);
                        let _ = handle_clone_3.emit("accessibility-granted", ());
                    });
                    break;
                }
            }
        }
    });
}

#[no_mangle]
pub extern "C" fn rust_onQuickConvert() {
    let success = unsafe { engine::do_quick_convert() };
    if let Some(handle) = APP_HANDLE.get() {
        let _ = handle.emit("quick-convert-result", success);
    }
}

#[no_mangle]
pub extern "C" fn rust_onToggleControlPanel() {
    if let Some(handle) = APP_HANDLE.get() {
        let _ = handle.run_on_main_thread(move || {
            toggle_control_panel(handle);
        });
    }
}

fn toggle_control_panel(handle: &tauri::AppHandle) {
    #[cfg(target_os = "macos")]
    {
        if let Some(window) = handle.get_webview_window("main") {
            if window.is_visible().unwrap_or(false) {
                let _ = window.hide();
            } else {
                let _ = window.show().and_then(|_| window.set_focus());
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_onToggleClipboardPicker() {
    if let Some(handle) = APP_HANDLE.get() {
        let _ = handle.run_on_main_thread(move || {
            toggle_clipboard_picker(handle);
        });
    }
}

fn toggle_clipboard_picker(handle: &tauri::AppHandle) {
    #[cfg(target_os = "macos")]
    {
        if let Some(window) = handle.get_webview_window("clipboard") {
            if window.is_visible().unwrap_or(false) {
                let _ = window.hide();
            } else {
                let prev_pid = engine::get_frontmost_app_pid();
                let _ = window.emit("set-prev-pid", prev_pid);

                let is_pin = CLIPBOARD_PIN_ON_TOP.load(std::sync::atomic::Ordering::Relaxed);
                let _ = window.set_always_on_top(is_pin);
                let _ = window.show().and_then(|_| window.set_focus());
            }
        }
    }
}

#[tauri::command]
fn get_clipboard_items() -> Vec<ClipboardItem> {
    if let Some(history_mutex) = CLIPBOARD_HISTORY.get() {
        history_mutex.lock().unwrap().clone()
    } else {
        Vec::new()
    }
}

#[tauri::command]
fn remove_clipboard_item(id: String, handle: tauri::AppHandle) {
    if let Some(history_mutex) = CLIPBOARD_HISTORY.get() {
        let mut history = history_mutex.lock().unwrap();
        if let Some(pos) = history.iter().position(|item| item.id == id) {
            let removed = history.remove(pos);
            if let Some(ref path) = removed.image_path {
                let _ = std::fs::remove_file(path);
            }
            save_clipboard_to_disk_internal(&handle, &history);
            let _ = handle.emit("clipboard-changed", ());
        }
    }
}

#[tauri::command]
fn clear_clipboard_history(handle: tauri::AppHandle) {
    if let Some(history_mutex) = CLIPBOARD_HISTORY.get() {
        let mut history = history_mutex.lock().unwrap();
        for item in history.iter() {
            if let Some(ref path) = item.image_path {
                let _ = std::fs::remove_file(path);
            }
        }
        history.clear();
        save_clipboard_to_disk_internal(&handle, &history);
        let _ = handle.emit("clipboard-changed", ());
    }
}

#[tauri::command]
fn strip_clipboard_formatting(id: String, handle: tauri::AppHandle) {
    if let Some(history_mutex) = CLIPBOARD_HISTORY.get() {
        let mut history = history_mutex.lock().unwrap();
        if let Some(pos) = history.iter().position(|item| item.id == id) {
            let mut item = history[pos].clone();
            item.html = None;
            history[pos] = item;
            save_clipboard_to_disk_internal(&handle, &history);
            let _ = handle.emit("clipboard-changed", ());
        }
    }
}

#[tauri::command]
fn paste_clipboard_item(id: String, prev_pid: i32, _handle: tauri::AppHandle) {
    #[cfg(target_os = "macos")]
    {
        let item_opt = if let Some(history_mutex) = CLIPBOARD_HISTORY.get() {
            let history = history_mutex.lock().unwrap();
            history.iter().find(|i| i.id == id).cloned()
        } else {
            None
        };

        if let Some(item) = item_opt {
            let files_joined = item.file_paths.as_ref().map(|paths| paths.join("\n"));
            engine::clipboard_paste_item(
                prev_pid,
                item.text.as_deref(),
                item.html.as_deref(),
                item.image_path.as_deref(),
                files_joined.as_deref(),
            );
            // Update LAST_CHANGE_COUNT immediately to prevent duplicate copy event on polling
            let new_count = engine::clipboard_get_change_count();
            LAST_CHANGE_COUNT.store(new_count, std::sync::atomic::Ordering::Relaxed);
        }
    }
}

#[tauri::command]
fn toggle_clipboard_picker_window(handle: tauri::AppHandle) {
    toggle_clipboard_picker(&handle);
}

#[tauri::command]
fn hide_clipboard_picker_window(handle: tauri::AppHandle) {
    if let Some(window) = handle.get_webview_window("clipboard") {
        let _ = window.hide();
    }
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct AppConfig {
    pub language: i32,
    pub input_type: i32,

    pub code_table: i32,
    pub check_spelling: i32,
    pub use_modern_orthography: i32,
    pub quick_telex: i32,
    pub use_english_dictionary: i32,
    pub use_macro: i32,
    pub use_macro_in_english_mode: i32,
    pub auto_caps_macro: i32,
    pub upper_case_first_char: i32,
    pub allow_consonant_zfwj: i32,
    pub quick_start_consonant: i32,
    pub quick_end_consonant: i32,
    #[serde(default)]
    pub check_programming_keywords: i32,
    #[serde(default = "default_fsm_priority_order")]
    pub fsm_priority_order: Vec<i32>,
    pub name: Option<String>,
}

pub fn get_app_settings_path(handle: &tauri::AppHandle) -> Option<PathBuf> {
    if let Ok(mut path) = handle.path().app_config_dir() {
        let _ = create_dir_all(&path);
        path.push("app_settings.json");
        Some(path)
    } else {
        None
    }
}

#[tauri::command]
async fn get_running_applications() -> Result<Option<String>, String> {
    #[cfg(target_os = "macos")]
    {
        let res = tauri::async_runtime::spawn_blocking(|| {
            engine::get_running_applications_json()
        }).await.map_err(|e| e.to_string())?;
        
        if let Some(json_str) = res {
            if let Ok(mut apps) = serde_json::from_str::<Vec<serde_json::Value>>(&json_str) {
                apps.retain(|app| {
                    if let Some(name) = app.get("name").and_then(|n| n.as_str()) {
                        if name.to_lowercase().contains("vnkey") {
                            return false;
                        }
                    }
                    if let Some(bundle_id) = app.get("bundle_id").and_then(|b| b.as_str()) {
                        if bundle_id.to_lowercase().contains("vnkey") {
                            return false;
                        }
                    }
                    true
                });
                return Ok(Some(serde_json::to_string(&apps).unwrap_or(json_str)));
            } else {
                return Ok(Some(json_str));
            }
        }
        Ok(None)
    }
    #[cfg(not(target_os = "macos"))]
    {
        Ok(None)
    }
}

#[tauri::command]
async fn get_application_info_by_path(path: String) -> Result<Option<String>, String> {
    #[cfg(target_os = "macos")]
    {
        let res = tauri::async_runtime::spawn_blocking(move || {
            engine::get_application_info_by_path_json(&path)
        }).await.map_err(|e| e.to_string())?;
        Ok(res)
    }
    #[cfg(not(target_os = "macos"))]
    {
        Ok(None)
    }
}

#[tauri::command]
async fn get_application_info_by_bundle_id(bundle_id: String) -> Result<Option<String>, String> {
    #[cfg(target_os = "macos")]
    {
        let res = tauri::async_runtime::spawn_blocking(move || {
            engine::get_application_info_by_bundle_id_json(&bundle_id)
        }).await.map_err(|e| e.to_string())?;
        Ok(res)
    }
    #[cfg(not(target_os = "macos"))]
    {
        Ok(None)
    }
}

#[tauri::command]
async fn get_application_info_by_name(name: String) -> Result<Option<String>, String> {
    #[cfg(target_os = "macos")]
    {
        let res = tauri::async_runtime::spawn_blocking(move || {
            engine::get_application_info_by_name_json(&name)
        }).await.map_err(|e| e.to_string())?;
        Ok(res)
    }
    #[cfg(not(target_os = "macos"))]
    {
        Ok(None)
    }
}

#[tauri::command]
fn get_app_configs(
    handle: tauri::AppHandle,
) -> Result<std::collections::HashMap<String, AppConfig>, String> {
    if let Some(path) = get_app_settings_path(&handle) {
        if path.exists() {
            if let Ok(content) = std::fs::read_to_string(path) {
                if let Ok(configs) =
                    serde_json::from_str::<std::collections::HashMap<String, AppConfig>>(&content)
                {
                    return Ok(configs);
                }
            }
        }
    }
    Ok(std::collections::HashMap::new())
}

#[tauri::command]
fn save_app_config(
    bundle_id: String,
    config: AppConfig,
    handle: tauri::AppHandle,
) -> Result<(), String> {
    let mut configs = get_app_configs(handle.clone()).unwrap_or_default();
    configs.insert(bundle_id.clone(), config);
    if let Some(path) = get_app_settings_path(&handle) {
        if let Ok(content) = serde_json::to_string_pretty(&configs) {
            std::fs::write(path, content).map_err(|e| e.to_string())?;
        }
    }
    #[cfg(target_os = "macos")]
    {
        if let Some(current_app) = engine::get_frontmost_app_bundle_id() {
            if current_app == bundle_id {
                apply_app_config_by_bundle_id(&handle, &current_app);
            }
        }
    }
    Ok(())
}

#[tauri::command]
fn remove_app_config(bundle_id: String, handle: tauri::AppHandle) -> Result<(), String> {
    let mut configs = get_app_configs(handle.clone()).unwrap_or_default();
    configs.remove(&bundle_id);
    if let Some(path) = get_app_settings_path(&handle) {
        if let Ok(content) = serde_json::to_string_pretty(&configs) {
            std::fs::write(path, content).map_err(|e| e.to_string())?;
        }
    }
    #[cfg(target_os = "macos")]
    {
        if let Some(current_app) = engine::get_frontmost_app_bundle_id() {
            if current_app == bundle_id {
                apply_app_config_by_bundle_id(&handle, &current_app);
            }
        }
    }
    Ok(())
}

fn apply_app_config_by_bundle_id(handle: &tauri::AppHandle, bundle_id: &str) {
    let mut applied_config: Option<AppConfig> = None;
    if let Some(path) = get_app_settings_path(handle) {
        if path.exists() {
            if let Ok(content) = std::fs::read_to_string(path) {
                if let Ok(configs) =
                    serde_json::from_str::<std::collections::HashMap<String, AppConfig>>(&content)
                {
                    if let Some(config) = configs.get(bundle_id) {
                        applied_config = Some(config.clone());
                    }
                }
            }
        }
    }

    if let Some(config) = applied_config {
        unsafe {
            engine::vLanguage = config.language;
            engine::vInputType = config.input_type;

            engine::vCodeTable = config.code_table;
            engine::vCheckSpelling = config.check_spelling;
            engine::vUseModernOrthography = config.use_modern_orthography;
            engine::vQuickTelex = config.quick_telex;
            engine::vUseEnglishDictionary = config.use_english_dictionary;
            engine::vUseMacro = config.use_macro;
            engine::vUseMacroInEnglishMode = config.use_macro_in_english_mode;
            engine::vAutoCapsMacro = config.auto_caps_macro;
            engine::vUpperCaseFirstChar = config.upper_case_first_char;
            engine::vQuickStartConsonant = config.quick_start_consonant;
            engine::vQuickEndConsonant = config.quick_end_consonant;
            engine::vCheckProgrammingKeywords = config.check_programming_keywords;
            let order = &config.fsm_priority_order;
            let fsm_order: [i32; 3] = [
                order.get(0).copied().unwrap_or(0),
                order.get(1).copied().unwrap_or(2),
                order.get(2).copied().unwrap_or(1),
            ];
            engine::set_fsm_priority_order(&fsm_order);
            engine::startNewSession();
            engine::code_table_changed();
        }
        update_tray_icon(handle);
        let settings = get_settings();
        let _ = handle.emit("settings-changed", settings);
    } else {
        load_settings_from_disk(handle);
        unsafe {
            engine::startNewSession();
            engine::code_table_changed();
        }
        update_tray_icon(handle);
        let settings = get_settings();
        let _ = handle.emit("settings-changed", settings);
    }
}

#[tauri::command]
fn disable_hotkeys(disable: bool) {
    unsafe {
        engine::vDisableHotkeys = if disable { 1 } else { 0 };
    }
}

#[tauri::command]
fn trigger_quick_convert() {
    rust_onQuickConvert();
}

fn update_dock_icon(app: &tauri::AppHandle) {
    #[cfg(target_os = "macos")]
    {
        let main_visible = app.get_webview_window("main").and_then(|w| w.is_visible().ok()).unwrap_or(false);
        let onboarding_visible = app.get_webview_window("onboarding").and_then(|w| w.is_visible().ok()).unwrap_or(false);
        if main_visible || onboarding_visible {
            let _ = app.set_activation_policy(tauri::ActivationPolicy::Regular);
        } else {
            let _ = app.set_activation_policy(tauri::ActivationPolicy::Accessory);
        }
    }
}

fn get_system_sync_password() -> String {
    option_env!("VNKEY_SYNC_PASSWORD").unwrap_or("VNKey@SecureSync2026").to_string()
}

#[tauri::command]
async fn sync_to_cloud(
    account_id: String,
    access_key: String,
    secret_key: String,
    bucket_name: String,
) -> Result<(), String> {
    let creds = cloud_sync::CloudCredentials {
        account_id,
        access_key,
        secret_key,
        bucket_name,
    };
    cloud_sync::upload_sync_data(&creds, &get_system_sync_password()).await.map_err(|e| e.to_string())
}

#[tauri::command]
async fn sync_from_cloud(
    account_id: String,
    access_key: String,
    secret_key: String,
    bucket_name: String,
) -> Result<(), String> {
    let creds = cloud_sync::CloudCredentials {
        account_id,
        access_key,
        secret_key,
        bucket_name,
    };
    cloud_sync::download_sync_data(&creds, &get_system_sync_password()).await.map_err(|e| e.to_string())
}

#[tauri::command]
fn get_kv(key: String) -> Option<String> {
    db::db_get_kv(&key)
}

#[tauri::command]
async fn set_kv(key: String, value: String) -> Result<(), String> {
    db::db_set_kv(&key, &value);
    Ok(())
}

#[tauri::command]
async fn start_google_auth() -> Result<google_sync::DeviceAuthResponse, String> {
    google_sync::start_device_auth().await.map_err(|e| e.to_string())
}

#[tauri::command]
async fn poll_google_auth(device_code: String) -> Result<google_sync::TokenResponse, String> {
    google_sync::poll_device_auth(&device_code).await
}

#[tauri::command]
async fn start_local_auth_server(app_handle: tauri::AppHandle, code_verifier: String) -> Result<(), String> {
    use tokio::net::TcpListener;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tauri::Emitter;

    tokio::spawn(async move {
        let listener = match TcpListener::bind("127.0.0.1:12558").await {
            Ok(l) => l,
            Err(e) => {
                eprintln!("Failed to bind local server: {}", e);
                return;
            }
        };

        if let Ok((mut socket, _)) = listener.accept().await {
            let mut buf = [0; 4096];
            let n = socket.read(&mut buf).await.unwrap_or(0);
            let request = String::from_utf8_lossy(&buf[..n]);
            
            let html_response;
            let mut code = None;

            if let Some(path_line) = request.lines().next() {
                if path_line.starts_with("GET /callback") {
                    let url_parts: Vec<&str> = path_line.split_whitespace().collect();
                    if url_parts.len() > 1 {
                        let path = url_parts[1];
                        if let Some(query_start) = path.find('?') {
                            let query = &path[query_start + 1..];
                            for pair in query.split('&') {
                                let parts: Vec<&str> = pair.split('=').collect();
                                if parts.len() == 2 && parts[0] == "code" {
                                    if let Ok(decoded_data_cow) = urlencoding::decode(parts[1]) {
                                        code = Some(decoded_data_cow.into_owned());
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if let Some(ref auth_code) = code {
                match google_sync::exchange_auth_code(auth_code, &code_verifier).await {
                    Ok(token_data) => {
                        db::db_set_kv("gdriveAccessToken", &token_data.access_token);
                        if let Some(ref refresh) = token_data.refresh_token {
                            db::db_set_kv("gdriveRefreshToken", refresh);
                        }
                        let _ = app_handle.emit("gdrive_web_auth_success", ());
                        
                        html_response = "<!DOCTYPE html>\
                                         <html>\
                                         <head>\
                                         <title>Xác thực thành công</title>\
                                         <style>body { font-family: sans-serif; text-align: center; padding: 50px; background-color: #0b0f19; color: #f3f4f6; } h1 { color: #10b981; } p { color: #9ca3af; }</style>\
                                         </head>\
                                         <body>\
                                         <h1>✓ Liên kết thành công!</h1>\
                                         <p>Bạn đã liên kết tài khoản Google Drive với ứng dụng VNKey thành công.</p>\
                                         <p>Có thể đóng trình duyệt này và quay lại sử dụng ứng dụng.</p>\
                                         <script>setTimeout(() => window.close(), 3000);</script>\
                                         </body>\
                                         </html>".to_string();
                    }
                    Err(err_msg) => {
                        let safe_err = err_msg.replace('<', "&lt;").replace('>', "&gt;");
                        html_response = format!("<!DOCTYPE html>\
                                         <html>\
                                         <head>\
                                         <title>Xác thực thất bại</title>\
                                         <style>body {{ font-family: sans-serif; text-align: center; padding: 50px; background-color: #0b0f19; color: #f3f4f6; }} h1 {{ color: #ef4444; }} p {{ color: #9ca3af; }}</style>\
                                         </head>\
                                         <body>\
                                         <h1>✗ Liên kết thất bại!</h1>\
                                         <p>Lỗi trong quá trình trao đổi token với Google:</p>\
                                         <p style='color:#f87171;'>{}</p>\
                                         <p>Vui lòng đóng trình duyệt này và thử lại từ ứng dụng.</p>\
                                         </body>\
                                         </html>", safe_err);
                    }
                }
            } else {
                html_response = "<!DOCTYPE html>\
                                 <html>\
                                 <head>\
                                 <title>Lỗi</title>\
                                 <style>body { font-family: sans-serif; text-align: center; padding: 50px; background-color: #0b0f19; color: #f3f4f6; } h1 { color: #ef4444; } p { color: #9ca3af; }</style>\
                                 </head>\
                                 <body>\
                                 <h1>✗ Yêu cầu không hợp lệ</h1>\
                                 <p>Không nhận được mã xác thực (code) từ Google.</p>\
                                 </body>\
                                 </html>".to_string();
            }

            let response = format!("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n{}", html_response);
            let _ = socket.write_all(response.as_bytes()).await;
            let _ = socket.flush().await;
        }
    });
    Ok(())
}
#[tauri::command]
async fn get_google_client_id() -> Result<String, String> {
    google_sync::get_client_id()
}

#[tauri::command]
async fn sync_to_gdrive() -> Result<(), String> {
    google_sync::upload_sync_data_gdrive(&get_system_sync_password()).await
}

#[tauri::command]
async fn sync_from_gdrive() -> Result<(), String> {
    google_sync::download_sync_data_gdrive(&get_system_sync_password()).await
}

static LAST_SYNC_REQUEST: AtomicU64 = AtomicU64::new(0);

fn auto_sync_to_cloud() {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64;
    LAST_SYNC_REQUEST.store(now, Ordering::SeqCst);

    tauri::async_runtime::spawn(async move {
        // Debounce for 5 seconds
        tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
        
        let last_request = LAST_SYNC_REQUEST.load(Ordering::SeqCst);
        if last_request != now {
            // Another sync request was made during our sleep. Abort this one.
            return;
        }

        // Find out which sync method the user prefers
        let sync_method = db::db_get_kv("syncMethod").unwrap_or_else(|| "r2".to_string());
        let sync_password = get_system_sync_password();

        if sync_method == "gdrive" {
            if let Err(e) = google_sync::upload_sync_data_gdrive(&sync_password).await {
                eprintln!("Auto sync to Google Drive failed: {}", e);
            }
        } else {
            // Default to R2
            let account_id = db::db_get_kv("cloudAccountId").unwrap_or_default();
            let access_key = db::db_get_kv("cloudAccessKey").unwrap_or_default();
            let secret_key = db::db_get_kv("cloudSecretKey").unwrap_or_default();
            let bucket_name = db::db_get_kv("cloudBucketName").unwrap_or_default();
            if account_id.is_empty() || access_key.is_empty() || secret_key.is_empty() || bucket_name.is_empty() {
                return;
            }
            let creds = cloud_sync::CloudCredentials {
                account_id,
                access_key,
                secret_key,
                bucket_name,
            };
            if let Err(e) = cloud_sync::upload_sync_data(&creds, &sync_password).await {
                eprintln!("Auto sync to R2 failed: {}", e);
            }
        }
    });
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Initialize C++ input engine
    engine::init();

    #[cfg(target_os = "macos")]
    {
        if engine::is_another_instance_running() {
            engine::activate_other_instance();
            std::process::exit(0);
        }
    }

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .on_window_event(|window, event| match event {
            tauri::WindowEvent::CloseRequested { api, .. } => {
                let label = window.label();
                if label == "main" || label == "clipboard" {
                    api.prevent_close();
                    let _ = window.hide();
                    update_dock_icon(window.app_handle());
                }
            }
            tauri::WindowEvent::Destroyed => {
                update_dock_icon(window.app_handle());
            }
            tauri::WindowEvent::Focused(true) => {
                let label = window.label();
                if label == "main" {
                    let handle = window.app_handle();
                    load_settings_from_disk(handle);
                    let settings = get_settings();
                    let _ = handle.emit("settings-changed", settings);
                }
            }
            _ => {}
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            update_settings,
            reset_settings,
            disable_hotkeys,
            list_macros,
            upsert_macro,
            remove_macro,
            convert_text,
            check_accessibility,
            request_accessibility,
            trigger_quick_convert,
            get_english_dictionary,
            save_custom_english_words,
            get_vietnamese_dictionary,
            save_custom_vietnamese_words,
            quit,
            get_clipboard_items,
            remove_clipboard_item,
            clear_clipboard_history,
            strip_clipboard_formatting,
            paste_clipboard_item,
            toggle_clipboard_picker_window,
            hide_clipboard_picker_window,
            get_app_configs,
            save_app_config,
            remove_app_config,
            get_running_applications,
            get_application_info_by_path,
            get_application_info_by_bundle_id,
            get_application_info_by_name,
            sync_to_cloud,
            sync_from_cloud,
            get_kv,
            set_kv,
            start_google_auth,
            poll_google_auth,
            start_local_auth_server,
            get_google_client_id,
            sync_to_gdrive,
            sync_from_gdrive,
            get_programming_keywords,
            save_custom_programming_keywords
        ])
        .setup(|app| {
            let handle = app.handle().clone();
            let _ = APP_HANDLE.set(handle.clone());
            
            if let Ok(app_config_dir) = handle.path().app_config_dir() {
                let _ = db::init_db(&app_config_dir);
            }

            load_clipboard_from_disk(&handle);
            LAST_CHANGE_COUNT.store(
                engine::clipboard_get_change_count(),
                std::sync::atomic::Ordering::Relaxed,
            );

            let handle_poll = handle.clone();
            std::thread::spawn(move || {
                let mut last_app: Option<String> = None;
                loop {
                    std::thread::sleep(std::time::Duration::from_millis(250));

                    #[cfg(target_os = "macos")]
                    {
                        if let Some(current_app) = engine::get_frontmost_app_bundle_id() {
                            let should_update = match &last_app {
                                Some(last) => last != &current_app,
                                None => true,
                            };
                            if should_update {
                                last_app = Some(current_app.clone());
                                apply_app_config_by_bundle_id(&handle_poll, &current_app);
                            }
                        }
                    }

                    if CLIPBOARD_ENABLED.load(std::sync::atomic::Ordering::Relaxed) {
                        let change_count = engine::clipboard_get_change_count();
                        let last_count = LAST_CHANGE_COUNT.load(std::sync::atomic::Ordering::Relaxed);
                        if change_count != last_count {
                            LAST_CHANGE_COUNT.store(change_count, std::sync::atomic::Ordering::Relaxed);
                            if !IS_INTERNAL_COPY.load(std::sync::atomic::Ordering::Relaxed) {
                                if !engine::clipboard_is_sensitive() {
                                    if let Err(e) = process_new_clipboard_item(&handle_poll) {
                                        eprintln!("Error processing clipboard item: {:?}", e);
                                    }
                                }
                            }
                        }
                    }

                }
            });

            let has_access = unsafe { engine::is_accessibility_granted() };
            if has_access {
                load_settings_from_disk(&handle);
                load_macros_from_disk(&handle);
                load_english_dict_from_disk(&handle);
                load_vietnamese_dict_from_disk(&handle);
                load_programming_keywords_from_disk(&handle);
                unsafe {
                    engine::start_event_tap();
                }
                if OPEN_PANEL_ON_START.load(std::sync::atomic::Ordering::Relaxed) {
                    if let Some(main_win) = handle.get_webview_window("main") {
                        let _ = main_win.show();
                    }
                }
                if let Some(hud) = handle.get_webview_window("hud") {
                    let _ = hud.set_ignore_cursor_events(true);
                    // Configure HUD window via native macOS API
                    #[cfg(target_os = "macos")]
                    {
                        let hud_for_ns = hud.clone();
                        let _ = hud.run_on_main_thread(move || {
                            if let Ok(ns_win) = hud_for_ns.ns_window() {
                                unsafe { engine::macos_configure_hud_window(ns_win); }
                            }
                        });
                    }
                }
            } else {
                // Show onboarding window
                if let Some(onboarding_win) = handle.get_webview_window("onboarding") {
                    let _ = onboarding_win.show();
                }
                update_dock_icon(&handle);

                // Spawn background thread to check for accessibility grant
                let handle_clone = handle.clone();
                std::thread::spawn(move || {
                    loop {
                        std::thread::sleep(std::time::Duration::from_millis(1500));
                        if unsafe { engine::is_accessibility_granted() } {
                            let handle_clone_2 = handle_clone.clone();
                            // 1. Load configuration and dictionaries in the background thread
                            load_settings_from_disk(&handle_clone_2);
                            load_macros_from_disk(&handle_clone_2);
                            load_english_dict_from_disk(&handle_clone_2);
                            load_vietnamese_dict_from_disk(&handle_clone_2);
                            load_programming_keywords_from_disk(&handle_clone_2);

                            // 2. Dispatch UI operations and start event tap to the main thread
                            let _ = handle_clone.run_on_main_thread(move || {
                                unsafe {
                                    engine::start_event_tap();
                                }
                                update_tray_icon(&handle_clone_2);

                                // Close onboarding window, show main window
                                if let Some(onboarding_win) =
                                    handle_clone_2.get_webview_window("onboarding")
                                {
                                    let _ = onboarding_win.close();
                                }
                                // Always show and focus the main window (control panel) on first run after accessibility is granted
                                if let Some(main_win) = handle_clone_2.get_webview_window("main") {
                                    let _ = main_win.show();
                                    let _ = main_win.set_focus();
                                }
                                update_dock_icon(&handle_clone_2);

                                let _ = handle_clone_2.emit("accessibility-granted", ());
                            });
                            break;
                        }
                    }
                });
            }

            let tray = TrayIconBuilder::new()
                .icon(get_tray_icon(unsafe { engine::vLanguage }))
                .icon_as_template(GRAY_ICON.load(std::sync::atomic::Ordering::Relaxed))
                .menu(&build_tray_menu(&handle))
                .on_menu_event(|app, event| {
                    match event.id().as_ref() {
                        "request_accessibility" => {
                            if let Some(onboarding_win) = app.get_webview_window("onboarding") {
                                let _ = onboarding_win
                                    .show()
                                    .and_then(|_| onboarding_win.set_focus());
                            }
                            unsafe {
                                engine::request_accessibility_permission();
                            }
                        }
                        "toggle_language" => {
                            unsafe {
                                engine::vLanguage = if engine::vLanguage == 1 { 0 } else { 1 };
                                engine::startNewSession();
                            }
                            update_tray_icon(app);
                            notify_frontend();
                        }
                        "clipboard_history" => {
                            toggle_clipboard_picker(app);
                        }
                        "control_panel" => {
                            if let Some(window) = app.get_webview_window("main") {
                                let _ = window.show().and_then(|_| window.set_focus());
                                let _ = window.emit("show-tab", 0);
                            }
                        }
                        "macro_settings" => {
                            if let Some(window) = app.get_webview_window("main") {
                                let _ = window.show().and_then(|_| window.set_focus());
                                let _ = window.emit("show-tab", 1);
                            }
                        }
                        "convert_tool" => {
                            if let Some(window) = app.get_webview_window("main") {
                                let _ = window.show().and_then(|_| window.set_focus());
                                let _ = window.emit("show-tab", 2);
                            }
                        }
                        "about" => {
                            if let Some(window) = app.get_webview_window("main") {
                                let _ = window.show().and_then(|_| window.set_focus());
                                let _ = window.emit("show-tab", 4);
                            }
                        }
                        "check_updates" => {
                            if let Some(window) = app.get_webview_window("main") {
                                let _ = window.show().and_then(|_| window.set_focus());
                                let _ = window.emit("check-updates-manually", ());
                            }
                        }
                        "quick_convert" => {
                            rust_onQuickConvert();
                        }
                        "quit" => {
                            unsafe {
                                engine::stop_event_tap();
                            }
                            app.exit(0);
                        }
                        id if id.starts_with("input_type_") => {
                            if let Ok(idx) = id.trim_start_matches("input_type_").parse::<i32>() {
                                unsafe {
                                    engine::vInputType = idx;
                                    engine::startNewSession();
                                }
                                update_tray_icon(app);
                                notify_frontend();
                            }
                        }
                        id if id.starts_with("code_table_") => {
                            if let Ok(idx) = id.trim_start_matches("code_table_").parse::<i32>() {
                                unsafe {
                                    engine::vCodeTable = idx;
                                    engine::startNewSession();
                                }
                                engine::code_table_changed();
                                update_tray_icon(app);
                                notify_frontend();
                            }
                        }
                        _ => {}
                    }
                    update_dock_icon(app);
                })
                .build(app)?;

            let _ = TRAY_ICON.set(tray);

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[no_mangle]
pub extern "C" fn set_is_internal_copy(val: bool) {
    IS_INTERNAL_COPY.store(val, std::sync::atomic::Ordering::Relaxed);
}


