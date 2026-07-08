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
    static ref DB_KEY: [u8; 32] = {
        let mut key = [0u8; 32];
        let password = b"vnkey_local_storage_secret";
        let salt = b"vnkey_salt_123456";
        pbkdf2_hmac::<Sha256>(password, salt, 2_000, &mut key);
        key
    };
}

// Generate a local encryption key (obfuscation key) for local DB encryption
// This ensures data is not "raw" on disk.
fn get_local_db_key() -> [u8; 32] {
    *DB_KEY
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

const DEFAULT_PRIORITY_WORDS: &[&str] = &[
    // C++
    "alignas", "alignof", "asm", "auto", "bool", "break", "case", "catch", "char", "char8_t",
    "char16_t", "char32_t", "class", "const", "consteval", "constexpr", "constinit", "const_cast",
    "continue", "co_await", "co_return", "co_yield", "decltype", "default", "delete", "do",
    "double", "dynamic_cast", "else", "enum", "explicit", "export", "extern", "false", "float",
    "for", "friend", "goto", "if", "inline", "int", "long", "mutable", "namespace", "new",
    "noexcept", "nullptr", "operator", "private", "protected", "public", "register",
    "reinterpret_cast", "requires", "return", "short", "signed", "sizeof", "static", "static_assert",
    "static_cast", "struct", "switch", "template", "this", "thread_local", "throw", "true",
    "try", "typedef", "typeid", "typename", "union", "unsigned", "using", "virtual", "void",
    "volatile", "wchar_t", "while",
    // C#
    "decimal", "delegate", "fixed", "implicit", "internal", "object", "out", "override", "params",
    "ref", "sbyte", "sealed", "stackalloc", "uint", "ulong", "unchecked", "unsafe", "ushort",
    "ascending", "descending", "equals", "nameof", "orderby", "partial", "remove", "select",
    // PHP
    "abstract", "array", "as", "callable", "clone", "declare", "die", "echo", "empty", "enddeclare",
    "endfor", "endforeach", "endif", "endswitch", "endwhile", "eval", "exit", "extends", "final",
    "finally", "fn", "foreach", "function", "global", "implements", "include", "include_once",
    "instanceof", "insteadof", "interface", "isset", "list", "match", "print", "require",
    "require_once", "trait", "use", "var", "yield",
    // Java
    "assert", "boolean", "byte", "native", "package", "strictfp", "super", "synchronized",
    "throws", "transient",
    // Python
    "None", "False", "True", "and", "def", "del", "elif", "except", "global", "import", "in",
    "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "with",
    // Javascript & TypeScript
    "let", "const", "var", "async", "await", "typeof", "debugger", "any", "constructor", "get",
    "module", "number", "readonly", "set", "string", "symbol", "type", "from", "of",
    // Ruby
    "elsif", "ensure", "nil", "redo", "rescue", "retry", "self", "then", "undef", "unless", "until",
    // Shell bash & Commands (Terminal, CMD, PowerShell)
    "alias", "bg", "bind", "builtin", "caller", "cd", "command", "coproc", "dirs", "disown",
    "enable", "exec", "fc", "fg", "getopts", "hash", "help", "history", "jobs", "local",
    "logout", "mapfile", "popd", "printf", "pushd", "pwd", "read", "readarray", "shift",
    "shopt", "source", "suspend", "test", "times", "trap", "typeset", "ulimit", "umask",
    "unalias", "unset", "wait", "ls", "mkdir", "rmdir", "rm", "cp", "mv", "touch", "cat",
    "grep", "find", "chmod", "chown", "sudo", "apt", "brew", "yum", "dnf", "npm", "node",
    "pip", "git", "docker", "composer", "cargo", "rustc", "clang", "gcc", "make", "cmake",
    "dir", "copy", "move", "del", "ren", "cls", "ipconfig", "ping", "netstat", "tasklist",
    "taskkill", "systeminfo", "gpupdate", "shutdown", "get-process", "get-service", "get-command",
    "get-member", "get-help", "set-executionpolicy", "write-host", "write-output", "select-object",
    "where-object", "foreach-object", "invoke-webrequest", "invoke-expression",
    // SQL
    "select", "insert", "update", "delete", "create", "drop", "alter", "table", "index",
    "where", "join", "inner", "outer", "left", "right", "group", "having", "order", "limit",
    "offset", "between", "exists", "like", "into", "values", "null", "primary", "foreign",
    "key", "references", "constraint", "union", "all", "any", "as", "from", "on", "into",
    // Common confusing English & Vietnamese words
    "game", "in", "or", "case", "true", "false", "new", "class", "function", "return",
    "import", "export", "chat", "schema", "error", "warning", "info", "debug", "trace",
    "config", "setting", "setup", "install", "uninstall", "update", "upgrade", "download",
    "upload", "sync", "cloud", "local", "server", "client", "database", "query",
    "username", "password", "email", "phone", "address", "name", "title", "description",
    "content", "status", "type", "category", "tag", "image", "file", "folder", "directory",
    "path", "url", "link", "button", "input", "output", "text", "date", "time", "datetime",
    "timestamp", "event", "action", "handler", "listener", "callback", "promise", "future",
    "task", "job", "process", "thread", "mutex", "lock", "unlock", "signal", "broadcast",
    "notify", "subscribe", "publish", "message", "packet", "data", "payload", "header",
    "body", "footer", "meta", "version", "build", "release"
];

pub fn init_db(app_config_dir: &Path) -> SqlResult<()> {
    std::fs::create_dir_all(app_config_dir).unwrap_or_default();
    let db_path = app_config_dir.join("vnkey.db");
    let mut conn = Connection::open(db_path)?;

    // Create tables
    conn.execute(
        "CREATE TABLE IF NOT EXISTS priority_words (
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

    // Pre-populate default priority words if empty
    let count: i64 = conn.query_row("SELECT COUNT(*) FROM priority_words", [], |row| row.get(0))?;
    if count == 0 {
        let tx = conn.transaction()?;
        {
            let mut stmt = tx.prepare("INSERT OR IGNORE INTO priority_words (word) VALUES (?1)")?;
            for &word in DEFAULT_PRIORITY_WORDS {
                let _ = stmt.execute(params![word]);
            }
        }
        tx.commit()?;
    }

    *DB_CONN.lock().unwrap() = Some(conn);

    Ok(())
}

pub fn db_insert_priority_words(words: &[String]) {
    let mut conn_guard = DB_CONN.lock().unwrap();
    if let Some(conn) = conn_guard.as_mut() {
        let tx = conn.transaction().unwrap();
        {
            let mut stmt = tx.prepare("INSERT OR IGNORE INTO priority_words (word) VALUES (?1)").unwrap();
            for word in words {
                let _ = stmt.execute(params![word]);
            }
        }
        tx.commit().unwrap();
    }
}

pub fn db_get_priority_words() -> Vec<String> {
    let mut words = Vec::new();
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        if let Ok(mut stmt) = conn.prepare("SELECT word FROM priority_words") {
            let iter = stmt.query_map([], |row| {
                let word: String = row.get(0)?;
                Ok(word)
            });
            if let Ok(iter) = iter {
                for w_res in iter {
                    if let Ok(w) = w_res {
                        words.push(w);
                    }
                }
            }
        }
    }
    words.sort();
    words.dedup();
    words
}

pub fn db_clear_priority_words() {
    if let Some(conn) = DB_CONN.lock().unwrap().as_ref() {
        let _ = conn.execute("DELETE FROM priority_words", []);
    }
}

pub fn db_reset_priority_words() {
    let mut conn_guard = DB_CONN.lock().unwrap();
    if let Some(conn) = conn_guard.as_mut() {
        let _ = conn.execute("DELETE FROM priority_words", []);
        if let Ok(tx) = conn.transaction() {
            {
                if let Ok(mut stmt) = tx.prepare("INSERT OR IGNORE INTO priority_words (word) VALUES (?1)") {
                    for &word in DEFAULT_PRIORITY_WORDS {
                        let _ = stmt.execute(params![word]);
                    }
                }
            }
            let _ = tx.commit();
        }
    }
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


