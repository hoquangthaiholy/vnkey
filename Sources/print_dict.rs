use rusqlite::Connection;
fn main() {
    let conn = Connection::open("/Users/theodore/Library/Application Support/com.hoquangthaiholy.vnkey/vnkey.db").unwrap();
    let mut stmt = conn.prepare("SELECT word FROM english_dict").unwrap();
    let iter = stmt.query_map([], |row| {
        let enc_word: String = row.get(0).unwrap();
        Ok(enc_word)
    }).unwrap();
    
    let mut words = Vec::new();
    for w in iter {
        words.push(w.unwrap());
    }
    println!("Total rows: {}", words.len());
    
    // Check for duplicates
    let mut sorted = words.clone();
    sorted.sort();
    let original_len = sorted.len();
    sorted.dedup();
    if sorted.len() < original_len {
        println!("FOUND DUPLICATES IN DB! {} duplicates", original_len - sorted.len());
    } else {
        println!("NO DUPLICATES IN DB.");
    }
}
