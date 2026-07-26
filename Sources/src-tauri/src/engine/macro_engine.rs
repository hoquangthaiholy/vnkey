use std::collections::HashMap;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MacroEntry {
    pub shortcut: String,
    pub content: String,
}

pub struct MacroEngine {
    macros: HashMap<String, String>,
    #[allow(dead_code)]
    auto_caps: bool,
    #[allow(dead_code)]
    enabled_in_english: bool,
}


impl MacroEngine {
    pub fn new() -> Self {
        Self {
            macros: HashMap::new(),
            auto_caps: true,
            enabled_in_english: false,
        }
    }

    pub fn add_macro(&mut self, shortcut: impl Into<String>, content: impl Into<String>) {
        self.macros.insert(shortcut.into(), content.into());
    }

    pub fn remove_macro(&mut self, shortcut: &str) -> bool {
        self.macros.remove(shortcut).is_some()
    }

    pub fn get_macro(&self, shortcut: &str) -> Option<&String> {
        self.macros.get(shortcut)
    }

    pub fn list_macros(&self) -> Vec<MacroEntry> {
        self.macros
            .iter()
            .map(|(k, v)| MacroEntry {
                shortcut: k.clone(),
                content: v.clone(),
            })
            .collect()
    }

    pub fn clear(&mut self) {
        self.macros.clear();
    }
}
