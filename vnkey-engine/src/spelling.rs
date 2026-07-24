#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tone {
    None,
    Sac,
    Huyen,
    Hoi,
    Nga,
    Nang,
}

impl Tone {
    pub fn to_char_offset(self) -> usize {
        match self {
            Tone::None => 0,
            Tone::Sac => 1,
            Tone::Huyen => 2,
            Tone::Hoi => 3,
            Tone::Nga => 4,
            Tone::Nang => 5,
        }
    }
}

// Maps standard base vowels to their accented variants (Tone ordered: [None, Sac, Huyen, Hoi, Nga, Nang])
pub const VOWEL_TABLE: &[(&str, &[char])] = &[
    ("a", &['a', 'á', 'à', 'ả', 'ã', 'ạ']),
    ("ă", &['ă', 'ắ', 'ằ', 'ẳ', 'ẵ', 'ặ']),
    ("â", &['â', 'ấ', 'ầ', 'ẩ', 'ẫ', 'ậ']),
    ("e", &['e', 'é', 'è', 'ẻ', 'ẽ', 'ẹ']),
    ("ê", &['ê', 'ế', 'ề', 'ể', 'ễ', 'ệ']),
    ("i", &['i', 'í', 'ì', 'ỉ', 'ĩ', 'ị']),
    ("o", &['o', 'ó', 'ò', 'ỏ', 'õ', 'ọ']),
    ("ô", &['ô', 'ố', 'ồ', 'ổ', 'ỗ', 'ộ']),
    ("ơ", &['ơ', 'ớ', 'ờ', 'ở', 'ỡ', 'ợ']),
    ("u", &['u', 'ú', 'ù', 'ủ', 'ũ', 'ụ']),
    ("ư", &['ư', 'ứ', 'ừ', 'ử', 'ữ', 'ự']),
    ("y", &['y', 'ý', 'ỳ', 'ỷ', 'ỹ', 'ỵ']),
];

// Helper to find a base vowel and its tone from a char
pub fn find_vowel_info(c: char) -> Option<(&'static str, Tone)> {
    let lower_c = c.to_lowercase().next()?;
    for (base, variants) in VOWEL_TABLE {
        for (i, &var) in variants.iter().enumerate() {
            if var == lower_c {
                let tone = match i {
                    0 => Tone::None,
                    1 => Tone::Sac,
                    2 => Tone::Huyen,
                    3 => Tone::Hoi,
                    4 => Tone::Nga,
                    5 => Tone::Nang,
                    _ => Tone::None,
                };
                return Some((*base, tone));
            }
        }
    }
    None
}

// List of all valid initial consonants
pub const INITIAL_CONSONANTS: &[&str] = &[
    "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n", "nh", "ng", "ngh",
    "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x",
    "f", "j", "w", "z", "cl", "cr", "br", "dr", "gr", "fr", "fl", "pr", "pl", "ps",
];

// List of all valid final consonants
pub const FINAL_CONSONANTS: &[&str] = &["c", "ch", "m", "n", "nh", "ng", "p", "t", "k"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Syllable {
    pub initial: String,
    pub vowels: Vec<&'static str>, // base vowels like "o", "a"
    pub final_consonant: String,
    pub tone: Tone,
}

impl Syllable {
    pub fn new() -> Self {
        Self {
            initial: String::new(),
            vowels: Vec::new(),
            final_consonant: String::new(),
            tone: Tone::None,
        }
    }

    /// Parse a lowercase clean string into a Syllable structure.
    /// Returns None if it is definitely not a valid Vietnamese word.
    pub fn parse(input: &str) -> Option<Self> {
        if input.is_empty() {
            return None;
        }

        let mut syl = Syllable::new();
        let chars_vec: Vec<char> = input.chars().collect();
        
        let mut has_gi_start = false;
        let mut gi_tone = Tone::None;
        if chars_vec.len() >= 2 && chars_vec[0].to_ascii_lowercase() == 'g' {
            if let Some((base, tone)) = find_vowel_info(chars_vec[1]) {
                if base == "i" {
                    has_gi_start = true;
                    gi_tone = tone;
                }
            }
        }
        
        let mut has_vowel_after = false;
        if has_gi_start {
            for &c in &chars_vec[2..] {
                if find_vowel_info(c).is_some() {
                    has_vowel_after = true;
                    break;
                }
            }
        }
        
        let remaining_chars;
        
        if has_gi_start {
            if has_vowel_after {
                syl.initial = "gi".to_string();
                remaining_chars = &chars_vec[2..];
                if gi_tone != Tone::None {
                    syl.tone = gi_tone;
                }
            } else {
                syl.initial = "g".to_string();
                remaining_chars = &chars_vec[1..];
            }
        } else {
            let mut temp_initial = String::new();
            let mut idx = 0;
            while idx < chars_vec.len() {
                let c = chars_vec[idx];
                if find_vowel_info(c).is_none() {
                    temp_initial.push(c.to_lowercase().next().unwrap_or(c));
                    idx += 1;
                } else {
                    break;
                }
            }
            if !temp_initial.is_empty() {
                if INITIAL_CONSONANTS.contains(&temp_initial.as_str()) {
                    syl.initial = chars_vec[0..idx].iter().collect();
                } else if temp_initial == "q" && idx < chars_vec.len() && chars_vec[idx].to_ascii_lowercase() == 'u' {
                    syl.initial = chars_vec[0..idx+1].iter().collect();
                    idx += 1;
                } else {
                    return None;
                }
            }
            remaining_chars = &chars_vec[idx..];
        }
        
        let mut chars_iter = remaining_chars.iter().copied().peekable();
        
        // 2. Parse vowels and determine tone
        let mut detected_tone = Tone::None;
        while let Some(&c) = chars_iter.peek() {
            if let Some((base, tone)) = find_vowel_info(c) {
                syl.vowels.push(base);
                if tone != Tone::None {
                    detected_tone = tone;
                }
                chars_iter.next();
            } else {
                break;
            }
        }
        if detected_tone != Tone::None {
            syl.tone = detected_tone;
        }
        
        // 3. Parse final consonant
        let mut temp_final = String::new();
        for c in chars_iter {
            temp_final.push(c.to_ascii_lowercase());
        }
        
        if !temp_final.is_empty() {
            if FINAL_CONSONANTS.contains(&temp_final.as_str()) {
                syl.final_consonant = temp_final;
            } else {
                return None;
            }
        }
        
        // 4. Validate spelling rules
        if syl.vowels.is_empty() {
            return None;
        }
        
        // Validate that the vowel group is a valid Vietnamese vowel combination
        let vowel_group = syl.vowels.join("");
        if !is_valid_vowel_group(&vowel_group) {
            return None;
        }

        

        // Validate gh/ngh/k only with e/ê/i/y
        if !syl.vowels.is_empty() {
            let first_vowel = syl.vowels[0];
            if (syl.initial.to_lowercase() == "gh" || syl.initial.to_lowercase() == "ngh" || syl.initial.to_lowercase() == "k")
                && !(first_vowel == "e" || first_vowel == "ê" || first_vowel == "i" || first_vowel == "y")
            {
                return None;
            }
            // g cannot go with e/ê/y
            if syl.initial.to_lowercase() == "g"
                && (first_vowel == "e" || first_vowel == "ê" || first_vowel == "y")
            {
                return None;
            }
            // ng/c cannot go with e/ê/i/y
            if (syl.initial.to_lowercase() == "ng" || syl.initial.to_lowercase() == "c")
                && (first_vowel == "e" || first_vowel == "ê" || first_vowel == "i" || first_vowel == "y")
            {
                return None;
            }
        }
        
        Some(syl)
    }

    /// Reconstruct the Syllable to a String using the given ToneStyle and Casing.
    pub fn to_string(&self, tone_style: crate::tone::ToneStyle, casing: Casing) -> String {
        use crate::tone::find_tone_position;

        let mut vowels = self.vowels.clone();
        if !self.final_consonant.is_empty() {
            if vowels == vec!["ư", "o"] {
                vowels = vec!["ư", "ơ"];
            } else if vowels == vec!["ư", "o", "i"] {
                vowels = vec!["ư", "ơ", "i"];
            } else if vowels == vec!["u", "ơ"] {
                vowels = vec!["ư", "ơ"];
            } else if vowels == vec!["u", "ơ", "i"] {
                vowels = vec!["ư", "ơ", "i"];
            }
        }

        let tone_pos = find_tone_position(&vowels, !self.final_consonant.is_empty(), &self.initial, tone_style);

        let mut vowel_str = String::new();
        for (i, &v) in vowels.iter().enumerate() {
            let tone_to_apply = if i == tone_pos { self.tone } else { Tone::None };
            
            // Find the character with the applied tone
            let c = if let Some(row) = VOWEL_TABLE.iter().find(|(b, _)| *b == v) {
                row.1[tone_to_apply.to_char_offset()]
            } else {
                v.chars().next().unwrap_or(' ')
            };
            vowel_str.push(c);
        }

        let combined = format!("{}{}{}", self.initial, vowel_str, self.final_consonant);

        // Apply casing
        match casing {
            Casing::Lowercase => combined,
            Casing::Capitalized => {
                let mut chars = combined.chars();
                if let Some(first) = chars.next() {
                    // special case for 'đ' / 'Đ'
                    let first_cap = if first == 'đ' {
                        'Đ'
                    } else {
                        first.to_uppercase().next().unwrap_or(first)
                    };
                    format!("{}{}", first_cap, chars.collect::<String>())
                } else {
                    combined
                }
            }
            Casing::Uppercase => {
                combined.chars().map(|c| {
                    if c == 'đ' {
                        'Đ'
                    } else if c == 'â' {
                        'Â'
                    } else if c == 'ă' {
                        'Ă'
                    } else if c == 'ê' {
                        'Ê'
                    } else if c == 'ô' {
                        'Ô'
                    } else if c == 'ơ' {
                        'Ơ'
                    } else if c == 'ư' {
                        'Ư'
                    } else {
                        c.to_uppercase().next().unwrap_or(c)
                    }
                }).collect()
            }
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Casing {
    Lowercase,
    Capitalized,
    Uppercase,
}

impl Casing {
    pub fn detect(input: &str) -> Self {
        if input.is_empty() {
            return Casing::Lowercase;
        }
        let chars: Vec<char> = input.chars().collect();
        let is_all_upper = chars.iter().all(|c| c.is_uppercase() || !c.is_alphabetic());
        if is_all_upper {
            return Casing::Uppercase;
        }
        if chars[0].is_uppercase() {
            return Casing::Capitalized;
        }
        Casing::Lowercase
    }
}

pub fn is_valid_vowel_group(vg: &str) -> bool {
    matches!(
        vg,
        "a" | "ă" | "â" | "e" | "ê" | "i" | "o" | "ô" | "ơ" | "u" | "ư" | "y"
            | "ai" | "ao" | "au" | "ay" | "âu" | "ây"
            | "eo" | "êu"
            | "ia" | "iê" | "io" | "iu" | "ie" | "ieu"
            | "oa" | "oă" | "oe" | "oi" | "oo" | "ôô" | "ôi" | "ơi"
            | "ua" | "uâ" | "uê" | "uô" | "uơ" | "ui" | "uy" | "uo" | "uou" | "uoi" | "uă" | "ue"
            | "ưa" | "ưi" | "ươ" | "ưu" | "ưo" | "ưoi" | "ưou"
            | "ya" | "yê" | "yu" | "ye" | "yeu"
            | "iêu" | "yêu"
            | "oai" | "oao" | "oay" | "oeo"
            | "uai" | "uân" | "uây" | "uôi" | "ươi" | "ươu" | "uyê" | "uya" | "uyu" | "uye"
    )
}
