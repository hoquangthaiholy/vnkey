import Foundation

/// Bằng chứng về cách người dùng gõ, để chọn giữa các từ cùng khớp một chuỗi phím thiếu dấu.
public protocol ContextModel: AnyObject {
    /// Số lần `word` đã được gõ ngay sau `prev`.
    func pairCount(_ word: String, after prev: String) -> Int
    /// Số lần `word` đã được gõ.
    func count(_ word: String) -> Int
    func record(_ word: String, after prev: String?)
    /// Rút lại một lần `record` (người dùng quay lại sửa từ đó: lần gõ cũ là gõ nhầm, không phải thói quen).
    func unrecord(_ word: String, after prev: String?)
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

    public func unrecord(_ word: String, after prev: String?) {
        func drop(_ d: inout [String: Int], _ key: String) {
            guard let n = d[key] else { return }
            d[key] = n > 1 ? n - 1 : nil
            dirty = true
        }
        drop(&words, word)
        if let prev, !prev.isEmpty { drop(&pairs, UsageModel.key(prev, word)) }
    }

    // MARK: - Cho người dùng xem

    /// Một cặp từ đã học đủ để VNKey sửa dạng gõ không dấu: gõ "`prev` `plain`" sẽ thành "`prev` `word`".
    public struct LearnedPair: Equatable {
        public var prev: String, word: String, plain: String, count: Int
        public init(prev: String, word: String, plain: String, count: Int) {
            self.prev = prev; self.word = word; self.plain = plain; self.count = count
        }
    }

    /// Bỏ dấu thanh, mũ, móc và đ -> d.
    static func plain(_ word: String) -> String {
        word.replacingOccurrences(of: "đ", with: "d").folding(options: .diacriticInsensitive, locale: nil)
    }

    /// Các cặp đủ điều kiện sửa, theo đúng luật của `Engine.predict` cho chữ không dấu: dạng có dấu được gõ ít
    /// nhất `minCount` lần, ít nhất gấp đôi dạng có dấu đứng thứ hai, và nhiều hơn dạng không dấu. Xếp theo số
    /// lần giảm dần.
    public func learnedPairs(minCount: Int = 3) -> [LearnedPair] {
        // Gom theo (từ trước, dạng không dấu của từ sau).
        var groups: [String: [(word: String, count: Int)]] = [:]
        var prevOf: [String: String] = [:]
        for (key, count) in pairs {
            guard let cut = key.firstIndex(of: "\u{1}") else { continue }
            let prev = String(key[..<cut]), word = String(key[key.index(after: cut)...])
            let group = prev + "\u{1}" + UsageModel.plain(word)
            groups[group, default: []].append((word, count))
            prevOf[group] = prev
        }
        var out: [LearnedPair] = []
        for (group, forms) in groups {
            let plain = String(group[group.index(after: group.firstIndex(of: "\u{1}")!)...])
            let marked = forms.filter { $0.word != plain }.sorted { $0.count > $1.count }
            guard let best = marked.first, best.count >= minCount else { continue }
            let second = marked.dropFirst().first?.count ?? 0
            let typedPlain = forms.first { $0.word == plain }?.count ?? 0
            if best.count >= 2 * second, best.count > typedPlain {
                out.append(LearnedPair(prev: prevOf[group]!, word: best.word, plain: plain, count: best.count))
            }
        }
        return out.sorted { $0.count != $1.count ? $0.count > $1.count : ($0.prev, $0.word) < ($1.prev, $1.word) }
    }

    /// Quên hẳn một cặp (người dùng xoá nó trong Cài đặt).
    public func forget(prev: String, word: String) {
        guard let n = pairs.removeValue(forKey: UsageModel.key(prev, word)) else { return }
        if let total = words[word] { words[word] = total > n ? total - n : nil }
        dirty = true
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
