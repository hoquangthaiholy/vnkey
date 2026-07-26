use std::collections::HashSet;

pub const DEFAULT_ENGLISH_WORDS: &str =
    "password rust issue coffee wrong software framework network browser download website search support workflow feedback dashboard deadline meeting google excel slack chrome youtube facebook instagram twitter microsoft office word powerpoint code vs notion telegram laptop email login logout upload file backend frontend button modal form checkbox dropdown github json http websocket database macos windows linux benchmark median p95 p99 space enter tab ai api cpu gpu wifi bluetooth iphone android docker kubernetes javascript typescript python swift production antivirus free write screen user zoom queue analytics";

pub struct EnglishDictionary {
    protected_words: HashSet<String>,
}

impl EnglishDictionary {
    pub fn new() -> Self {
        let mut dict = Self {
            protected_words: HashSet::new(),
        };
        dict.load_default_words();
        dict
    }

    pub fn load_default_words(&mut self) {
        for word in DEFAULT_ENGLISH_WORDS.split_whitespace() {
            self.protected_words.insert(word.to_lowercase());
        }
    }

    pub fn set_custom_words(&mut self, content: &str) {
        self.protected_words.clear();
        self.load_default_words();
        for word in content.split_whitespace() {
            self.protected_words.insert(word.to_lowercase());
        }
    }

    pub fn is_protected_word(&self, word: &str) -> bool {
        self.protected_words.contains(&word.to_lowercase())
    }

    pub fn has_protected_prefix(&self, prefix: &str) -> bool {
        if prefix.is_empty() {
            return false;
        }
        let prefix_lower = prefix.to_lowercase();
        self.protected_words.iter().any(|w| w.starts_with(&prefix_lower))
    }
}
