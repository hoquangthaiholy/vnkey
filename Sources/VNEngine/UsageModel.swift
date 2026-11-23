import Foundation

/// Bằng chứng về cách người dùng gõ, để chọn giữa các từ cùng khớp một chuỗi phím thiếu dấu.
public protocol ContextModel: AnyObject {
    /// Số lần `word` đã được gõ ngay sau `prev`.
    func pairCount(_ word: String, after prev: String) -> Int
    /// Số lần `word` đã được gõ.
    func count(_ word: String) -> Int
    func record(_ word: String, after prev: String?)
}

/// Bảng đếm từ và cặp từ liền nhau mà người dùng đã gõ (chữ thường). Chỉ có số đếm: không lưu câu, không
/// lưu thứ tự thời gian. Có giới hạn kích thước; đầy thì bỏ các mục ít dùng nhất. Chỉ dùng trên một luồng.
public final class UsageModel: ContextModel {
    private var words: [String: Int] = [:]
    private var pairs: [String: Int] = [:]
    private let wordLimit: Int, pairLimit: Int
    /// false: vẫn trả lời câu hỏi nhưng không ghi thêm.
    public var recording = true
    /// Có thay đổi chưa được lưu (app đọc để biết khi nào cần ghi tệp).
    public private(set) var dirty = false

    public init(wordLimit: Int = 3000, pairLimit: Int = 8000) {
        self.wordLimit = wordLimit; self.pairLimit = pairLimit
    }

    private static func key(_ prev: String, _ word: String) -> String { prev + "\u{1}" + word }

    public func pairCount(_ word: String, after prev: String) -> Int { pairs[UsageModel.key(prev, word)] ?? 0 }
    public func count(_ word: String) -> Int { words[word] ?? 0 }
    public var wordCount: Int { words.count }
    public var pairTotal: Int { pairs.count }

    public func record(_ word: String, after prev: String?) {
        guard recording, !word.isEmpty else { return }
        words[word, default: 0] += 1
        if let prev, !prev.isEmpty { pairs[UsageModel.key(prev, word), default: 0] += 1 }
        dirty = true
        if words.count > wordLimit { words = UsageModel.trim(words, to: wordLimit) }
        if pairs.count > pairLimit { pairs = UsageModel.trim(pairs, to: pairLimit) }
    }

    /// Giữ lại khoảng 3/4 giới hạn, ưu tiên mục có số đếm cao (để không phải dọn lại ở mỗi lần ghi).
    private static func trim(_ d: [String: Int], to limit: Int) -> [String: Int] {
        let keep = d.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit * 3 / 4)
        return Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    public func clear() {
        words = [:]; pairs = [:]; dirty = true
    }

    public func markSaved() { dirty = false }

    // MARK: - Lưu / đọc

    private struct Stored: Codable {
        var version = 1
        var words: [String: Int]
        var pairs: [String: Int]
    }

    public func data() -> Data { (try? JSONEncoder().encode(Stored(words: words, pairs: pairs))) ?? Data() }

    public convenience init?(data: Data, wordLimit: Int = 3000, pairLimit: Int = 8000) {
        guard let s = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        self.init(wordLimit: wordLimit, pairLimit: pairLimit)
        words = s.words
        pairs = s.pairs
    }
}
