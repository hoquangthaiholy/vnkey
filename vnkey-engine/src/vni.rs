use crate::spelling::{Syllable, Tone, Casing};
use crate::tone::ToneStyle;

/// Process a VNI keypress on the current word buffer.
/// Returns the new reconstructed word if processed, or None if the key should be treated normally.
pub fn process_vni(
    buffer: &str,
    new_char: char,
    tone_style: ToneStyle,
    spelling_check: bool,
) -> Option<String> {
    if !new_char.is_ascii_digit() {
        return None;
    }

    let digit = new_char;

    // 1. Handle Tone Marks: 1, 2, 3, 4, 5, 0
    if "123450".contains(digit) {
        if let Some(mut syl) = Syllable::parse(buffer) {
            let tone = match digit {
                '1' => Tone::Sac,
                '2' => Tone::Huyen,
                '3' => Tone::Hoi,
                '4' => Tone::Nga,
                '5' => Tone::Nang,
                '0' => Tone::None,
                _ => Tone::None,
            };

            if spelling_check && !syl.final_consonant.is_empty() {
                let fc = syl.final_consonant.as_str();
                if (fc == "c" || fc == "ch" || fc == "p" || fc == "t")
                    && tone != Tone::Sac
                    && tone != Tone::Nang
                    && tone != Tone::None
                {
                    return None;
                }
            }

            if syl.tone == tone {
                syl.tone = Tone::None;
                let casing = Casing::detect(buffer);
                let mut restored = syl.to_string(tone_style, casing);
                restored.push(new_char);
                return Some(restored);
            } else {
                syl.tone = tone;
                let casing = Casing::detect(buffer);
                return Some(syl.to_string(tone_style, casing));
            }
        }
    }

    // 2. Handle no-vowel d/đ modifier case
    if digit == '9' && buffer.chars().count() == 1 {
        let last_char = buffer.chars().last().unwrap();
        let last_lower = last_char.to_lowercase().next().unwrap_or(last_char);
        if last_lower == 'd' {
            return Some(if last_char.is_uppercase() { "Đ".to_string() } else { "đ".to_string() });
        } else if last_lower == 'đ' {
            return Some(if last_char.is_uppercase() { "D9".to_string() } else { "d9".to_string() });
        }
    }

    // 3. Handle Accent Modifiers: 6, 7, 8, 9
    if "6789".contains(digit) && !buffer.is_empty() {
        let mut modified = false;
        let mut updated_buffer = buffer.to_string();

        // Try syllable-based free modifier first
        if let Some(mut syl) = Syllable::parse(buffer) {
            match digit {
                '9' => {
                    if syl.initial == "d" {
                        syl.initial = "đ".to_string();
                        modified = true;
                    } else if syl.initial == "đ" {
                        syl.initial = "d".to_string();
                        modified = true;
                    }
                }
                '6' => {
                    for v in &mut syl.vowels {
                        if *v == "o" {
                            *v = "ô";
                            modified = true;
                            break;
                        } else if *v == "ô" {
                            *v = "o";
                            modified = true;
                            break;
                        } else if *v == "e" {
                            *v = "ê";
                            modified = true;
                            break;
                        } else if *v == "ê" {
                            *v = "e";
                            modified = true;
                            break;
                        } else if *v == "a" {
                            *v = "â";
                            modified = true;
                            break;
                        } else if *v == "â" {
                            *v = "a";
                            modified = true;
                            break;
                        }
                    }
                }
                '7' => {
                    if syl.vowels == vec!["u", "o"] {
                        syl.vowels = vec!["ư", "ơ"];
                        modified = true;
                    } else if syl.vowels == vec!["ư", "ơ"] {
                        syl.vowels = vec!["u", "o"];
                        modified = true;
                    } else if syl.vowels == vec!["ư", "o"] || syl.vowels == vec!["u", "ơ"] {
                        syl.vowels = vec!["ư", "ơ"];
                        modified = true;
                    } else if syl.vowels == vec!["u", "a"] {
                        syl.vowels = vec!["ư", "a"];
                        modified = true;
                    } else if syl.vowels == vec!["ư", "a"] {
                        syl.vowels = vec!["u", "a"];
                        modified = true;
                    } else if syl.vowels == vec!["u", "o", "i"] {
                        syl.vowels = vec!["ư", "ơ", "i"];
                        modified = true;
                    } else if syl.vowels == vec!["ư", "ơ", "i"] {
                        syl.vowels = vec!["u", "o", "i"];
                        modified = true;
                    } else if syl.vowels == vec!["ư", "o", "i"] || syl.vowels == vec!["u", "ơ", "i"] {
                        syl.vowels = vec!["ư", "ơ", "i"];
                        modified = true;
                    } else if syl.vowels == vec!["u", "o", "u"] {
                        syl.vowels = vec!["ư", "ơ", "u"];
                        modified = true;
                    } else if syl.vowels == vec!["ư", "ơ", "u"] {
                        syl.vowels = vec!["u", "o", "u"];
                        modified = true;
                    } else if syl.vowels == vec!["ư", "o", "u"] || syl.vowels == vec!["u", "ơ", "u"] {
                        syl.vowels = vec!["ư", "ơ", "u"];
                        modified = true;
                    } else if syl.vowels == vec!["o"] {
                        syl.vowels = vec!["ơ"];
                        modified = true;
                    } else if syl.vowels == vec!["ơ"] {
                        syl.vowels = vec!["o"];
                        modified = true;
                    } else if syl.vowels == vec!["u"] {
                        syl.vowels = vec!["ư"];
                        modified = true;
                    } else if syl.vowels == vec!["ư"] {
                        syl.vowels = vec!["u"];
                        modified = true;
                    }
                }
                '8' => {
                    for v in &mut syl.vowels {
                        if *v == "a" {
                            *v = "ă";
                            modified = true;
                            break;
                        } else if *v == "ă" {
                            *v = "a";
                            modified = true;
                            break;
                        }
                    }
                }
                _ => {}
            }
            if modified {
                let casing = Casing::detect(buffer);
                updated_buffer = syl.to_string(tone_style, casing);
            }
        }

        // Fallback to raw adjacent modifier
        if !modified {
            let last_char = buffer.chars().last().unwrap();
            let last_lower = last_char.to_lowercase().next().unwrap_or(last_char);
            match digit {
                '6' => {
                    if last_lower == 'a' {
                        updated_buffer.pop();
                        updated_buffer.push(if last_char.is_uppercase() { 'Â' } else { 'â' });
                        modified = true;
                    } else if last_lower == 'e' {
                        updated_buffer.pop();
                        updated_buffer.push(if last_char.is_uppercase() { 'Ê' } else { 'ê' });
                        modified = true;
                    } else if last_lower == 'o' {
                        updated_buffer.pop();
                        updated_buffer.push(if last_char.is_uppercase() { 'Ô' } else { 'ô' });
                        modified = true;
                    }
                }
                '7' => {
                    if last_lower == 'o' {
                        let chars_vec: Vec<char> = buffer.chars().collect();
                        if chars_vec.len() >= 2 && chars_vec[chars_vec.len() - 2].to_ascii_lowercase() == 'u' {
                            updated_buffer.pop();
                            updated_buffer.pop();
                            let u_char = chars_vec[chars_vec.len() - 2];
                            updated_buffer.push(if u_char.is_uppercase() { 'Ư' } else { 'ư' });
                            updated_buffer.push(if last_char.is_uppercase() { 'Ơ' } else { 'ơ' });
                        } else {
                            updated_buffer.pop();
                            updated_buffer.push(if last_char.is_uppercase() { 'Ơ' } else { 'ơ' });
                        }
                        modified = true;
                    } else if last_lower == 'u' {
                        updated_buffer.pop();
                        updated_buffer.push(if last_char.is_uppercase() { 'Ư' } else { 'ư' });
                        modified = true;
                    }
                }
                '8' => {
                    if last_lower == 'a' {
                        updated_buffer.pop();
                        updated_buffer.push(if last_char.is_uppercase() { 'Ă' } else { 'ă' });
                        modified = true;
                    }
                }
                '9' => {
                    if last_lower == 'd' {
                        updated_buffer.pop();
                        updated_buffer.push(if last_char.is_uppercase() { 'Đ' } else { 'đ' });
                        modified = true;
                    }
                }
                _ => {}
            }
        }

        if modified {
            if let Some(syl) = Syllable::parse(&updated_buffer) {
                let casing = Casing::detect(&updated_buffer);
                return Some(syl.to_string(tone_style, casing));
            }
            return Some(updated_buffer);
        }
    }

    None
}
