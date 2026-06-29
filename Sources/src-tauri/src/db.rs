use rusqlite::{params, Connection, Result as SqlResult};
use std::path::Path;
use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use rand::RngCore;
use pbkdf2::pbkdf2_hmac;
use sha2::Sha256;
use base64::{Engine as _, engine::general_purpose::STANDARD as b64};
use std::sync::Mutex;

lazy_static::lazy_static! {
    static ref DB_CONN: Mutex<Option<Connection>> = Mutex::new(None);
}

const INITIAL_ENGLISH_WORDS: &[&str] = &[];


// Generate a local encryption key (obfuscation key) for local DB encryption
// This ensures data is not "raw" on disk.
fn get_local_db_key() -> [u8; 32] {
    let mut key = [0u8; 32];
    let password = b"vnkey_local_storage_secret";
    let salt = b"vnkey_salt_123456";
    pbkdf2_hmac::<Sha256>(password, salt, 100_000, &mut key);
    key
}

pub fn encrypt_text(plain_text: &str, key: &[u8; 32]) -> String {
    let cipher = Aes256Gcm::new(key.into());
    let mut nonce_bytes = [0u8; 12];
    rand::thread_rng().fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = match cipher.encrypt(nonce, plain_text.as_bytes()) {
        Ok(ct) => ct,
        Err(_) => return plain_text.to_string(), // fallback
    };

    let mut payload = nonce_bytes.to_vec();
    payload.extend(ciphertext);
    b64.encode(payload)
}

pub fn decrypt_text(encrypted_b64: &str, key: &[u8; 32]) -> String {
    let payload = match b64.decode(encrypted_b64) {
        Ok(p) => p,
        Err(_) => return encrypted_b64.to_string(), // likely not encrypted
    };

    if payload.len() < 12 {
        return encrypted_b64.to_string();
    }

    let nonce = Nonce::from_slice(&payload[0..12]);
    let ciphertext = &payload[12..];

    let cipher = Aes256Gcm::new(key.into());
    match cipher.decrypt(nonce, ciphertext) {
        Ok(plain) => String::from_utf8(plain).unwrap_or_else(|_| encrypted_b64.to_string()),
        Err(_) => encrypted_b64.to_string(),
    }
}

pub fn init_db(app_config_dir: &Path) -> SqlResult<()> {
    std::fs::create_dir_all(app_config_dir).unwrap_or_default();
    let db_path = app_config_dir.join("vnkey.db");
    let conn = Connection::open(db_path)?;

    // Create tables
    conn.execute(
        "CREATE TABLE IF NOT EXISTS english_dict (
            word TEXT PRIMARY KEY
        )",
        [],
    )?;

    conn.execute(
        "CREATE TABLE IF NOT EXISTS vietnamese_dict (
            word TEXT PRIMARY KEY
        )",
        [],
    )?;



    conn.execute(
        "CREATE TABLE IF NOT EXISTS programming_keywords (
            word TEXT PRIMARY KEY
        )",
        [],
    )?;

    conn.execute(
        "CREATE TABLE IF NOT EXISTS macros (
            shortcut TEXT PRIMARY KEY,
            content TEXT NOT NULL
        )",
        [],
    )?;

    conn.execute(
        "CREATE TABLE IF NOT EXISTS clipboard_history (
            id TEXT PRIMARY KEY,
            timestamp INTEGER NOT NULL,
            payload TEXT NOT NULL
        )",
        [],
    )?;
    
    conn.execute(
        "CREATE TABLE IF NOT EXISTS app_kv_store (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )",
        [],
    )?;

    *DB_CONN.lock().unwrap() = Some(conn);

    let initialized = db_get_kv("english_dict_initialized").unwrap_or_else(|| "0".to_string());
    if initialized == "0" {
        let words: Vec<String> = INITIAL_ENGLISH_WORDS.iter().map(|s| s.to_string()).collect();
        db_insert_english_words(&words);
        db_set_kv("english_dict_initialized", "1");
    }



    Ok(())
}

pub fn db_insert_english_words(words: &[String]) {
    let mut conn_guard = DB_CONN.lock().unwrap();
    if let Some(conn) = conn_guard.as_mut() {
        let key = get_local_db_key();
        let tx = conn.transaction().unwrap();
        {
            let mut stmt = tx.prepare("INSERT OR IGNORE INTO english_dict (word) VALUES (?1)").unwrap();
            for word in words {
                let enc_word = encrypt_text(word, &key);
                let _ = stmt.execute(params![enc_word]);
            }
        }
        tx.commit().unwrap();
    }
}

pub fn db_get_english_words() -> Vec<String> {
    let mut words = Vec::new();
    let key = get_local_db_key();
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        if let Ok(mut stmt) = conn.prepare("SELECT word FROM english_dict") {
            let iter = stmt.query_map([], |row| {
                let enc_word: String = row.get(0)?;
                Ok(enc_word)
            });
            if let Ok(iter) = iter {
                for w_res in iter {
                    if let Ok(w) = w_res {
                        words.push(decrypt_text(&w, &key));
                    }
                }
            }
        }
    }
    words.sort();
    words.dedup();
    words
}

pub fn db_insert_vietnamese_words(words: &[String]) {
    let mut conn_guard = DB_CONN.lock().unwrap();
    if let Some(conn) = conn_guard.as_mut() {
        let key = get_local_db_key();
        let tx = conn.transaction().unwrap();
        {
            let mut stmt = tx.prepare("INSERT OR IGNORE INTO vietnamese_dict (word) VALUES (?1)").unwrap();
            for word in words {
                let enc_word = encrypt_text(word, &key);
                let _ = stmt.execute(params![enc_word]);
            }
        }
        tx.commit().unwrap();
    }
}

pub fn db_get_vietnamese_words() -> Vec<String> {
    let mut words = Vec::new();
    let key = get_local_db_key();
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        if let Ok(mut stmt) = conn.prepare("SELECT word FROM vietnamese_dict") {
            let iter = stmt.query_map([], |row| {
                let enc_word: String = row.get(0)?;
                Ok(enc_word)
            });
            if let Ok(iter) = iter {
                for w_res in iter {
                    if let Ok(w) = w_res {
                        words.push(decrypt_text(&w, &key));
                    }
                }
            }
        }
    }
    words.sort();
    words.dedup();
    words
}

pub fn db_clear_vietnamese_words() {
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        let _ = conn.execute("DELETE FROM vietnamese_dict", []);
    }
}

pub fn db_clear_english_words() {
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        let _ = conn.execute("DELETE FROM english_dict", []);
    }
}

pub fn db_reset_english_words() {
    db_clear_english_words();
    let words: Vec<String> = INITIAL_ENGLISH_WORDS.iter().map(|s| s.to_string()).collect();
    db_insert_english_words(&words);
}

pub fn db_insert_programming_keywords(words: &[String]) {
    let mut conn_guard = DB_CONN.lock().unwrap();
    if let Some(conn) = conn_guard.as_mut() {
        let key = get_local_db_key();
        let tx = conn.transaction().unwrap();
        {
            let mut stmt = tx.prepare("INSERT OR IGNORE INTO programming_keywords (word) VALUES (?1)").unwrap();
            for word in words {
                let enc_word = encrypt_text(word, &key);
                let _ = stmt.execute(params![enc_word]);
            }
        }
        tx.commit().unwrap();
    }
}

pub fn db_get_programming_keywords() -> Vec<String> {
    let mut words = Vec::new();
    let key = get_local_db_key();
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        if let Ok(mut stmt) = conn.prepare("SELECT word FROM programming_keywords") {
            let iter = stmt.query_map([], |row| {
                let enc_word: String = row.get(0)?;
                Ok(enc_word)
            });
            if let Ok(iter) = iter {
                for w_res in iter {
                    if let Ok(w) = w_res {
                        words.push(decrypt_text(&w, &key));
                    }
                }
            }
        }
    }
    words.sort();
    words.dedup();
    words
}

pub fn db_clear_programming_keywords() {
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        let _ = conn.execute("DELETE FROM programming_keywords", []);
    }
}

pub fn db_reset_programming_keywords() {
    db_clear_programming_keywords();
}

pub fn db_insert_macros(macros: &[(String, String)]) {
    let mut conn_guard = DB_CONN.lock().unwrap();
    if let Some(conn) = conn_guard.as_mut() {
        let key = get_local_db_key();
        let tx = conn.transaction().unwrap();
        {
            let mut stmt = tx.prepare("INSERT OR REPLACE INTO macros (shortcut, content) VALUES (?1, ?2)").unwrap();
            for (shortcut, content) in macros {
                let enc_shortcut = encrypt_text(shortcut, &key);
                let enc_content = encrypt_text(content, &key);
                let _ = stmt.execute(params![enc_shortcut, enc_content]);
            }
        }
        tx.commit().unwrap();
    }
}

pub fn db_get_macros() -> Vec<(String, String)> {
    let mut macros = Vec::new();
    let key = get_local_db_key();
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        if let Ok(mut stmt) = conn.prepare("SELECT shortcut, content FROM macros") {
            let iter = stmt.query_map([], |row| {
                let enc_shortcut: String = row.get(0)?;
                let enc_content: String = row.get(1)?;
                Ok((enc_shortcut, enc_content))
            });
            if let Ok(iter) = iter {
                for tuple_res in iter {
                    if let Ok(tuple) = tuple_res {
                        macros.push((decrypt_text(&tuple.0, &key), decrypt_text(&tuple.1, &key)));
                    }
                }
            }
        }
    }
    macros
}

pub fn db_clear_macros() {
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        let _ = conn.execute("DELETE FROM macros", []);
    }
}

pub fn db_set_kv(key_name: &str, value: &str) {
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        let key = get_local_db_key();
        let enc_val = encrypt_text(value, &key);
        let _ = conn.execute(
            "INSERT OR REPLACE INTO app_kv_store (key, value) VALUES (?1, ?2)",
            params![key_name, enc_val],
        );
    }
}

pub fn db_get_kv(key_name: &str) -> Option<String> {
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        let key = get_local_db_key();
        if let Ok(enc_val) = conn.query_row(
            "SELECT value FROM app_kv_store WHERE key = ?1",
            params![key_name],
            |row| row.get::<_, String>(0)
        ) {
            return Some(decrypt_text(&enc_val, &key));
        }
    }
    None
}

use crate::ClipboardItem;

pub fn db_insert_clipboard_items(items: &[ClipboardItem]) {
    let mut conn_guard = DB_CONN.lock().unwrap();
    if let Some(conn) = conn_guard.as_mut() {
        let key = get_local_db_key();
        let tx = conn.transaction().unwrap();
        {
            let mut stmt = tx.prepare("INSERT OR REPLACE INTO clipboard_history (id, timestamp, payload) VALUES (?1, ?2, ?3)").unwrap();
            for item in items {
                if let Ok(json_str) = serde_json::to_string(item) {
                    let enc_payload = encrypt_text(&json_str, &key);
                    let _ = stmt.execute(params![&item.id, item.timestamp, enc_payload]);
                }
            }
        }
        tx.commit().unwrap();
    }
}

pub fn db_get_clipboard_items() -> Vec<ClipboardItem> {
    let mut items = Vec::new();
    let key = get_local_db_key();
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        if let Ok(mut stmt) = conn.prepare("SELECT payload FROM clipboard_history ORDER BY timestamp DESC") {
            let iter = stmt.query_map([], |row| {
                let enc_payload: String = row.get(0)?;
                Ok(enc_payload)
            });
            if let Ok(iter) = iter {
                for payload_res in iter {
                    if let Ok(payload) = payload_res {
                        let dec_payload = decrypt_text(&payload, &key);
                        if let Ok(item) = serde_json::from_str::<ClipboardItem>(&dec_payload) {
                            items.push(item);
                        }
                    }
                }
            }
        }
    }
    items
}

pub fn db_clear_clipboard() {
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        let _ = conn.execute("DELETE FROM clipboard_history", []);
    }
}


