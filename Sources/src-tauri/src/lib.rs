mod engine;

use std::fs::{create_dir_all, File};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::OnceLock;
use tauri::menu::{
    CheckMenuItemBuilder, Menu, MenuItemBuilder, PredefinedMenuItem, SubmenuBuilder,
};
use tauri::tray::{TrayIcon, TrayIconBuilder};
use tauri::{AppHandle, Emitter, Manager};

static APP_HANDLE: OnceLock<AppHandle> = OnceLock::new();
static TRAY_ICON: OnceLock<TrayIcon<tauri::Wry>> = OnceLock::new();
static GRAY_ICON: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);

static CLIPBOARD_ENABLED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
static CLIPBOARD_PIN_ON_TOP: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
static CLIPBOARD_AUTO_HIDE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
static CLIPBOARD_MAX_ITEMS: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(30);
static CLIPBOARD_HOTKEY: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(0x76000109); // Default: Ctrl + V
static LAST_CHANGE_COUNT: std::sync::atomic::AtomicI64 = std::sync::atomic::AtomicI64::new(0);

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

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct Settings {
    pub language: i32,
    pub input_type: i32,
    pub free_mark: i32,
    pub code_table: i32,
    pub switch_key_status: i32,
    pub check_spelling: i32,
    pub use_modern_orthography: i32,
    pub quick_telex: i32,
    pub restore_if_wrong_spelling: i32,
    pub use_english_dictionary: i32,
    pub fix_recommend_browser: i32,
    pub use_macro: i32,
    pub use_macro_in_english_mode: i32,
    pub auto_caps_macro: i32,
    pub use_smart_switch_key: i32,
    pub upper_case_first_char: i32,
    pub temp_off_spelling: i32,
    pub allow_consonant_zfwj: i32,
    pub quick_start_consonant: i32,
    pub quick_end_consonant: i32,
    pub remember_code: i32,
    pub other_language: i32,
    pub temp_off_vnkey: i32,
    pub send_key_step_by_step: i32,
    pub fix_chromium_browser: i32,
    pub perform_layout_compat: i32,
    pub gray_icon: i32,
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
}

use std::sync::Mutex;

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
    default_words: Vec<String>,
    custom_words: Vec<String>,
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
    let mut items = Vec::new();
    if let Some(path) = get_clipboard_path(handle) {
        if path.exists() {
            if let Ok(mut file) = File::open(path) {
                let mut content = String::new();
                if file.read_to_string(&mut content).is_ok() {
                    if let Ok(loaded) = serde_json::from_str::<Vec<ClipboardItem>>(&content) {
                        items = loaded;
                    }
                }
            }
        }
    }
    if let Some(history_mutex) = CLIPBOARD_HISTORY.get() {
        let mut history = history_mutex.lock().unwrap();
        *history = items;
    } else {
        let _ = CLIPBOARD_HISTORY.set(Mutex::new(items));
    }
}

fn save_clipboard_to_disk_internal(handle: &tauri::AppHandle, items: &[ClipboardItem]) {
    if let Some(path) = get_clipboard_path(handle) {
        if let Ok(content) = serde_json::to_string_pretty(items) {
            if let Ok(mut file) = File::create(path) {
                let _ = file.write_all(content.as_bytes());
            }
        }
    }
}

fn process_new_clipboard_item(handle: &tauri::AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(target_os = "macos")]
    {
        // 1. Read app info
        let app_name = engine::get_frontmost_app_name();
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
                            if let (Some(ref new_p), Some(ref old_p)) = (&new_item.image_path, &item.image_path) {
                                if let (Ok(new_data), Ok(old_data)) = (std::fs::read(new_p), std::fs::read(old_p)) {
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
                    if let (Some(new_img), Some(old_img)) = (&final_item.image_path, &old_item.image_path) {
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
        Settings {
            language: engine::vLanguage,
            input_type: engine::vInputType,
            free_mark: engine::vFreeMark,
            code_table: engine::vCodeTable,
            switch_key_status: switch_key,
            check_spelling: engine::vCheckSpelling,
            use_modern_orthography: engine::vUseModernOrthography,
            quick_telex: engine::vQuickTelex,
            restore_if_wrong_spelling: engine::vRestoreIfWrongSpelling,
            use_english_dictionary: engine::vUseEnglishDictionary,
            fix_recommend_browser: engine::vFixRecommendBrowser,
            use_macro: engine::vUseMacro,
            use_macro_in_english_mode: engine::vUseMacroInEnglishMode,
            auto_caps_macro: engine::vAutoCapsMacro,
            use_smart_switch_key: engine::vUseSmartSwitchKey,
            upper_case_first_char: engine::vUpperCaseFirstChar,
            temp_off_spelling: engine::vTempOffSpelling,
            allow_consonant_zfwj: engine::vAllowConsonantZFWJ,
            quick_start_consonant: engine::vQuickStartConsonant,
            quick_end_consonant: engine::vQuickEndConsonant,
            remember_code: engine::vRememberCode,
            other_language: engine::vOtherLanguage,
            temp_off_vnkey: engine::vTempOffVNKey,
            send_key_step_by_step: engine::vSendKeyStepByStep,
            fix_chromium_browser: engine::vFixChromiumBrowser,
            perform_layout_compat: engine::vPerformLayoutCompat,
            gray_icon: if GRAY_ICON.load(std::sync::atomic::Ordering::Relaxed) { 1 } else { 0 },
            convert_tool_dont_alert: engine::get_convert_tool_dont_alert(),
            convert_tool_to_all_caps: engine::get_convert_tool_to_all_caps(),
            convert_tool_to_all_non_caps: engine::get_convert_tool_to_all_non_caps(),
            convert_tool_to_caps_first_letter: engine::get_convert_tool_to_caps_first_letter(),
            convert_tool_to_caps_each_word: engine::get_convert_tool_to_caps_each_word(),
            convert_tool_remove_mark: engine::get_convert_tool_remove_mark(),
            convert_tool_from_code: engine::get_convert_tool_from_code(),
            convert_tool_to_code: engine::get_convert_tool_to_code(),
            convert_tool_hotkey: convert_hotkey,
            clipboard_enabled: if CLIPBOARD_ENABLED.load(std::sync::atomic::Ordering::Relaxed) { 1 } else { 0 },
            clipboard_pin_on_top: if CLIPBOARD_PIN_ON_TOP.load(std::sync::atomic::Ordering::Relaxed) { 1 } else { 0 },
            clipboard_auto_hide: if CLIPBOARD_AUTO_HIDE.load(std::sync::atomic::Ordering::Relaxed) { 1 } else { 0 },
            clipboard_max_items: CLIPBOARD_MAX_ITEMS.load(std::sync::atomic::Ordering::Relaxed),
            clipboard_hotkey: CLIPBOARD_HOTKEY.load(std::sync::atomic::Ordering::Relaxed),
        }
    }
}

fn get_settings_path(handle: &tauri::AppHandle) -> Option<PathBuf> {
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
        if path.exists() {
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
                            engine::vFreeMark = settings.free_mark;
                            engine::vCodeTable = settings.code_table;
                            engine::vSwitchKeyStatus = switch_key;
                            engine::vCheckSpelling = settings.check_spelling;
                            engine::vUseModernOrthography = settings.use_modern_orthography;
                            engine::vQuickTelex = settings.quick_telex;
                            engine::vRestoreIfWrongSpelling = settings.restore_if_wrong_spelling;
                            engine::vUseEnglishDictionary = settings.use_english_dictionary;
                            engine::vFixRecommendBrowser = settings.fix_recommend_browser;
                            engine::vUseMacro = settings.use_macro;
                            engine::vUseMacroInEnglishMode = settings.use_macro_in_english_mode;
                            engine::vAutoCapsMacro = settings.auto_caps_macro;
                            engine::vUseSmartSwitchKey = settings.use_smart_switch_key;
                            engine::vUpperCaseFirstChar = settings.upper_case_first_char;
                            engine::vTempOffSpelling = settings.temp_off_spelling;
                            engine::vAllowConsonantZFWJ = settings.allow_consonant_zfwj;
                            engine::vQuickStartConsonant = settings.quick_start_consonant;
                            engine::vQuickEndConsonant = settings.quick_end_consonant;
                            engine::vRememberCode = settings.remember_code;
                            engine::vOtherLanguage = settings.other_language;
                            engine::vTempOffVNKey = settings.temp_off_vnkey;
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
                        }
                        GRAY_ICON.store(settings.gray_icon == 1, std::sync::atomic::Ordering::Relaxed);
                        CLIPBOARD_ENABLED.store(settings.clipboard_enabled == 1, std::sync::atomic::Ordering::Relaxed);
                        CLIPBOARD_PIN_ON_TOP.store(settings.clipboard_pin_on_top == 1, std::sync::atomic::Ordering::Relaxed);
                        CLIPBOARD_AUTO_HIDE.store(settings.clipboard_auto_hide == 1, std::sync::atomic::Ordering::Relaxed);
                        CLIPBOARD_MAX_ITEMS.store(settings.clipboard_max_items, std::sync::atomic::Ordering::Relaxed);
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
                    }
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
        engine::vFreeMark = settings.free_mark;
        engine::vCodeTable = settings.code_table;
        engine::vSwitchKeyStatus = settings.switch_key_status;
        engine::vCheckSpelling = settings.check_spelling;
        engine::vUseModernOrthography = settings.use_modern_orthography;
        engine::vQuickTelex = settings.quick_telex;
        engine::vRestoreIfWrongSpelling = settings.restore_if_wrong_spelling;
        engine::vUseEnglishDictionary = settings.use_english_dictionary;
        engine::vFixRecommendBrowser = settings.fix_recommend_browser;
        engine::vUseMacro = settings.use_macro;
        engine::vUseMacroInEnglishMode = settings.use_macro_in_english_mode;
        engine::vAutoCapsMacro = settings.auto_caps_macro;
        engine::vUseSmartSwitchKey = settings.use_smart_switch_key;
        engine::vUpperCaseFirstChar = settings.upper_case_first_char;
        engine::vTempOffSpelling = settings.temp_off_spelling;
        engine::vAllowConsonantZFWJ = settings.allow_consonant_zfwj;
        engine::vQuickStartConsonant = settings.quick_start_consonant;
        engine::vQuickEndConsonant = settings.quick_end_consonant;
        engine::vRememberCode = settings.remember_code;
        engine::vOtherLanguage = settings.other_language;
        engine::vTempOffVNKey = settings.temp_off_vnkey;
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
    if previous_code_table != settings.code_table {
        engine::code_table_changed();
    }
    save_settings_to_disk(&handle, &settings);
    update_tray_icon(&handle);
}

fn get_macro_path(handle: &tauri::AppHandle) -> Option<PathBuf> {
    let mut path = handle.path().app_config_dir().ok()?;
    create_dir_all(&path).ok()?;
    path.push("macros.dat");
    Some(path)
}

fn save_macros_to_disk(handle: &tauri::AppHandle) {
    if let Some(path) = get_macro_path(handle) {
        engine::save_macros(&path.to_string_lossy());
    }
}

fn load_macros_from_disk(handle: &tauri::AppHandle) {
    if let Some(path) = get_macro_path(handle) {
        if path.exists() {
            engine::load_macros(&path.to_string_lossy());
        }
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
                engine::set_custom_english_words(&content);
            }
        } else {
            let default_content = "# Từ tùy chỉnh của bạn. Danh sách mặc định được tích hợp trong VNKey.\n";
            let _ = std::fs::write(&path, default_content);
            engine::set_custom_english_words(default_content);
        }
    }
}

#[tauri::command]
fn get_english_dictionary(handle: tauri::AppHandle) -> Result<EnglishDictionary, String> {
    let custom_content = get_english_dict_path(&handle)
        .and_then(|path| std::fs::read_to_string(path).ok())
        .unwrap_or_default();
    Ok(EnglishDictionary {
        default_words: parse_english_words(&engine::default_english_words()),
        custom_words: parse_english_words(&custom_content),
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
fn save_custom_english_words(words: String, handle: tauri::AppHandle) -> Result<(), String> {
    if let Some(path) = get_english_dict_path(&handle) {
        let normalized = parse_english_words(&words).join("\n");
        std::fs::write(&path, &normalized).map_err(|e| e.to_string())?;
        engine::set_custom_english_words(&normalized);
        Ok(())
    } else {
        Err("Không thể truy cập thư mục cấu hình.".into())
    }
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
        if let Some(png_bytes) = engine::macos_status_icon(is_vietnamese, is_gray) {
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
            _ => {
                match key_code {
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
                }
            }
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
            eprintln!("Failed to build toggle_language menu item with accelerator: {:?}", e);
            CheckMenuItemBuilder::new("Bật Tiếng Việt")
                .id("toggle_language")
                .checked(is_vietnamese)
                .build(handle)
                .unwrap()
        }
    };

    let input_type_menu = SubmenuBuilder::new(handle, "Kiểu gõ").build().unwrap();
    let current_input_type = unsafe { engine::vInputType };
    let it_labels = ["Telex", "VNI", "Simple Telex 1", "Simple Telex 2"];
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
    let mut quick_convert_builder = MenuItemBuilder::new("Chuyển mã nhanh")
        .id("quick_convert");
    if let Some(ref accel) = convert_hotkey_accel {
        quick_convert_builder = quick_convert_builder.accelerator(accel);
    }
    let quick_convert = match quick_convert_builder.build(handle) {
        Ok(item) => item,
        Err(e) => {
            eprintln!("Failed to build quick_convert menu item with accelerator: {:?}", e);
            MenuItemBuilder::new("Chuyển mã nhanh")
                .id("quick_convert")
                .build(handle)
                .unwrap()
        }
    };

    let control_panel = MenuItemBuilder::new("Bảng điều khiển...")
        .id("control_panel")
        .build(handle)
        .unwrap();

    let macro_settings = MenuItemBuilder::new("Gõ tắt...")
        .id("macro_settings")
        .build(handle)
        .unwrap();

    let about = MenuItemBuilder::new("Giới thiệu")
        .id("about")
        .build(handle)
        .unwrap();

    let quit = MenuItemBuilder::new("Thoát")
        .id("quit")
        .build(handle)
        .unwrap();

    let clipboard_hotkey = CLIPBOARD_HOTKEY.load(std::sync::atomic::Ordering::Relaxed);
    let clipboard_hotkey_accel = hotkey_to_accelerator(clipboard_hotkey);
    let mut clipboard_menu_builder = MenuItemBuilder::new("Bảng nhớ...")
        .id("clipboard_history");
    if CLIPBOARD_ENABLED.load(std::sync::atomic::Ordering::Relaxed) {
        if let Some(ref accel) = clipboard_hotkey_accel {
            clipboard_menu_builder = clipboard_menu_builder.accelerator(accel);
        }
    }
    let clipboard_menu = match clipboard_menu_builder.build(handle) {
        Ok(item) => item,
        Err(e) => {
            eprintln!("Failed to build clipboard_history menu item: {:?}", e);
            MenuItemBuilder::new("Bảng nhớ...")
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
    let _ = menu.append(&about);
    let _ = menu.append(&PredefinedMenuItem::separator(handle).unwrap());
    
    let _ = menu.append(&quit);

    menu
}

fn update_tray_icon<R: tauri::Runtime>(handle: &tauri::AppHandle<R>) {
    if let Some(tray) = TRAY_ICON.get() {
        let lang = unsafe { engine::vLanguage };
        let icon = get_tray_icon(lang);
        let _ = tray.set_icon(Some(icon));
        let _ = tray.set_icon_as_template(GRAY_ICON.load(std::sync::atomic::Ordering::Relaxed));
        let menu = build_tray_menu(handle);
        let _ = tray.set_menu(Some(menu));
    }
}

fn notify_frontend() {
    if let Some(handle) = APP_HANDLE.get() {
        let settings = get_settings();
        save_settings_to_disk(handle, &settings);
        let _ = handle.emit("settings-changed", settings);
    }
}

#[no_mangle]
pub extern "C" fn rust_onInputMethodChanged(val: std::os::raw::c_int) {
    unsafe {
        engine::vLanguage = val;
    }
    if let Some(handle) = APP_HANDLE.get() {
        update_tray_icon(handle);
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
pub extern "C" fn rust_onQuickConvert() {
    let success = unsafe { engine::do_quick_convert() };
    if let Some(handle) = APP_HANDLE.get() {
        let _ = handle.emit("quick-convert-result", success);
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Initialize C++ input engine
    engine::init();

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            get_settings,
            update_settings,
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
            quit,
            get_clipboard_items,
            remove_clipboard_item,
            clear_clipboard_history,
            strip_clipboard_formatting,
            paste_clipboard_item,
            toggle_clipboard_picker_window,
            hide_clipboard_picker_window
        ])
        .setup(|app| {
            let handle = app.handle().clone();
            let _ = APP_HANDLE.set(handle.clone());

            load_clipboard_from_disk(&handle);
            LAST_CHANGE_COUNT.store(engine::clipboard_get_change_count(), std::sync::atomic::Ordering::Relaxed);

            let handle_poll = handle.clone();
            std::thread::spawn(move || {
                loop {
                    std::thread::sleep(std::time::Duration::from_millis(250));
                    
                    if !CLIPBOARD_ENABLED.load(std::sync::atomic::Ordering::Relaxed) {
                        continue;
                    }
                    
                    let change_count = engine::clipboard_get_change_count();
                    let last_count = LAST_CHANGE_COUNT.load(std::sync::atomic::Ordering::Relaxed);
                    if change_count != last_count {
                        LAST_CHANGE_COUNT.store(change_count, std::sync::atomic::Ordering::Relaxed);
                        
                        if engine::clipboard_is_sensitive() {
                            continue;
                        }
                        
                        if let Err(e) = process_new_clipboard_item(&handle_poll) {
                            eprintln!("Error processing clipboard item: {:?}", e);
                        }
                    }
                }
            });

            let has_access = unsafe { engine::is_accessibility_granted() };
            if has_access {
                load_settings_from_disk(&handle);
                load_macros_from_disk(&handle);
                load_english_dict_from_disk(&handle);
                unsafe {
                    engine::start_event_tap();
                }
                if let Some(main_win) = handle.get_webview_window("main") {
                    let _ = main_win.show();
                }
            } else {
                // Show onboarding window
                if let Some(onboarding_win) = handle.get_webview_window("onboarding") {
                    let _ = onboarding_win.show();
                }
                
                // Spawn background thread to check for accessibility grant
                let handle_clone = handle.clone();
                std::thread::spawn(move || {
                    loop {
                        std::thread::sleep(std::time::Duration::from_millis(1500));
                        if unsafe { engine::is_accessibility_granted() } {
                            let handle_clone_2 = handle_clone.clone();
                            let _ = handle_clone.run_on_main_thread(move || {
                                load_settings_from_disk(&handle_clone_2);
                                load_macros_from_disk(&handle_clone_2);
                                load_english_dict_from_disk(&handle_clone_2);
                                unsafe {
                                    engine::start_event_tap();
                                }
                                update_tray_icon(&handle_clone_2);
                                
                                // Close onboarding window, show main window
                                if let Some(onboarding_win) = handle_clone_2.get_webview_window("onboarding") {
                                    let _ = onboarding_win.close();
                                }
                                if let Some(main_win) = handle_clone_2.get_webview_window("main") {
                                    let _ = main_win.show();
                                    let _ = main_win.set_focus();
                                }
                                
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
                .on_menu_event(|app, event| match event.id().as_ref() {
                    "request_accessibility" => {
                        if let Some(onboarding_win) = app.get_webview_window("onboarding") {
                            let _ = onboarding_win.show().and_then(|_| onboarding_win.set_focus());
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
                })
                .build(app)?;

            let _ = TRAY_ICON.set(tray);

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
