pub mod spelling;
pub mod telex;
pub mod tone;
pub mod vni;

use tone::ToneStyle;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputMethod {
    Off,
    Telex,
    Vni,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EngineResult {
    /// Let the key pass through normally. The engine appends it to the buffer.
    Keep,
    /// Swallow the key, send backspaces to delete the current buffer, and inject the new text.
    Replace { backspaces: usize, text: String },
    /// Reset the active buffer. Let the key pass through normally.
    Reset,
}

pub fn minimal_suffix_edit(old: &str, new: &str) -> (usize, String) {
    let common_prefix_len = old
        .chars()
        .zip(new.chars())
        .take_while(|(old_char, new_char)| old_char == new_char)
        .count();
    let backspaces = old.chars().count() - common_prefix_len;
    let text = new.chars().skip(common_prefix_len).collect();
    (backspaces, text)
}

fn replace_result(old: &str, new: String) -> EngineResult {
    let (backspaces, text) = minimal_suffix_edit(old, &new);
    EngineResult::Replace { backspaces, text }
}

#[derive(Debug, Clone)]
pub struct EngineConfig {
    pub method: InputMethod,
    pub tone_style: ToneStyle,
    pub spelling_check: bool,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            method: InputMethod::Telex,
            tone_style: ToneStyle::Modern,
            spelling_check: true,
        }
    }
}

pub struct Engine {
    buffer: String,
    raw_buffer: String,
    config: EngineConfig,
}

impl Engine {
    pub fn new(config: EngineConfig) -> Self {
        Self {
            buffer: String::new(),
            raw_buffer: String::new(),
            config,
        }
    }

    pub fn update_config(&mut self, config: EngineConfig) {
        self.config = config;
        self.reset();
    }

    pub fn reset(&mut self) {
        self.buffer.clear();
        self.raw_buffer.clear();
    }

    pub fn get_buffer(&self) -> &str {
        &self.buffer
    }
}

fn is_completed_syllable_sequence(text: &str) -> bool {
    if text.is_empty() {
        return true;
    }
    if let Some(_) = spelling::Syllable::parse(text) {
        return true;
    }
    let chars: Vec<char> = text.chars().collect();
    let len = chars.len();
    let start = len.saturating_sub(7);
    for i in (start..len).rev() {
        let left: String = chars[0..i].iter().collect();
        let right: String = chars[i..].iter().collect();
        if is_completed_syllable_sequence(&left) && spelling::Syllable::parse(&right).is_some() {
            return true;
        }
    }
    false
}

fn is_syllable_prefix(text: &str) -> bool {
    if text.is_empty() {
        return true;
    }
    if let Some(_) = spelling::Syllable::parse(text) {
        return true;
    }
    let lower = text.to_lowercase();
    if spelling::INITIAL_CONSONANTS.iter().any(|&ic| ic.starts_with(&lower)) {
        return true;
    }
    false
}

fn check_spelling_validity(buffer: &str) -> bool {
    if buffer.is_empty() {
        return true;
    }
    if let Some(_) = spelling::Syllable::parse(buffer) {
        return true;
    }
    let chars: Vec<char> = buffer.chars().collect();
    let len = chars.len();
    let start = len.saturating_sub(7);
    for i in (start..len).rev() {
        let left: String = chars[0..i].iter().collect();
        let right: String = chars[i..].iter().collect();
        if (left.is_empty() || is_completed_syllable_sequence(&left)) && is_syllable_prefix(&right) {
            return true;
        }
    }
    false
}
fn is_intermediate_syllable(syl: &spelling::Syllable) -> bool {
    if !syl.final_consonant.is_empty() {
        let vg = syl.vowels.join("");
        return matches!(vg.as_str(), "ie" | "uă" | "ue" | "uye");
    }
    false
}

impl Engine {
    pub fn process_key(&mut self, c: char) -> EngineResult {
        if self.config.method == InputMethod::Off {
            return EngineResult::Keep;
        }

        // Retroactive intermediate spelling check failure check
        if !self.buffer.is_empty() && c.is_alphanumeric() {
            if let Some(syl) = spelling::Syllable::parse(&self.buffer) {
                if is_intermediate_syllable(&syl) {
                    let lower_c = c.to_ascii_lowercase();
                    let is_control = match self.config.method {
                        InputMethod::Telex => "aseojwdfxrz".contains(lower_c),
                        InputMethod::Vni => "123456789".contains(lower_c),
                        InputMethod::Off => false,
                    };
                    if !is_control {
                        if self.buffer == self.raw_buffer {
                            self.reset();
                            self.raw_buffer.push(c);
                            self.buffer.push(c);
                            return EngineResult::Keep;
                        }
                        let old_buffer = self.buffer.clone();
                        self.buffer = self.raw_buffer.clone();
                        let new_word = format!("{}{}", self.raw_buffer, c);
                        self.reset();
                        return replace_result(&old_buffer, new_word);
                    }
                }
            }
        }

        // If it's a spacer / word boundary (Space, Enter, punctuation, etc.)
        if !c.is_alphanumeric() {
            if self.config.spelling_check && !self.buffer.is_empty() {
                if !is_completed_syllable_sequence(&self.buffer) {
                    if self.buffer == self.raw_buffer {
                        self.reset();
                        return EngineResult::Reset;
                    }
                    let old_buffer = self.buffer.clone();
                    self.buffer = self.raw_buffer.clone();
                    let res = replace_result(&old_buffer, self.buffer.clone());
                    self.reset();
                    return res;
                }
            }
            self.reset();
            return EngineResult::Reset;
        }

        let old_buffer = self.buffer.clone();
        self.raw_buffer.push(c);

        let process_result = match self.config.method {
            InputMethod::Telex => telex::process_telex(
                &self.buffer,
                c,
                self.config.tone_style,
                self.config.spelling_check,
            ),
            InputMethod::Vni => vni::process_vni(
                &self.buffer,
                c,
                self.config.tone_style,
                self.config.spelling_check,
            ),
            InputMethod::Off => None,
        };

        if let Some(new_word) = process_result {
            // Replace the buffer
            self.buffer = new_word.clone();
            
            // Check if the modified word is spelling-wise valid (skip for Telex escapes)
            let lower_c = c.to_ascii_lowercase();
            let is_escape = new_word.to_lowercase().ends_with(lower_c);
            if is_escape {
                self.raw_buffer = new_word.clone();
            }
            if !is_escape && self.config.spelling_check && !self.buffer.is_empty() {
                let is_valid = check_spelling_validity(&self.buffer);
                if !is_valid {
                    if self.buffer == self.raw_buffer {
                        self.reset();
                        return EngineResult::Reset;
                    }
                    self.buffer = self.raw_buffer.clone();
                    let res = replace_result(&old_buffer, self.buffer.clone());
                    self.reset();
                    return res;
                }
            }
            
            replace_result(&old_buffer, new_word)
        } else {
            // No transformation. If it's a valid character, append to buffer
            self.buffer.push(c);
            
            // Auto-reconstruct if it changes syllable layout (e.g. gir + a -> giả)
            let mut did_reconstruct = false;
            if c.is_alphabetic() {
                if let Some(syl) = spelling::Syllable::parse(&self.buffer) {
                    let casing = spelling::Casing::detect(&self.buffer);
                    let reconstructed = syl.to_string(self.config.tone_style, casing);
                    if reconstructed != self.buffer {
                        self.buffer = reconstructed.clone();
                        did_reconstruct = true;
                    }
                }
            }
            
            // Check if the newly appended state is spelling-wise valid
            if self.config.spelling_check && !self.buffer.is_empty() {
                let is_valid = check_spelling_validity(&self.buffer);
                if !is_valid {
                    if self.buffer == self.raw_buffer {
                        self.reset();
                        return EngineResult::Reset;
                    }
                    self.buffer = self.raw_buffer.clone();
                    let res = replace_result(&old_buffer, self.buffer.clone());
                    self.reset();
                    return res;
                }
            }
            
            if did_reconstruct {
                replace_result(&old_buffer, self.buffer.clone())
            } else {
                EngineResult::Keep
            }
        }
    }
}
