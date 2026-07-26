#[cfg(test)]
mod tests {
    use crate::engine::{
        convert_text, ConvertOptions, EnglishDictionary, InputLanguage, InputMethod,
        KeyEngine, MacroEngine, ProgrammingFSM,
    };


    #[test]
    fn test_key_engine_session() {
        let mut engine = KeyEngine::new();
        engine.language = InputLanguage::Vietnamese;
        engine.input_method = InputMethod::Telex;
        engine.macro_engine.add_macro("vnk", "VNKey Engine");

        assert_eq!(engine.process_key('v'), None);
        assert_eq!(engine.process_key('n'), None);
        assert_eq!(engine.process_key('k'), Some("VNKey Engine".to_string()));
    }

    #[test]
    fn test_macro_engine_add_and_get() {
        let mut engine = MacroEngine::new();
        engine.add_macro("ms", "millisecond");
        assert_eq!(engine.get_macro("ms"), Some(&"millisecond".to_string()));
        assert_eq!(engine.get_macro("unknown"), None);
    }


    #[test]
    fn test_english_dictionary() {
        let dict = EnglishDictionary::new();
        assert!(dict.is_protected_word("password"));
        assert!(dict.is_protected_word("software"));
        assert!(!dict.is_protected_word("tiengviet"));
    }

    #[test]
    fn test_programming_fsm() {
        let fsm = ProgrammingFSM::new();
        assert!(fsm.is_builtin_keyword("function"));
        assert!(fsm.is_valid_programming_identifier("camelCaseVar"));
        assert!(fsm.is_valid_programming_identifier("snake_case_var"));
    }

    #[test]
    fn test_convert_text_remove_accents() {
        let options = ConvertOptions {
            remove_accents: true,
            ..Default::default()
        };
        let input = "Tiếng Việt có dấu";
        let output = convert_text(input, &options);
        assert_eq!(output, "Tieng Viet co dau");
    }

    #[test]
    fn test_convert_text_uppercase() {
        let options = ConvertOptions {
            to_all_caps: true,
            ..Default::default()
        };
        let input = "vnkey xin chào";
        let output = convert_text(input, &options);
        assert_eq!(output, "VNKEY XIN CHÀO");
    }
}

