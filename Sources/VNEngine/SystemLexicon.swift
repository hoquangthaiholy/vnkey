#if canImport(AppKit)
import AppKit

/// Phân xử từ mơ hồ bằng từ điển chính tả của macOS (có sẵn "en" và "vi").
/// Phần duy nhất của VNEngine phụ thuộc AppKit; engine vẫn chạy được khi không có nó.
public final class SystemLexicon: Lexicon {
    private let checker = NSSpellChecker.shared
    private let hasVietnamese = NSSpellChecker.shared.availableLanguages.contains("vi")
    private var cache: [String: Bool] = [:]

    public init() {}

    private func known(_ word: String, _ lang: String) -> Bool {
        let key = lang + ":" + word
        if let hit = cache[key] { return hit }
        let r = checker.checkSpelling(
            of: word, startingAt: 0, language: lang, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        let ok = r.location == NSNotFound
        // Đầy thì bỏ một nửa (bất kỳ) thay vì xoá sạch, để không phải hỏi lại mọi từ quen cùng lúc.
        if cache.count > 5000 { for k in Array(cache.keys.prefix(2500)) { cache[k] = nil } }
        cache[key] = ok
        return ok
    }

    private var ranks: [String: [String]] = [:]

    /// Gợi ý của trình kiểm tra chính tả cho `typed` đặt trong câu (nó có dùng các từ đứng trước). Mỗi lần hỏi
    /// mất khoảng 5–15 ms nên kết quả được nhớ lại; engine chỉ hỏi khi các cách chọn khác không quyết được.
    public func rank(_ candidates: [String], after context: [String], typed: String) -> String? {
        guard hasVietnamese else { return nil }
        let sentence = (context + [typed]).joined(separator: " ")
        let guesses: [String]
        if let hit = ranks[sentence] {
            guesses = hit
        } else {
            let ns = sentence as NSString
            let range = NSRange(location: ns.length - (typed as NSString).length, length: (typed as NSString).length)
            guesses = (checker.guesses(forWordRange: range, in: sentence, language: "vi", inSpellDocumentWithTag: 0) ?? [])
                .map { $0.lowercased() }
            if ranks.count > 500 { ranks.removeAll() }
            ranks[sentence] = guesses
        }
        return guesses.first { candidates.contains($0) }
    }

    public func isEnglish(_ word: String) -> Bool { known(word, "en") }
    /// Không có từ điển Việt thì coi như hợp lệ (không tự khôi phục từ mơ hồ).
    public func isVietnamese(_ word: String) -> Bool { hasVietnamese ? known(word, "vi") : true }
}
#endif
