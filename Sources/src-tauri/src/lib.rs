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

#[derive(serde::Serialize, serde::Deserialize, Clone)]
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
            let default_content = "# Thêm các từ tiếng Anh cần bảo vệ vào đây (mỗi dòng một từ hoặc cách nhau bằng dấu cách)\n# Ví dụ:\n# source\n# rust\n# test\n";
            let _ = std::fs::write(&path, default_content);
            engine::set_custom_english_words(default_content);
        }
    }
}

#[tauri::command]
fn get_custom_english_words(handle: tauri::AppHandle) -> Result<String, String> {
    if let Some(path) = get_english_dict_path(&handle) {
        if path.exists() {
            std::fs::read_to_string(&path).map_err(|e| e.to_string())
        } else {
            Ok(String::new())
        }
    } else {
        Err("Không thể truy cập thư mục cấu hình.".into())
    }
}

#[tauri::command]
fn save_custom_english_words(words: String, handle: tauri::AppHandle) -> Result<(), String> {
    if let Some(path) = get_english_dict_path(&handle) {
        std::fs::write(&path, &words).map_err(|e| e.to_string())?;
        engine::set_custom_english_words(&words);
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
    let toggle_lang = CheckMenuItemBuilder::new("Bật Tiếng Việt")
        .id("toggle_language")
        .checked(is_vietnamese)
        .build(handle)
        .unwrap();

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

    let current_code_table = unsafe { engine::vCodeTable };

    let mnu_unicode = CheckMenuItemBuilder::new("Unicode dựng sẵn")
        .id("code_table_0")
        .checked(current_code_table == 0)
        .build(handle)
        .unwrap();

    let mnu_tcvn = CheckMenuItemBuilder::new("TCVN3 (ABC)")
        .id("code_table_1")
        .checked(current_code_table == 1)
        .build(handle)
        .unwrap();

    let mnu_vni_windows = CheckMenuItemBuilder::new("VNI Windows")
        .id("code_table_2")
        .checked(current_code_table == 2)
        .build(handle)
        .unwrap();

    let other_code_menu = SubmenuBuilder::new(handle, "Bảng mã khác").build().unwrap();
    let other_ct_labels = [
        ("Unicode tổ hợp", 3),
        ("Vietnamese Locale CP1258", 4),
    ];
    for (label, i) in other_ct_labels.iter() {
        let checked = current_code_table == *i;
        let item = CheckMenuItemBuilder::new(*label)
            .id(format!("code_table_{}", i))
            .checked(checked)
            .build(handle)
            .unwrap();
        let _ = other_code_menu.append(&item);
    }

    let convert_tool = MenuItemBuilder::new("Công cụ chuyển mã...")
        .id("convert_tool")
        .build(handle)
        .unwrap();

    let quick_convert = MenuItemBuilder::new("Chuyển mã nhanh")
        .id("quick_convert")
        .build(handle)
        .unwrap();

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

    let menu = Menu::new(handle).unwrap();
    let _ = menu.append(&toggle_lang);
    let _ = menu.append(&PredefinedMenuItem::separator(handle).unwrap());
    
    let _ = menu.append(&input_type_menu);
    let _ = menu.append(&PredefinedMenuItem::separator(handle).unwrap());
    
    let _ = menu.append(&mnu_unicode);
    let _ = menu.append(&mnu_tcvn);
    let _ = menu.append(&mnu_vni_windows);
    let _ = menu.append(&other_code_menu);
    let _ = menu.append(&PredefinedMenuItem::separator(handle).unwrap());
    
    let _ = menu.append(&convert_tool);
    let _ = menu.append(&quick_convert);
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
            get_custom_english_words,
            save_custom_english_words,
            quit
        ])
        .setup(|app| {
            let handle = app.handle().clone();
            let _ = APP_HANDLE.set(handle.clone());

            let has_access = unsafe { engine::is_accessibility_granted() };
            if has_access {
                load_settings_from_disk(&handle);
                load_macros_from_disk(&handle);
                load_english_dict_from_disk(&handle);
                unsafe {
                    engine::start_event_tap();
                }
            } else {
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
