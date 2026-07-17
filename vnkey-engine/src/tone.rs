
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ToneStyle {
    Modern,
    Classic,
}

/// Find the correct index in the vowels slice to place the tone mark
pub fn find_tone_position(vowels: &[&str], has_final: bool, initial: &str, style: ToneStyle) -> usize {
    let len = vowels.len();
    if len == 0 {
        return 0;
    }
    if len == 1 {
        return 0;
    }

    // Special consonant prefix handling: "qu" and "gi"
    // If initial is "qu", the first 'u' is actually part of the consonant, but it might have been
    // parsed into vowels.
    // Wait, in our Syllable parser, we parsed "qu" as the initial consonant, so vowels starts AFTER "qu".
    // So if initial is "qu" and vowels are ["a"], len is 1, and we return index 0 (which is "a").
    // If initial is "gi" and vowels are ["a"], len is 1, we return index 0 ("a").
    // What if vowels are ["i", "e"] and initial is "g"? That is parsed as initial "g", vowels ["i", "e"].
    // In that case, "gi" is the consonant, so the actual vowels start at index 1 ("e").
    let mut vowel_start_offset = 0;
    let mut adjusted_len = len;

    if initial == "g" && vowels[0] == "i" && len > 1 {
        vowel_start_offset = 1;
        adjusted_len = len - 1;
    }

    if adjusted_len == 1 {
        return vowel_start_offset;
    }

    if adjusted_len == 2 {
        let v1 = vowels[vowel_start_offset];
        let v2 = vowels[vowel_start_offset + 1];

        // "y" in "uy" is the main vowel
        if v1 == "u" && v2 == "y" {
            if style == ToneStyle::Classic {
                return vowel_start_offset; // "u" in "huý"
            } else {
                return vowel_start_offset + 1; // "y" in "húy"
            }
        }

        // Vowels that always take tone on the second vowel (iê, uô, ươ, uâ, oă, yê)
        if (v1 == "i" && v2 == "ê")
            || (v1 == "u" && v2 == "ô")
            || (v1 == "ư" && v2 == "ơ")
            || (v1 == "u" && v2 == "â")
            || (v1 == "o" && v2 == "ă")
            || (v1 == "y" && v2 == "ê")
        {
            return vowel_start_offset + 1;
        }

        // Vowels that shift tone if there is a final consonant (oa, oe, uy, uê, uơ)
        let is_shifting_vowel = (v1 == "o" && (v2 == "a" || v2 == "e"))
            || (v1 == "u" && (v2 == "y" || v2 == "ê" || v2 == "ơ"));

        if is_shifting_vowel {
            if has_final {
                return vowel_start_offset + 1;
            }
            if style == ToneStyle::Classic {
                return vowel_start_offset;
            } else {
                return vowel_start_offset + 1;
            }
        }

        // For all other double vowels (ai, ao, ay, ui, oi, ôi, ơi, ia, ua, ưa, êu)
        // tone is always on the first vowel.
        return vowel_start_offset;
    }

    if adjusted_len == 3 {
        // e.g. "oai", "uôi", "ươu", "uyê"
        // For "uyê", the tone is always placed on the third vowel "ê" (index 2 of adjusted vowels)
        let v1 = vowels[vowel_start_offset];
        let v2 = vowels[vowel_start_offset + 1];
        let v3 = vowels[vowel_start_offset + 2];
        if v1 == "u" && v2 == "y" && v3 == "ê" {
            return vowel_start_offset + 2;
        }

        // Otherwise, tone is placed on the middle vowel (index 1)
        return vowel_start_offset + 1;
    }

    vowel_start_offset
}
