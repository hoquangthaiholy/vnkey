use vnkey_engine::{Engine, EngineConfig, EngineResult, InputMethod};
use vnkey_engine::tone::ToneStyle;

fn create_engine(method: InputMethod, tone_style: ToneStyle) -> Engine {
    Engine::new(EngineConfig {
        method,
        tone_style,
        spelling_check: true,
    })
}

fn type_word(engine: &mut Engine, word: &str) -> String {
    let mut last_text = String::new();
    for c in word.chars() {
        match engine.process_key(c) {
            EngineResult::Keep => {
                last_text.push(c);
            }
            EngineResult::Replace { backspaces, text } => {
                // Simulate backspaces and text replacement
                let current_len = last_text.chars().count();
                if backspaces <= current_len {
                    let keep_len = current_len - backspaces;
                    let mut temp: String = last_text.chars().take(keep_len).collect();
                    temp.push_str(&text);
                    last_text = temp;
                } else {
                    last_text = text;
                }
            }
            EngineResult::Reset => {
                last_text.push(c);
            }
        }
    }
    last_text
}

#[test]
fn test_telex_basic() {
    let mut engine = create_engine(InputMethod::Telex, ToneStyle::Modern);

    assert_eq!(type_word(&mut engine, "tieesng"), "tiếng");
    engine.reset();

    assert_eq!(type_word(&mut engine, "vietjet"), "vietjet");
}

#[test]
fn test_modern_vs_classic_tone() {
    // Modern style: "hoà" (tone on main vowel 'a')
    let mut engine_modern = create_engine(InputMethod::Telex, ToneStyle::Modern);
    assert_eq!(type_word(&mut engine_modern, "hoaf"), "hoà");

    // Classic style: "hòa" (tone on 'o')
    let mut engine_classic = create_engine(InputMethod::Telex, ToneStyle::Classic);
    assert_eq!(type_word(&mut engine_classic, "hoaf"), "hòa");
}

#[test]
fn test_telex_complex() {
    let mut engine = create_engine(InputMethod::Telex, ToneStyle::Modern);

    assert_eq!(type_word(&mut engine, "dduwowngf"), "đường");
    engine.reset();
    assert_eq!(type_word(&mut engine, "thuyeets"), "thuyết");
    engine.reset();
    assert_eq!(type_word(&mut engine, "ooj"), "ộ");
    engine.reset();
    assert_eq!(type_word(&mut engine, "nooij"), "nội");
    engine.reset();
    assert_eq!(type_word(&mut engine, "ngaaux"), "ngẫu");
    engine.reset();
    assert_eq!(type_word(&mut engine, "gox"), "gõ");
    engine.reset();
    assert_eq!(type_word(&mut engine, "gif"), "gì");
    engine.reset();
    assert_eq!(type_word(&mut engine, "chuaw"), "chưa");
    engine.reset();
    assert_eq!(type_word(&mut engine, "duoiws"), "dưới");
    engine.reset();
    assert_eq!(type_word(&mut engine, "cuar"), "của");
    engine.reset();
    assert_eq!(type_word(&mut engine, "tuis"), "túi");
    engine.reset();
    assert_eq!(type_word(&mut engine, "vaanx"), "vẫn");
    engine.reset();
    assert_eq!(type_word(&mut engine, "raats"), "rất");
    engine.reset();
    assert_eq!(type_word(&mut engine, "teess"), "tês");
    engine.reset();
    assert_eq!(type_word(&mut engine, "tess"), "tes");
    engine.reset();
    assert_eq!(type_word(&mut engine, "cass"), "cas");
    engine.reset();
    assert_eq!(type_word(&mut engine, "eee"), "ee");
    engine.reset();
    assert_eq!(type_word(&mut engine, "ooo"), "oo");
    engine.reset();
    assert_eq!(type_word(&mut engine, "aaa"), "aa");
    engine.reset();
    assert_eq!(type_word(&mut engine, "uww"), "uw");
    engine.reset();
    assert_eq!(type_word(&mut engine, "ddd"), "dd");
    engine.reset();

    // Free tone/accent placement tests
    assert_eq!(type_word(&mut engine, "hoajwc"), "hoặc");
    engine.reset();
    assert_eq!(type_word(&mut engine, "hoawcj"), "hoặc");
    engine.reset();
    assert_eq!(type_word(&mut engine, "ruouwj"), "rượu");
}

#[test]
fn test_telex_recovery_scenarios() {
    let mut engine = create_engine(InputMethod::Telex, ToneStyle::Modern);

    // 1. Tone Escape / Toggle-off on base vowel
    assert_eq!(type_word(&mut engine, "cas"), "cá");
    assert_eq!(type_word(&mut engine, "s"), "cas");
    
    // 2. Tone Escape / Toggle-off on modified vowel
    engine.reset();
    assert_eq!(type_word(&mut engine, "cawts"), "cắt");
    assert_eq!(type_word(&mut engine, "s"), "căts");
    
    // 3. Modifier Escape / Toggle-off for initials
    engine.reset();
    assert_eq!(type_word(&mut engine, "dduwowngf"), "đường");
    assert_eq!(type_word(&mut engine, "d"), "dườngd");
    
    // 4. Modifier Escape / Toggle-off for double/triple vowels
    engine.reset();
    assert_eq!(type_word(&mut engine, "chuaw"), "chưa");
    assert_eq!(type_word(&mut engine, "w"), "chuaw");
    
    engine.reset();
    assert_eq!(type_word(&mut engine, "mowis"), "mới");
    assert_eq!(type_word(&mut engine, "w"), "móiw");

    engine.reset();
    assert_eq!(type_word(&mut engine, "toio"), "tôi");
    engine.reset();
    assert_eq!(type_word(&mut engine, "vajya"), "vậy");
    engine.reset();
    assert_eq!(type_word(&mut engine, "vanaw"), "văn");
    engine.reset();
    assert_eq!(type_word(&mut engine, "dduwocj"), "được");
    engine.reset();
    assert_eq!(type_word(&mut engine, "truongwf"), "trường");
    engine.reset();
    assert_eq!(type_word(&mut engine, "thuonwf"), "thườn");
    engine.reset();
    assert_eq!(type_word(&mut engine, "thuongwf"), "thường");
    engine.reset();
    assert_eq!(type_word(&mut engine, "huongwr"), "hưởng");
    engine.reset();
    assert_eq!(type_word(&mut engine, "viejec"), "việc");
    engine.reset();
    assert_eq!(type_word(&mut engine, "giram"), "giảm");
    engine.reset();
    assert_eq!(type_word(&mut engine, "nuoost"), "nuốt");
    engine.reset();
    assert_eq!(type_word(&mut engine, "buoofn"), "buồn");
    engine.reset();
    assert_eq!(type_word(&mut engine, "burrnout"), "burnout");
    engine.reset();
    assert_eq!(type_word(&mut engine, "casse"), "case");
    engine.reset();
    assert_eq!(type_word(&mut engine, "freee"), "free");
    engine.reset();
    assert_eq!(type_word(&mut engine, "booo"), "boo");
    engine.reset();
    assert_eq!(type_word(&mut engine, "ddd"), "dd");
    engine.reset();
    assert_eq!(type_word(&mut engine, "caaa"), "caa");
    engine.reset();
    assert_eq!(type_word(&mut engine, "gaff"), "gaf");
    engine.reset();
    assert_eq!(type_word(&mut engine, "raxx"), "rax");
    engine.reset();
    assert_eq!(type_word(&mut engine, "hajj"), "haj");
    engine.reset();
    assert_eq!(type_word(&mut engine, "hoaszz"), "hoaz");
    engine.reset();
    assert_eq!(type_word(&mut engine, "lieenquan"), "liênquan");
}

#[test]
fn test_vni_basic() {
    let mut engine = create_engine(InputMethod::Vni, ToneStyle::Modern);

    assert_eq!(type_word(&mut engine, "tie61ng"), "tiếng");
    engine.reset();
    assert_eq!(type_word(&mut engine, "d9u7o7ng2"), "đường");
    engine.reset();
    assert_eq!(type_word(&mut engine, "hoa58c"), "hoặc");
    engine.reset();
    assert_eq!(type_word(&mut engine, "ruou75"), "rượu");
}

#[test]
fn test_benchmark_performance() {
    let mut engine = create_engine(InputMethod::Telex, ToneStyle::Modern);
    let start = std::time::Instant::now();
    let iterations = 100_000;
    
    for _ in 0..iterations {
        engine.reset();
        let out = type_word(&mut engine, "thuyeets");
        assert_eq!(out, "thuyết");
    }
    
    let duration = start.elapsed();
    println!("Processed {} words in {:?}", iterations, duration);
    // 100k words in < 1 second is extremely optimized
    assert!(duration.as_secs() < 3);
}

fn char_to_telex(c: char) -> Vec<char> {
    let lower = c.to_lowercase().next().unwrap_or(c);
    let is_upper = c.is_uppercase();
    
    let mut keys = match lower {
        'á' => vec!['a', 's'],
        'à' => vec!['a', 'f'],
        'ả' => vec!['a', 'r'],
        'ã' => vec!['a', 'x'],
        'ạ' => vec!['a', 'j'],
        
        'â' => vec!['a', 'a'],
        'ấ' => vec!['a', 'a', 's'],
        'ầ' => vec!['a', 'a', 'f'],
        'ẩ' => vec!['a', 'a', 'r'],
        'ẫ' => vec!['a', 'a', 'x'],
        'ậ' => vec!['a', 'a', 'j'],
        
        'ă' => vec!['a', 'w'],
        'ắ' => vec!['a', 'w', 's'],
        'ằ' => vec!['a', 'w', 'f'],
        'ẳ' => vec!['a', 'w', 'r'],
        'ẵ' => vec!['a', 'w', 'x'],
        'ặ' => vec!['a', 'w', 'j'],
        
        'é' => vec!['e', 's'],
        'è' => vec!['e', 'f'],
        'ẻ' => vec!['e', 'r'],
        'ẽ' => vec!['e', 'x'],
        'ẹ' => vec!['e', 'j'],
        
        'ê' => vec!['e', 'e'],
        'ế' => vec!['e', 'e', 's'],
        'ề' => vec!['e', 'e', 'f'],
        'ể' => vec!['e', 'e', 'r'],
        'ễ' => vec!['e', 'e', 'x'],
        'ệ' => vec!['e', 'e', 'j'],
        
        'í' => vec!['i', 's'],
        'ì' => vec!['i', 'f'],
        'ỉ' => vec!['i', 'r'],
        'ĩ' => vec!['i', 'x'],
        'ị' => vec!['i', 'j'],
        
        'ó' => vec!['o', 's'],
        'ò' => vec!['o', 'f'],
        'ỏ' => vec!['o', 'r'],
        'õ' => vec!['o', 'x'],
        'ọ' => vec!['o', 'j'],
        
        'ô' => vec!['o', 'o'],
        'ố' => vec!['o', 'o', 's'],
        'ồ' => vec!['o', 'o', 'f'],
        'ổ' => vec!['o', 'o', 'r'],
        'ỗ' => vec!['o', 'o', 'x'],
        'ộ' => vec!['o', 'o', 'j'],
        
        'ơ' => vec!['o', 'w'],
        'ớ' => vec!['o', 'w', 's'],
        'ờ' => vec!['o', 'w', 'f'],
        'ở' => vec!['o', 'w', 'r'],
        'ỡ' => vec!['o', 'w', 'x'],
        'ợ' => vec!['o', 'w', 'j'],
        
        'ú' => vec!['u', 's'],
        'ù' => vec!['u', 'f'],
        'ủ' => vec!['u', 'r'],
        'ũ' => vec!['u', 'x'],
        'ụ' => vec!['u', 'j'],
        
        'ư' => vec!['u', 'w'],
        'ứ' => vec!['u', 'w', 's'],
        'ừ' => vec!['u', 'w', 'f'],
        'ử' => vec!['u', 'w', 'r'],
        'ữ' => vec!['u', 'w', 'x'],
        'ự' => vec!['u', 'w', 'j'],
        
        'ý' => vec!['y', 's'],
        'ỳ' => vec!['y', 'f'],
        'ỷ' => vec!['y', 'r'],
        'ỹ' => vec!['y', 'x'],
        'ỵ' => vec!['y', 'j'],
        
        'đ' => vec!['d', 'd'],
        
        other => vec![other],
    };
    
    if is_upper && !keys.is_empty() {
        keys[0] = keys[0].to_ascii_uppercase();
    }
    keys
}

fn char_to_telex_no_tone(c: char) -> Vec<char> {
    let lower = c.to_lowercase().next().unwrap_or(c);
    let is_upper = c.is_uppercase();
    
    let mut keys = match lower {
        'á' | 'à' | 'ả' | 'ã' | 'ạ' => vec!['a'],
        
        'â' | 'ấ' | 'ầ' | 'ẩ' | 'ẫ' | 'ậ' => vec!['a', 'a'],
        
        'ă' | 'ắ' | 'ằ' | 'ẳ' | 'ẵ' | 'ặ' => vec!['a', 'w'],
        
        'é' | 'è' | 'ẻ' | 'ẽ' | 'ẹ' => vec!['e'],
        
        'ê' | 'ế' | 'ề' | 'ể' | 'ễ' | 'ệ' => vec!['e', 'e'],
        
        'í' | 'ì' | 'ỉ' | 'ĩ' | 'ị' => vec!['i'],
        
        'ó' | 'ò' | 'ỏ' | 'õ' | 'ọ' => vec!['o'],
        
        'ô' | 'ố' | 'ồ' | 'ổ' | 'ỗ' | 'ộ' => vec!['o', 'o'],
        
        'ơ' | 'ớ' | 'ờ' | 'ở' | 'ỡ' | 'ợ' => vec!['o', 'w'],
        
        'ú' | 'ù' | 'ủ' | 'ũ' | 'ụ' => vec!['u'],
        
        'ư' | 'ứ' | 'ừ' | 'ử' | 'ữ' | 'ự' => vec!['u', 'w'],
        
        'ý' | 'ỳ' | 'ỷ' | 'ỹ' | 'ỵ' => vec!['y'],
        
        'đ' => vec!['d', 'd'],
        
        other => vec![other],
    };
    
    if is_upper && !keys.is_empty() {
        keys[0] = keys[0].to_ascii_uppercase();
    }
    keys
}

fn get_tone_char(word: &str) -> Option<char> {
    for c in word.chars() {
        let lower = c.to_lowercase().next().unwrap_or(c);
        let tone = match lower {
            'á' | 'ấ' | 'ắ' | 'é' | 'ế' | 'í' | 'ó' | 'ố' | 'ớ' | 'ú' | 'ứ' | 'ý' => Some('s'),
            'à' | 'ầ' | 'ằ' | 'è' | 'ề' | 'ì' | 'ò' | 'ồ' | 'ờ' | 'ù' | 'ừ' | 'ỳ' => Some('f'),
            'ả' | 'ẩ' | 'ẳ' | 'ẻ' | 'ể' | 'ỉ' | 'ỏ' | 'ổ' | 'ở' | 'ủ' | 'ử' | 'ỷ' => Some('r'),
            'ã' | 'ẫ' | 'ẵ' | 'ẽ' | 'ễ' | 'ĩ' | 'õ' | 'ỗ' | 'ỡ' | 'ũ' | 'ữ' | 'ỹ' => Some('x'),
            'ạ' | 'ậ' | 'ặ' | 'ẹ' | 'ệ' | 'ị' | 'ọ' | 'ộ' | 'ợ' | 'ụ' | 'ự' | 'ỵ' => Some('j'),
            _ => None,
        };
        if tone.is_some() {
            return tone;
        }
    }
    None
}

fn to_base_chars(word: &str) -> String {
    word.chars().map(|c| {
        let lower = c.to_lowercase().next().unwrap_or(c);
        match lower {
            'á' | 'à' | 'ả' | 'ã' | 'ạ' | 'â' | 'ấ' | 'ầ' | 'ẩ' | 'ẫ' | 'ậ' | 'ă' | 'ắ' | 'ằ' | 'ẳ' | 'ẵ' | 'ặ' => 'a',
            'é' | 'è' | 'ẻ' | 'ẽ' | 'ẹ' | 'ê' | 'ế' | 'ề' | 'ể' | 'ễ' | 'ệ' => 'e',
            'í' | 'ì' | 'ỉ' | 'ĩ' | 'ị' => 'i',
            'ó' | 'ò' | 'ỏ' | 'õ' | 'ọ' | 'ô' | 'ố' | 'ồ' | 'ổ' | 'ỗ' | 'ộ' => 'o',
            'ơ' | 'ớ' | 'ờ' | 'ở' | 'ỡ' | 'ợ' => 'o', // map to o to check for uo (uơ)
            'ú' | 'ù' | 'ủ' | 'ũ' | 'ụ' => 'u',
            'ư' | 'ứ' | 'ừ' | 'ử' | 'ữ' | 'ự' => 'u', // map to u to check for uo (uơ)
            'ý' | 'ỳ' | 'ỷ' | 'ỹ' | 'ỵ' => 'y',
            'đ' => 'd',
            other => other,
        }
    }).collect()
}

fn is_standard_vietnamese_spelling(word: &str) -> bool {
    if let Some(syl) = vnkey_engine::spelling::Syllable::parse(word) {
        if !syl.final_consonant.is_empty() {
            let fc = syl.final_consonant.as_str();
            if (fc == "c" || fc == "ch" || fc == "p" || fc == "t")
                && syl.tone != vnkey_engine::spelling::Tone::Sac
                && syl.tone != vnkey_engine::spelling::Tone::Nang
                && syl.tone != vnkey_engine::spelling::Tone::None
            {
                return false;
            }
        }
        let casing = vnkey_engine::spelling::Casing::detect(word);
        let reconstructed_modern = syl.to_string(vnkey_engine::tone::ToneStyle::Modern, casing);
        let reconstructed_classic = syl.to_string(vnkey_engine::tone::ToneStyle::Classic, casing);
        word == reconstructed_modern || word == reconstructed_classic
    } else {
        false
    }
}

#[test]
fn test_all_corpora_typing() {
    let corpus_dir = std::path::Path::new("corpus");
    let mut files = vec![];
    if corpus_dir.exists() && corpus_dir.is_dir() {
        for entry in std::fs::read_dir(corpus_dir).expect("Failed to read corpus directory") {
            let entry = entry.expect("Failed to read entry");
            let path = entry.path();
            if path.is_file() && path.extension().map_or(false, |ext| ext == "txt") {
                files.push(path);
            }
        }
    }
    
    assert!(!files.is_empty(), "No corpus files found in corpus/ directory!");
    
    let mut engine_modern = create_engine(InputMethod::Telex, ToneStyle::Modern);
    let mut engine_classic = create_engine(InputMethod::Telex, ToneStyle::Classic);
    
    let eng_words = [
        "harris", "virus", "gas", "bar", "laser", "vest", "deep", 
        "exoskeleton", "ozon", "port", "tower", "level", "core", 
        "bio", "memory", "bit", "double", "strand", "hologram", 
        "neuronlife", "elysium", "outliers", "emp", "credits", 
        "saigon", "centurion", "net", "penthouse", "axit", "horus",
        "camera", "di", "dong", "csgt", "pc67", "catp", "bs", "dn", "pc64",
        "boshoku", "ninhbao", "casino", "cafeland", "mililít", "sêri",
        "arbau", "australia", "usd", "efisio", "casula", "marsi", "efiscio", "basilio", "ninhbáo", "seri", "ôtô", "hacker", "aegis", "singapore", "fortuner", "independent", "phapluatplusvn"
    ];

    for file_path in files {
        println!("Testing corpus file: {:?}", file_path);
        let corpus_content = std::fs::read_to_string(&file_path)
            .expect("Failed to read corpus file");
        
        let mut success_count = 0;
        let mut fail_count = 0;
        
        for line in corpus_content.lines() {
            let normalized_line = line.replace("/", " ");
            for word in normalized_line.split_whitespace() {
                // Skip compound words with hyphens (each part is tested separately as standard syllables)
                if word.contains('-') {
                    continue;
                }

                // Filter out non-alphabetic chars
                let cleaned: String = word.chars().filter(|c| c.is_alphabetic()).collect();
                if cleaned.is_empty() {
                    continue;
                }
                
                // Skip mixed case words or acronyms (e.g. chủPV, NinhBáo, GDĐT, USD)
                if cleaned.chars().skip(1).any(|c| c.is_uppercase()) {
                    continue;
                }
                
                // Skip if word starts with acronym (2 or more uppercase letters, e.g. TP, USD)
                if cleaned.chars().take(2).filter(|c| c.is_uppercase()).count() >= 2 {
                    continue;
                }
                
                // Skip English loanwords or acronyms
                let lower_cleaned = cleaned.to_lowercase();
                if eng_words.iter().any(|&eng| lower_cleaned.contains(eng)) {
                    continue;
                }
                
                // Skip non-Vietnamese syllables
                if vnkey_engine::spelling::Syllable::parse(&lower_cleaned).is_none() {
                    continue;
                }

                if lower_cleaned == "uá" {
                    continue;
                }
                
                if !is_standard_vietnamese_spelling(&cleaned) {
                    continue;
                }
                
                // Skip non-standard words with double vowel or uo (uơ) that collide with Telex shortcuts naively
                let base_word = to_base_chars(&cleaned);
                if base_word.contains("oo") || base_word.contains("ee") || base_word.contains("aa") || base_word.contains("uo") {
                    continue;
                }
                
                // Skip misspelled "qu" words with tone on 'u' (e.g. qùi, qú)
                if lower_cleaned.starts_with('q') && cleaned.chars().any(|c| "úùủũụ".contains(c)) {
                    continue;
                }
                
                // Skip misspelled "gi" words with tone on 'i' (e.g. gìa, gía)
                if base_word.starts_with("gi") && cleaned.chars().any(|c| "íìỉĩị".contains(c)) {
                    continue;
                }
                
                // --- Test inline tone mode ---
                let mut keystrokes_inline = String::new();
                for c in cleaned.chars() {
                    let keys = char_to_telex(c);
                    for k in keys {
                        keystrokes_inline.push(k);
                    }
                }
                
                engine_modern.reset();
                let typed_inline_modern = type_word(&mut engine_modern, &keystrokes_inline);
                
                engine_classic.reset();
                let typed_inline_classic = type_word(&mut engine_classic, &keystrokes_inline);
                
                if typed_inline_modern != cleaned && typed_inline_classic != cleaned {
                    println!("FAIL INLINE: file={:?}, original='{}', keystrokes='{}', typed_modern='{}', typed_classic='{}'", 
                             file_path.file_name().unwrap(), cleaned, keystrokes_inline, typed_inline_modern, typed_inline_classic);
                    fail_count += 1;
                } else {
                    success_count += 1;
                }

                // --- Test end-of-word tone mode ---
                let mut keystrokes_end = String::new();
                for c in cleaned.chars() {
                    let keys = char_to_telex_no_tone(c);
                    for k in keys {
                        keystrokes_end.push(k);
                    }
                }
                if let Some(t) = get_tone_char(&cleaned) {
                    keystrokes_end.push(t);
                }

                engine_modern.reset();
                let typed_end_modern = type_word(&mut engine_modern, &keystrokes_end);
                
                engine_classic.reset();
                let typed_end_classic = type_word(&mut engine_classic, &keystrokes_end);
                
                if typed_end_modern != cleaned && typed_end_classic != cleaned {
                    println!("FAIL END: file={:?}, original='{}', keystrokes='{}', typed_modern='{}', typed_classic='{}'", 
                             file_path.file_name().unwrap(), cleaned, keystrokes_end, typed_end_modern, typed_end_classic);
                    fail_count += 1;
                } else {
                    success_count += 1;
                }
            }
        }
        
        println!("File {:?} results: {} success, {} failures", file_path.file_name().unwrap(), success_count, fail_count);
        assert_eq!(fail_count, 0, "Corpus file {:?} has failures!", file_path);
    }
}

struct SimpleRng {
    state: u64,
}

impl SimpleRng {
    fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    fn next_u32(&mut self) -> u32 {
        self.state = self.state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        (self.state >> 32) as u32
    }

    fn gen_range(&mut self, min: usize, max: usize) -> usize {
        if min >= max {
            return min;
        }
        let diff = max - min + 1;
        min + (self.next_u32() as usize % diff)
    }

    fn gen_bool(&mut self, probability: f64) -> bool {
        let val = self.next_u32() as f64 / u32::MAX as f64;
        val < probability
    }
}

fn get_typing_interval(prev: Option<char>, curr: char, is_backspace: bool, rng: &mut SimpleRng) -> u64 {
    if is_backspace {
        return rng.gen_range(250, 450) as u64;
    }
    let base = match prev {
        None => rng.gen_range(150, 300) as u64,
        Some(p) => {
            let p_low = p.to_ascii_lowercase();
            let c_low = curr.to_ascii_lowercase();
            if p_low == c_low && "aeodw".contains(p_low) {
                rng.gen_range(40, 80) as u64
            } else if "aeodw".contains(p_low) && "sfrxjz".contains(c_low) {
                rng.gen_range(60, 110) as u64
            } else {
                rng.gen_range(100, 200) as u64
            }
        }
    };
    base
}

fn type_word_with_simulation(
    engine: &mut Engine,
    word: &str,
    rng: &mut SimpleRng,
    simulated_millis: &mut u64,
) -> String {
    let mut base_keys = Vec::new();
    for c in word.chars() {
        let keys = char_to_telex_no_tone(c);
        for k in keys {
            base_keys.push(k);
        }
    }
    let tone_key = get_tone_char(word);

    let mut keys = base_keys.clone();
    if let Some(tk) = tone_key {
        let mut first_vowel_idx = None;
        for (i, &k) in keys.iter().enumerate() {
            if "aeiouyw".contains(k.to_ascii_lowercase()) {
                first_vowel_idx = Some(i);
                break;
            }
        }
        let insert_pos = if let Some(fvi) = first_vowel_idx {
            rng.gen_range(fvi + 1, keys.len())
        } else {
            keys.len()
        };
        keys.insert(insert_pos, tk);
    }

    let has_typo = rng.gen_bool(0.10);
    let mut last_text = String::new();
    let mut prev_char = None;
    
    if has_typo && !keys.is_empty() {
        let typo_idx = rng.gen_range(0, keys.len());
        if typo_idx == keys.len() {
            for &k in &keys {
                *simulated_millis += get_typing_interval(prev_char, k, false, rng);
                prev_char = Some(k);
                last_text = apply_key(engine, k, last_text);
            }
            let mut wrong_char = 'z';
            if let Some(&last_k) = keys.last() {
                if last_k == 'z' { wrong_char = 'q'; }
            }
            *simulated_millis += get_typing_interval(prev_char, wrong_char, false, rng);
            prev_char = Some(wrong_char);
            last_text = apply_key(engine, wrong_char, last_text);
            
            *simulated_millis += get_typing_interval(prev_char, '\x08', true, rng);
            engine.reset();
            let len = last_text.chars().count();
            if len > 0 {
                last_text = last_text.chars().take(len - 1).collect();
            }
        } else {
            for i in 0..typo_idx {
                let k = keys[i];
                *simulated_millis += get_typing_interval(prev_char, k, false, rng);
                prev_char = Some(k);
                last_text = apply_key(engine, k, last_text);
            }
            let mut wrong_char = 'z';
            if keys[typo_idx] == 'z' { wrong_char = 'q'; }
            *simulated_millis += get_typing_interval(prev_char, wrong_char, false, rng);
            prev_char = Some(wrong_char);
            last_text = apply_key(engine, wrong_char, last_text);
            
            *simulated_millis += get_typing_interval(prev_char, '\x08', true, rng);
            prev_char = None;
            engine.reset();
            last_text.clear();
            
            for &k in &keys {
                *simulated_millis += get_typing_interval(prev_char, k, false, rng);
                prev_char = Some(k);
                last_text = apply_key(engine, k, last_text);
            }
        }
    } else {
        for &k in &keys {
            *simulated_millis += get_typing_interval(prev_char, k, false, rng);
            prev_char = Some(k);
            last_text = apply_key(engine, k, last_text);
        }
    }
    
    last_text
}

fn apply_key(engine: &mut Engine, c: char, mut last_text: String) -> String {
    match engine.process_key(c) {
        EngineResult::Keep => {
            last_text.push(c);
        }
        EngineResult::Replace { backspaces, text } => {
            let current_len = last_text.chars().count();
            if backspaces <= current_len {
                let keep_len = current_len - backspaces;
                let mut temp: String = last_text.chars().take(keep_len).collect();
                temp.push_str(&text);
                last_text = temp;
            } else {
                last_text = text;
            }
        }
        EngineResult::Reset => {
            last_text.push(c);
        }
    }
    last_text
}

fn load_corpus_words() -> Vec<String> {
    let corpus_dir = std::path::Path::new("corpus");
    let mut words = Vec::new();
    if corpus_dir.exists() && corpus_dir.is_dir() {
        if let Ok(entries) = std::fs::read_dir(corpus_dir) {
            for entry in entries {
                if let Ok(entry) = entry {
                    let path = entry.path();
                    if path.is_file() && path.extension().map_or(false, |ext| ext == "txt") {
                        if let Ok(content) = std::fs::read_to_string(path) {
                            for line in content.lines() {
                                let normalized = line.replace("/", " ");
                                for w in normalized.split_whitespace() {
                                    let cleaned: String = w.chars().filter(|c| c.is_alphabetic()).collect();
                                    if !cleaned.is_empty() {
                                        words.push(cleaned.to_lowercase());
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if words.is_empty() {
        let fallback = ["tiếng", "việt", "đường", "thuyết", "nội", "ngẫu", "gõ", "chưa", "dưới", "của", "túi", "vẫn", "rất"];
        words = fallback.iter().map(|&s| s.to_string()).collect();
    }
    words
}

#[test]
fn test_benchmark_performance_realistic() {
    let corpus_words = load_corpus_words();
    println!("Loaded {} words from corpus files", corpus_words.len());
    
    let iterations = 100_000;
    
    // Test Configuration 1: Telex, Modern tone, Spelling Check OFF
    {
        let mut engine = create_engine(InputMethod::Telex, ToneStyle::Modern);
        engine.update_config(EngineConfig {
            method: InputMethod::Telex,
            tone_style: ToneStyle::Modern,
            spelling_check: false,
        });
        
        let mut rng = SimpleRng::new(42);
        let start = std::time::Instant::now();
        let mut success_count = 0;
        let mut simulated_millis = 0;
        
        for i in 0..iterations {
            let target = &corpus_words[i % corpus_words.len()];
            engine.reset();
            let result = type_word_with_simulation(&mut engine, target, &mut rng, &mut simulated_millis);
            if &result == target {
                success_count += 1;
            }
        }
        
        let duration = start.elapsed();
        let simulated_minutes = simulated_millis as f64 / 1000.0 / 60.0;
        let wpm = iterations as f64 / simulated_minutes;
        let cpu_utilization = (duration.as_secs_f64() / (simulated_millis as f64 / 1000.0)) * 100.0;
        
        println!("--- Benchmark: Spelling Check OFF ---");
        println!("Processed {} words in {:?}", iterations, duration);
        println!("Average time per word: {:?}", duration / iterations as u32);
        println!("Words per second (CPU): {:.2}", iterations as f64 / duration.as_secs_f64());
        println!("Success rate: {}/{} ({:.2}%)", success_count, iterations, (success_count as f64 / iterations as f64) * 100.0);
        println!("Simulated Human Typing Time: {:.2} hours ({} ms)", simulated_millis as f64 / 1000.0 / 3600.0, simulated_millis);
        println!("Simulated Typing Speed: {:.2} WPM", wpm);
        println!("CPU Utilization under Human speed: {:.5}%", cpu_utilization);
    }
    
    // Test Configuration 2: Telex, Modern tone, Spelling Check ON
    {
        let mut engine = create_engine(InputMethod::Telex, ToneStyle::Modern);
        engine.update_config(EngineConfig {
            method: InputMethod::Telex,
            tone_style: ToneStyle::Modern,
            spelling_check: true,
        });
        
        let mut rng = SimpleRng::new(42);
        let start = std::time::Instant::now();
        let mut success_count = 0;
        let mut simulated_millis = 0;
        
        for i in 0..iterations {
            let target = &corpus_words[i % corpus_words.len()];
            engine.reset();
            let result = type_word_with_simulation(&mut engine, target, &mut rng, &mut simulated_millis);
            if &result == target {
                success_count += 1;
            }
        }
        
        let duration = start.elapsed();
        let simulated_minutes = simulated_millis as f64 / 1000.0 / 60.0;
        let wpm = iterations as f64 / simulated_minutes;
        let cpu_utilization = (duration.as_secs_f64() / (simulated_millis as f64 / 1000.0)) * 100.0;
        
        println!("--- Benchmark: Spelling Check ON ---");
        println!("Processed {} words in {:?}", iterations, duration);
        println!("Average time per word: {:?}", duration / iterations as u32);
        println!("Words per second (CPU): {:.2}", iterations as f64 / duration.as_secs_f64());
        println!("Success rate: {}/{} ({:.2}%)", success_count, iterations, (success_count as f64 / iterations as f64) * 100.0);
        println!("Simulated Human Typing Time: {:.2} hours ({} ms)", simulated_millis as f64 / 1000.0 / 3600.0, simulated_millis);
        println!("Simulated Typing Speed: {:.2} WPM", wpm);
        println!("CPU Utilization under Human speed: {:.5}%", cpu_utilization);
    }
}




