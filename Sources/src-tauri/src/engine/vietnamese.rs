use std::collections::HashSet;


pub struct VietnameseData {
    pub custom_words: HashSet<String>,
}

impl VietnameseData {
    pub fn new() -> Self {
        Self {
            custom_words: HashSet::new(),
        }
    }

    pub fn set_custom_words(&mut self, content: &str) {
        self.custom_words.clear();
        for word in content.split_whitespace() {
            self.custom_words.insert(word.to_lowercase());
        }
    }

    pub fn is_custom_word(&self, word: &str) -> bool {
        self.custom_words.contains(&word.to_lowercase())
    }
}

pub fn is_vietnamese_vowel(c: char) -> bool {
    matches!(
        c.to_ascii_lowercase(),
        'a' | 'e' | 'i' | 'o' | 'u' | 'y' | 'à' | 'á' | 'ả' | 'ã' | 'ạ'
            | 'ă' | 'ằ' | 'ắ' | 'ẳ' | 'ẵ' | 'ặ' | 'â' | 'ầ' | 'ấ' | 'ẩ' | 'ẫ' | 'ậ'
            | 'è' | 'é' | 'ẻ' | 'ẽ' | 'ẹ' | 'ê' | 'ề' | 'ế' | 'ể' | 'ễ' | 'ệ'
            | 'ì' | 'í' | 'ỉ' | 'ĩ' | 'ị' | 'ò' | 'ó' | 'ỏ' | 'õ' | 'ọ'
            | 'ô' | 'ồ' | 'ố' | 'ổ' | 'ỗ' | 'ộ' | 'ơ' | 'ờ' | 'ớ' | 'ở' | 'ỡ' | 'ợ'
            | 'ù' | 'ú' | 'ủ' | 'ũ' | 'ụ' | 'ư' | 'ừ' | 'ứ' | 'ử' | 'ữ' | 'ự'
            | 'ỳ' | 'ý' | 'ỷ' | 'ỹ' | 'ỵ'
    )
}
