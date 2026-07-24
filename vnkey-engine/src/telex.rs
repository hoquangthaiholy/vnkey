use crate::spelling::{Syllable, Tone, Casing};
use crate::tone::ToneStyle;

/// Process a Telex keypress on the current word buffer.
/// Returns the new reconstructed word if processed, or None if the key should be treated normally.
pub fn process_telex(
    buffer: &str,
    raw_buffer: &str,
    new_char: char,
    tone_style: ToneStyle,
    spelling_check: bool,
) -> Option<String> {
    let lower_c = new_char.to_ascii_lowercase();

    // 1. Handle Tone Marks: s, f, r, x, j, z
    if "sfrxjz".contains(lower_c) {
        if let Some(mut syl) = Syllable::parse(buffer) {
            let tone = match lower_c {
                's' => Tone::Sac,
                'f' => Tone::Huyen,
                'r' => Tone::Hoi,
                'x' => Tone::Nga,
                'j' => Tone::Nang,
                'z' => Tone::None,
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
    if lower_c == 'd' && buffer.chars().count() == 1 {
        let last_char = buffer.chars().last().unwrap();
        let last_lower = last_char.to_lowercase().next().unwrap_or(last_char);
        if last_lower == 'd' {
            return Some(if last_char.is_uppercase() { "Đ".to_string() } else { "đ".to_string() });
        } else if last_lower == 'đ' {
            return Some(if last_char.is_uppercase() { "DD".to_string() } else { "dd".to_string() });
        }
    }

    // 3. Handle Accent Modifiers: a, e, o, d, w
    if "aeodw".contains(lower_c) && !buffer.is_empty() {
        let mut modified = false;
        let mut updated_buffer = buffer.to_string();
        
        // Try syllable-based free modifier first
        if let Some(mut syl) = Syllable::parse(buffer) {
            match lower_c {
                'd' => {
                    if syl.initial == "d" {
                        syl.initial = "đ".to_string();
                        modified = true;
                    } else if syl.initial == "đ" {
                        syl.initial = "d".to_string();
                        let casing = Casing::detect(buffer);
                        let mut restored = syl.to_string(tone_style, casing);
                        restored.push(new_char);
                        return Some(restored);
                    }
                }
                'o' => {
                    let mut consecutive_modified = false;
                    if syl.final_consonant.is_empty() {
                        if let Some(last_v) = syl.vowels.last_mut() {
                            if *last_v == "o" {
                                *last_v = "ô";
                                modified = true;
                                consecutive_modified = true;
                            } else if *last_v == "ô" {
                                *last_v = "o";
                                let casing = Casing::detect(buffer);
                                let mut restored = syl.to_string(tone_style, casing);
                                restored.push(new_char);
                                return Some(restored);
                            }
                        }
                    }
                    if !consecutive_modified {
                        let next_word = format!("{}{}", buffer, new_char);
                        if Syllable::parse(&next_word).is_none() {
                            for v in &mut syl.vowels {
                                if *v == "o" {
                                    *v = "ô";
                                    modified = true;
                                    break;
                                } else if *v == "ô" {
                                    *v = "o";
                                    let casing = Casing::detect(buffer);
                                    let mut restored = syl.to_string(tone_style, casing);
                                    restored.push(new_char);
                                    return Some(restored);
                                }
                            }
                        }
                    }
                }
                'e' => {
                    let mut consecutive_modified = false;
                    if syl.final_consonant.is_empty() {
                        if let Some(last_v) = syl.vowels.last_mut() {
                            if *last_v == "e" {
                                *last_v = "ê";
                                modified = true;
                                consecutive_modified = true;
                            } else if *last_v == "ê" {
                                *last_v = "e";
                                let casing = Casing::detect(buffer);
                                let mut restored = syl.to_string(tone_style, casing);
                                restored.push(new_char);
                                return Some(restored);
                            }
                        }
                    }
                    if !consecutive_modified {
                        let next_word = format!("{}{}", buffer, new_char);
                        if Syllable::parse(&next_word).is_none() {
                            for v in &mut syl.vowels {
                                if *v == "e" {
                                    *v = "ê";
                                    modified = true;
                                    break;
                                } else if *v == "ê" {
                                    *v = "e";
                                    let casing = Casing::detect(buffer);
                                    let mut restored = syl.to_string(tone_style, casing);
                                    restored.push(new_char);
                                    return Some(restored);
                                }
                            }
                        }
                    }
                }
                'a' => {
                    let mut consecutive_modified = false;
                    if syl.final_consonant.is_empty() {
                        if let Some(last_v) = syl.vowels.last_mut() {
                            if *last_v == "a" {
                                *last_v = "â";
                                modified = true;
                                consecutive_modified = true;
                            } else if *last_v == "â" {
                                *last_v = "a";
                                let casing = Casing::detect(buffer);
                                let mut restored = syl.to_string(tone_style, casing);
                                restored.push(new_char);
                                return Some(restored);
                            }
                        }
                    }
                    if !consecutive_modified {
                        let next_word = format!("{}{}", buffer, new_char);
                        if Syllable::parse(&next_word).is_none() {
                            for v in &mut syl.vowels {
                                if *v == "a" {
                                    *v = "â";
                                    modified = true;
                                    break;
                                } else if *v == "ă" {
                                    *v = "â";
                                    modified = true;
                                    break;
                                } else if *v == "â" {
                                    *v = "a";
                                    let casing = Casing::detect(buffer);
                                    let mut restored = syl.to_string(tone_style, casing);
                                    restored.push(new_char);
                                    return Some(restored);
                                }
                            }
                        }
                    }
                }
                'w' => {
                    // Check for toggle-off/escape first
                    if syl.vowels == vec!["ư", "ơ"] {
                        syl.vowels = vec!["u", "o"];
                        let casing = Casing::detect(buffer);
                        let mut restored = syl.to_string(tone_style, casing);
                        restored.push(new_char);
                        return Some(restored);
                    } else if syl.vowels == vec!["ư", "ơ", "i"] {
                        syl.vowels = vec!["u", "o", "i"];
                        let casing = Casing::detect(buffer);
                        let mut restored = syl.to_string(tone_style, casing);
                        restored.push(new_char);
                        return Some(restored);
                    } else if syl.vowels == vec!["ư", "a"] {
                        syl.vowels = vec!["u", "a"];
                        let casing = Casing::detect(buffer);
                        let mut restored = syl.to_string(tone_style, casing);
                        restored.push(new_char);
                        return Some(restored);
                    } else if syl.vowels == vec!["ơ", "i"] {
                        syl.vowels = vec!["o", "i"];
                        let casing = Casing::detect(buffer);
                        let mut restored = syl.to_string(tone_style, casing);
                        restored.push(new_char);
                        return Some(restored);
                    } else if syl.vowels == vec!["ư", "i"] {
                        syl.vowels = vec!["u", "i"];
                        let casing = Casing::detect(buffer);
                        let mut restored = syl.to_string(tone_style, casing);
                        restored.push(new_char);
                        return Some(restored);
                    } else if syl.vowels == vec!["ơ"] {
                        syl.vowels = vec!["o"];
                        let casing = Casing::detect(buffer);
                        let mut restored = syl.to_string(tone_style, casing);
                        restored.push(new_char);
                        return Some(restored);
                    } else if syl.vowels == vec!["ư"] {
                        if raw_buffer.to_lowercase() == "ww" {
                            let first_w = if buffer.chars().next() == Some('Ư') { 'W' } else { 'w' };
                            return Some(first_w.to_string());
                        } else {
                            syl.vowels = vec!["u"];
                            let casing = Casing::detect(buffer);
                            let mut restored = syl.to_string(tone_style, casing);
                            restored.push(new_char);
                            return Some(restored);
                        }
                    } else if syl.vowels == vec!["ư", "ơ", "u"] {
                        syl.vowels = vec!["u", "o", "u"];
                        let casing = Casing::detect(buffer);
                        let mut restored = syl.to_string(tone_style, casing);
                        restored.push(new_char);
                        return Some(restored);
                    } else if syl.vowels == vec!["o", "ă"] {
                        syl.vowels = vec!["o", "a"];
                        let casing = Casing::detect(buffer);
                        let mut restored = syl.to_string(tone_style, casing);
                        restored.push(new_char);
                        return Some(restored);
                    } else if syl.vowels == vec!["ă"] {
                        syl.vowels = vec!["a"];
                        let casing = Casing::detect(buffer);
                        let mut restored = syl.to_string(tone_style, casing);
                        restored.push(new_char);
                        return Some(restored);
                    }

                    // Otherwise apply horn modifications
                    if syl.vowels == vec!["u", "o"] {
                        syl.vowels = vec!["ư", "ơ"];
                        modified = true;
                    } else if syl.vowels == vec!["ư", "o"] || syl.vowels == vec!["u", "ơ"] {
                        syl.vowels = vec!["ư", "ơ"];
                        modified = true;
                    } else if syl.vowels == vec!["u", "a"] {
                        syl.vowels = vec!["ư", "a"];
                        modified = true;
                    } else if syl.vowels == vec!["o", "a"] {
                        syl.vowels = vec!["o", "ă"];
                        modified = true;
                    } else if syl.vowels == vec!["u", "o", "u"] {
                        syl.vowels = vec!["ư", "ơ", "u"];
                        modified = true;
                    } else if syl.vowels == vec!["ư", "o", "u"] || syl.vowels == vec!["u", "ơ", "u"] {
                        syl.vowels = vec!["ư", "ơ", "u"];
                        modified = true;
                    } else if syl.vowels == vec!["u", "o", "i"] {
                        syl.vowels = vec!["ư", "ơ", "i"];
                        modified = true;
                    } else if syl.vowels == vec!["ư", "o", "i"] || syl.vowels == vec!["u", "ơ", "i"] {
                        syl.vowels = vec!["ư", "ơ", "i"];
                        modified = true;
                    } else if syl.vowels == vec!["o", "i"] {
                        syl.vowels = vec!["ơ", "i"];
                        modified = true;
                    } else if syl.vowels == vec!["u", "i"] {
                        syl.vowels = vec!["ư", "i"];
                        modified = true;
                    } else if syl.vowels == vec!["o"] {
                        syl.vowels = vec!["ơ"];
                        modified = true;
                    } else if syl.vowels == vec!["u"] {
                        syl.vowels = vec!["ư"];
                        modified = true;
                    } else if syl.vowels == vec!["a"] {
                        syl.vowels = vec!["ă"];
                        modified = true;
                    } else if syl.vowels == vec!["â"] {
                        syl.vowels = vec!["ă"];
                        modified = true;
                    }
                }
                _ => {}
            }
            if modified {
                let casing = Casing::detect(buffer);
                updated_buffer = syl.to_string(tone_style, casing);
            }
        }
        
        // If syllable-based modifier didn't apply, fall back to raw adjacent modifier
        if !modified {
            let last_char = buffer.chars().last().unwrap();
            let last_lower = last_char.to_lowercase().next().unwrap_or(last_char);
            
            match lower_c {
                'a' => {
                    if last_lower == 'a' {
                        updated_buffer.pop();
                        updated_buffer.push(if last_char.is_uppercase() { 'Â' } else { 'â' });
                        modified = true;
                    } else if last_lower == 'â' {
                        updated_buffer.pop();
                        let a_char = if last_char.is_uppercase() { 'A' } else { 'a' };
                        updated_buffer.push(a_char);
                        updated_buffer.push(new_char);
                        return Some(updated_buffer);
                    }
                }
                'e' => {
                    if last_lower == 'e' {
                        updated_buffer.pop();
                        updated_buffer.push(if last_char.is_uppercase() { 'Ê' } else { 'ê' });
                        modified = true;
                    } else if last_lower == 'ê' {
                        updated_buffer.pop();
                        let e_char = if last_char.is_uppercase() { 'E' } else { 'e' };
                        updated_buffer.push(e_char);
                        updated_buffer.push(new_char);
                        return Some(updated_buffer);
                    }
                }
                'o' => {
                    if last_lower == 'o' {
                        updated_buffer.pop();
                        updated_buffer.push(if last_char.is_uppercase() { 'Ô' } else { 'ô' });
                        modified = true;
                    } else if last_lower == 'ô' {
                        updated_buffer.pop();
                        let o_char = if last_char.is_uppercase() { 'O' } else { 'o' };
                        updated_buffer.push(o_char);
                        updated_buffer.push(new_char);
                        return Some(updated_buffer);
                    }
                }
                'd' => {
                    if last_lower == 'd' {
                        updated_buffer.pop();
                        updated_buffer.push(if last_char.is_uppercase() { 'Đ' } else { 'đ' });
                        modified = true;
                    } else if last_lower == 'đ' {
                        updated_buffer.pop();
                        let d_char = if last_char.is_uppercase() { 'D' } else { 'd' };
                        updated_buffer.push(d_char);
                        updated_buffer.push(new_char);
                        return Some(updated_buffer);
                    }
                }
                'w' => {
                    if last_lower == 'ă' {
                        updated_buffer.pop();
                        let a_char = if last_char.is_uppercase() { 'A' } else { 'a' };
                        updated_buffer.push(a_char);
                        updated_buffer.push(new_char);
                        return Some(updated_buffer);
                    } else if last_lower == 'ơ' {
                        let chars_vec: Vec<char> = buffer.chars().collect();
                        if chars_vec.len() >= 2 && chars_vec[chars_vec.len() - 2].to_ascii_lowercase() == 'ư' {
                            updated_buffer.pop();
                            updated_buffer.pop();
                            let u_char = chars_vec[chars_vec.len() - 2];
                            let o_char = last_char;
                            updated_buffer.push(if u_char.is_uppercase() { 'U' } else { 'u' });
                            updated_buffer.push(if o_char.is_uppercase() { 'O' } else { 'o' });
                            updated_buffer.push(new_char);
                            return Some(updated_buffer);
                        } else {
                            updated_buffer.pop();
                            updated_buffer.push(if last_char.is_uppercase() { 'O' } else { 'o' });
                            updated_buffer.push(new_char);
                            return Some(updated_buffer);
                        }
                    } else if last_lower == 'ư' {
                        updated_buffer.pop();
                        updated_buffer.push(if last_char.is_uppercase() { 'U' } else { 'u' });
                        updated_buffer.push(new_char);
                        return Some(updated_buffer);
                    } else if last_lower == 'u' {
                        let chars_vec: Vec<char> = buffer.chars().collect();
                        if chars_vec.len() >= 2 && chars_vec[chars_vec.len() - 2].to_ascii_lowercase() == 'o' {
                            updated_buffer.pop();
                            updated_buffer.pop();
                            let u_char = chars_vec[chars_vec.len() - 2];
                            updated_buffer.push(if u_char.is_uppercase() { 'Ư' } else { 'ư' });
                            updated_buffer.push(if last_char.is_uppercase() { 'Ơ' } else { 'ơ' });
                        } else {
                            updated_buffer.pop();
                            updated_buffer.push(if last_char.is_uppercase() { 'Ư' } else { 'ư' });
                        }
                        modified = true;
                    } else if last_lower == 'o' {
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
                    } else if last_lower == 'a' {
                        updated_buffer.pop();
                        updated_buffer.push(if last_char.is_uppercase() { 'Ă' } else { 'ă' });
                        modified = true;
                    }
                }
                _ => {}
            }
        }

        if modified {
            // After applying either modifier, make sure tone is preserved if the new word is a valid syllable
            if let Some(syl) = Syllable::parse(&updated_buffer) {
                let casing = Casing::detect(&updated_buffer);
                return Some(syl.to_string(tone_style, casing));
            }
            return Some(updated_buffer);
        }
    }

    // 4. Special standalone 'w' -> 'ư'
    if lower_c == 'w' && buffer.is_empty() {
        return Some(if new_char.is_uppercase() { "Ư".to_string() } else { "ư".to_string() });
    }

    None
}
