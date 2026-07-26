use super::{
    convert_tool::CodeTable,
    english_dictionary::EnglishDictionary,
    macro_engine::MacroEngine,
    programming_fsm::ProgrammingFSM,
    vietnamese::VietnameseData,
};


#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputMethod {
    Telex = 0,
    Vni = 1,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputLanguage {
    English = 0,
    Vietnamese = 1,
}

pub struct KeyEngine {
    pub language: InputLanguage,
    pub input_method: InputMethod,
    pub code_table: CodeTable,
    pub check_spelling: bool,
    pub use_modern_orthography: bool,
    pub macro_engine: MacroEngine,
    pub english_dict: EnglishDictionary,
    pub programming_fsm: ProgrammingFSM,
    pub vietnamese_data: VietnameseData,
    buffer: String,
}

impl KeyEngine {
    pub fn new() -> Self {
        Self {
            language: InputLanguage::Vietnamese,
            input_method: InputMethod::Telex,
            code_table: CodeTable::Unicode,
            check_spelling: true,
            use_modern_orthography: true,
            macro_engine: MacroEngine::new(),
            english_dict: EnglishDictionary::new(),
            programming_fsm: ProgrammingFSM::new(),
            vietnamese_data: VietnameseData::new(),
            buffer: String::new(),
        }
    }

    pub fn start_new_session(&mut self) {
        self.buffer.clear();
    }

    pub fn process_key(&mut self, key_char: char) -> Option<String> {
        if self.language == InputLanguage::English {
            self.buffer.push(key_char);
            return None;
        }

        self.buffer.push(key_char);
        
        // Return transformed text if macro or Telex rule applies
        if let Some(macro_val) = self.macro_engine.get_macro(&self.buffer) {
            return Some(macro_val.clone());
        }

        None
    }
}
