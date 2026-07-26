use serde::{Deserialize, Serialize};

fn default_one() -> i32 { 1 }
fn default_zero() -> i32 { 0 }
fn default_panel_hotkey() -> i32 { 0x50000C23 }
fn default_fsm_priority_order() -> Vec<i32> { vec![2, 0, 1] }

#[derive(Serialize, Deserialize, Debug, Clone)]
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
