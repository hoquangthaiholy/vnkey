use std::collections::HashSet;

pub struct ProgrammingFSM {
    builtin_keywords: HashSet<String>,
    custom_keywords: HashSet<String>,
}

impl ProgrammingFSM {
    pub fn new() -> Self {
        let builtins = vec![
            "if", "else", "elif", "while", "for", "do", "switch", "case", "default",
            "break", "continue", "return", "try", "catch", "finally", "throw", "throws",
            "except", "raise", "with", "as", "import", "export", "from", "yield", "await", "async",
            "const", "let", "var", "function", "def", "class", "struct", "interface", "enum",
            "public", "private", "protected", "static", "final", "abstract", "virtual", "override",
            "volatile", "transient", "synchronized", "native", "extern", "fn", "impl", "trait",
            "type", "mut", "pub", "use", "mod",
            "void", "int", "float", "double", "char", "bool", "boolean", "string", "long", "short",
            "byte", "signed", "unsigned",
            "true", "false", "null", "nil", "undefined", "none", "self", "this", "super",
            "println", "printf", "console", "log", "print", "main", "include", "define",
            "ifndef", "ifdef", "endif", "namespace", "package", "extends", "implements",
            "github", "gitlab", "docker", "kubernetes", "k8s", "redis", "nginx", "mysql",
            "mongodb", "sqlite", "postgres", "postgresql", "react", "vue", "svelte", "angular",
            "electron", "tauri", "nodejs", "npm", "cargo", "pip", "maven", "gradle",
        ];

        let mut builtin_keywords = HashSet::new();
        for k in builtins {
            builtin_keywords.insert(k.to_string());
        }

        Self {
            builtin_keywords,
            custom_keywords: HashSet::new(),
        }
    }

    pub fn set_custom_keywords(&mut self, content: &str) {
        self.custom_keywords.clear();
        for word in content.split_whitespace() {
            self.custom_keywords.insert(word.to_lowercase());
        }
    }

    pub fn is_builtin_keyword(&self, word: &str) -> bool {
        self.builtin_keywords.contains(&word.to_lowercase()) || self.custom_keywords.contains(&word.to_lowercase())
    }

    pub fn is_valid_programming_identifier(&self, word: &str) -> bool {
        if word.is_empty() || word.len() > 50 {
            return false;
        }

        let first_char = word.chars().next().unwrap();
        if first_char.is_ascii_digit() {
            return false;
        }

        let mut has_lower = false;
        let mut has_upper = false;
        let mut has_underscore = false;

        for c in word.chars() {
            if !c.is_ascii_alphanumeric() && c != '_' && c != '$' {
                return false;
            }
            if c.is_ascii_lowercase() {
                has_lower = true;
            }
            if c.is_ascii_uppercase() {
                has_upper = true;
            }
            if c == '_' {
                has_underscore = true;
            }
        }

        if self.is_builtin_keyword(word) {
            return true;
        }

        // CamelCase or snake_case detection
        (has_lower && has_upper) || has_underscore
    }
}
