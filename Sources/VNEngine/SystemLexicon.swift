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

    public func isEnglish(_ word: String) -> Bool { known(word, "en") }
    /// Không có từ điển Việt thì coi như hợp lệ (không tự khôi phục từ mơ hồ).
    public func isVietnamese(_ word: String) -> Bool { hasVietnamese ? known(word, "vi") : true }
}
#endif
