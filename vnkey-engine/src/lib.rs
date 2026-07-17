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

fn has_tone_or_modifier(syl: &spelling::Syllable) -> bool {
    if syl.tone != spelling::Tone::None {
        return true;
    }
    if syl.initial.contains('đ') || syl.initial.contains('Đ') {
        return true;
    }
    for v in &syl.vowels {
        if "âăêôơưÂĂÊÔƠƯ".contains(*v) {
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
    /// Process a new keypress.
    pub fn process_key(&mut self, c: char) -> EngineResult {
        if self.config.method == InputMethod::Off {
            return EngineResult::Keep;
        }

        // Auto-split syllable check for compound words typed without space (e.g. liênquan -> liên + quan)
        if !self.buffer.is_empty() && c.is_alphabetic() {
            let lower_c = c.to_ascii_lowercase();
            let is_control = match self.config.method {
                InputMethod::Telex => "aseojwdfxrz".contains(lower_c),
                InputMethod::Vni => "123456789".contains(lower_c),
                InputMethod::Off => false,
            };
            if !is_control {
                if let Some(syl) = spelling::Syllable::parse(&self.buffer) {
                    // Only auto-split if the current syllable contains Vietnamese diacritics
                    if !syl.vowels.is_empty() && has_tone_or_modifier(&syl) {
                        let next_word = format!("{}{}", self.buffer, c);
                        if spelling::Syllable::parse(&next_word).is_none() {
                            let c_str = lower_c.to_string();
                            let is_valid_start = spelling::INITIAL_CONSONANTS.iter().any(|&ic| ic.starts_with(&c_str));
                            if is_valid_start {
                                self.reset();
                            }
                        }
                    }
                }
            }
        }

        // If it's a spacer / word boundary (Space, Enter, punctuation, etc.)
        if !c.is_alphanumeric() {
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
                let is_valid = if let Some(syl) = spelling::Syllable::parse(&self.buffer) {
                    !is_intermediate_syllable(&syl)
                } else {
                    let lower_buf = self.buffer.to_lowercase();
                    spelling::INITIAL_CONSONANTS.iter().any(|&ic| ic.starts_with(&lower_buf))
                };
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
                let is_valid = if let Some(syl) = spelling::Syllable::parse(&self.buffer) {
                    !is_intermediate_syllable(&syl)
                } else {
                    // Check if self.buffer is a prefix of any valid initial consonant
                    let lower_buf = self.buffer.to_lowercase();
                    spelling::INITIAL_CONSONANTS.iter().any(|&ic| ic.starts_with(&lower_buf))
                };
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
