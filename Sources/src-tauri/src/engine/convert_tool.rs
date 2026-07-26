#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CodeTable {
    Unicode = 0,
    UnicodeCompound = 1,
    TCVN3 = 2,
    VNIWindow = 3,
    VietnameseLocaleCP1258 = 4,
}

pub struct ConvertOptions {
    pub to_all_caps: bool,
    pub to_all_lower: bool,
    pub to_capitalize_words: bool,
    pub remove_accents: bool,
    pub from_code: CodeTable,
    pub to_code: CodeTable,
}

impl Default for ConvertOptions {
    fn default() -> Self {
        Self {
            to_all_caps: false,
            to_all_lower: false,
            to_capitalize_words: false,
            remove_accents: false,
            from_code: CodeTable::Unicode,
            to_code: CodeTable::Unicode,
        }
    }
}

pub fn convert_text(input: &str, options: &ConvertOptions) -> String {
    let mut result = String::with_capacity(input.len());

    for ch in input.chars() {
        let mut processed_ch = ch;

        if options.remove_accents {
            processed_ch = remove_vietnamese_accent(processed_ch);
        }

        if options.to_all_caps {
            processed_ch = processed_ch.to_uppercase().next().unwrap_or(processed_ch);
        } else if options.to_all_lower {
            processed_ch = processed_ch.to_lowercase().next().unwrap_or(processed_ch);
        }

        result.push(processed_ch);
    }

    result
}

fn remove_vietnamese_accent(c: char) -> char {
    match c {
        'à' | 'á' | 'ả' | 'ã' | 'ạ' | 'ă' | 'ằ' | 'ắ' | 'ẳ' | 'ẵ' | 'ặ' | 'â' | 'ầ' | 'ấ' | 'ẩ' | 'ẫ' | 'ậ' => 'a',
        'À' | 'Á' | 'Ả' | 'Ã' | 'Ạ' | 'Ă' | 'Ằ' | 'Ắ' | 'Ẳ' | 'Ẵ' | 'Ặ' | 'Â' | 'Ầ' | 'Ấ' | 'Ẩ' | 'Ẫ' | 'Ậ' => 'A',
        'è' | 'é' | 'ẻ' | 'ẽ' | 'ẹ' | 'ê' | 'ề' | 'ế' | 'ể' | 'ễ' | 'ệ' => 'e',
        'È' | 'É' | 'Ẻ' | 'Ẽ' | 'Ẹ' | 'Ê' | 'Ề' | 'Ế' | 'Ể' | 'Ễ' | 'Ệ' => 'E',
        'ì' | 'í' | 'ỉ' | 'ĩ' | 'ị' => 'i',
        'Ì' | 'Í' | 'Ỉ' | 'Ĩ' | 'Ị' => 'I',
        'ò' | 'ó' | 'ỏ' | 'õ' | 'ọ' | 'ô' | 'ồ' | 'ố' | 'ổ' | 'ỗ' | 'ộ' | 'ơ' | 'ờ' | 'ớ' | 'ở' | 'ỡ' | 'ợ' => 'o',
        'Ò' | 'Ó' | 'Ỏ' | 'Õ' | 'Ọ' | 'Ô' | 'Ồ' | 'Ố' | 'Ổ' | 'Ỗ' | 'Ộ' | 'Ơ' | 'Ờ' | 'Ớ' | 'Ở' | 'Ỡ' | 'Ợ' => 'O',
        'ù' | 'ú' | 'ủ' | 'ũ' | 'ụ' | 'ư' | 'ừ' | 'ứ' | 'ử' | 'ữ' | 'ự' => 'u',
        'Ù' | 'Ú' | 'Ủ' | 'Ũ' | 'Ụ' | 'Ư' | 'Ừ' | 'Ứ' | 'Ử' | 'Ữ' | 'Ự' => 'U',
        'ỳ' | 'ý' | 'ỷ' | 'ỹ' | 'ỵ' => 'y',
        'Ỳ' | 'Ý' | 'Ỷ' | 'Ỹ' | 'Ỵ' => 'Y',
        'đ' => 'd',
        'Đ' => 'D',
        _ => c,
    }
}
