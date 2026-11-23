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
    /// Cụm hai từ có dấu mà người dùng hay gõ, ứng với hai từ vừa gõ KHÔNG dấu ("lam", "loi" -> "lầm lỗi").
    /// nil nếu chưa đủ bằng chứng: phải được gõ ít nhất ba lần, ít nhất gấp đôi cụm có dấu khác cùng khớp, và
    /// nhiều hơn số lần người dùng gõ chính cụm không dấu đó.
    func phrase(plainPrev: String, plainWord: String) -> (prev: String, word: String, count: Int)?
}

/// Bảng đếm từ và cặp từ liền nhau mà người dùng đã gõ (chữ thường). Chỉ có số đếm: không lưu câu, không
/// lưu thứ tự thời gian. Có giới hạn kích thước; đầy thì bỏ các mục ít dùng nhất. Chỉ dùng trên một luồng.
public final class UsageModel: ContextModel {
    private var words: [String: Int] = [:]
    private var pairs: [String: Int] = [:]
    /// (từ trước, từ sau) ở dạng không dấu -> các khoá trong `pairs` có dạng không dấu đó. Để tra cụm từ sau
    /// hai từ gõ không dấu mà không phải duyệt cả bảng ở mỗi lần kết thúc từ.
    private var plainIndex: [String: Set<String>] = [:]
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
        if let prev, !prev.isEmpty {
            let key = UsageModel.key(prev, word)
            if pairs[key] == nil { plainIndex[UsageModel.key(UsageModel.plain(prev), UsageModel.plain(word)), default: []].insert(key) }
            pairs[key, default: 0] += 1
        }
        dirty = true
        if words.count > wordLimit { words = UsageModel.trim(words, to: wordLimit) }
        if pairs.count > pairLimit {
            pairs = UsageModel.trim(pairs, to: pairLimit)
            rebuildIndex()
        }
    }

    public func unrecord(_ word: String, after prev: String?) {
        func drop(_ d: inout [String: Int], _ key: String) {
            guard let n = d[key] else { return }
            d[key] = n > 1 ? n - 1 : nil
            dirty = true
        }
        drop(&words, word)
        if let prev, !prev.isEmpty {
            let key = UsageModel.key(prev, word)
            drop(&pairs, key)
            if pairs[key] == nil { unindex(key, prev, word) }
        }
    }

    private func unindex(_ key: String, _ prev: String, _ word: String) {
        let group = UsageModel.key(UsageModel.plain(prev), UsageModel.plain(word))
        plainIndex[group]?.remove(key)
        if plainIndex[group]?.isEmpty == true { plainIndex[group] = nil }
    }

    private func rebuildIndex() {
        plainIndex = [:]
        for key in pairs.keys {
            guard let cut = key.firstIndex(of: "\u{1}") else { continue }
            let prev = String(key[..<cut]), word = String(key[key.index(after: cut)...])
            plainIndex[UsageModel.key(UsageModel.plain(prev), UsageModel.plain(word)), default: []].insert(key)
        }
    }

    public func phrase(plainPrev: String, plainWord: String) -> (prev: String, word: String, count: Int)? {
        let plainKey = UsageModel.key(plainPrev, plainWord)
        guard let keys = plainIndex[plainKey] else { return nil }
        let marked = keys.filter { $0 != plainKey }.map { ($0, pairs[$0] ?? 0) }.sorted { $0.1 > $1.1 }
        guard let best = marked.first, best.1 >= 3, best.1 >= 2 * (marked.dropFirst().first?.1 ?? 0),
            best.1 > (pairs[plainKey] ?? 0), let cut = best.0.firstIndex(of: "\u{1}")
        else { return nil }
        return (String(best.0[..<cut]), String(best.0[best.0.index(after: cut)...]), best.1)
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
        unindex(UsageModel.key(prev, word), prev, word)
        if let total = words[word] { words[word] = total > n ? total - n : nil }
        dirty = true
    }

    /// Giữ lại khoảng 3/4 giới hạn, ưu tiên mục có số đếm cao (để không phải dọn lại ở mỗi lần ghi).
    private static func trim(_ d: [String: Int], to limit: Int) -> [String: Int] {
        let keep = d.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit * 3 / 4)
        return Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    public func clear() {
        words = [:]; pairs = [:]; plainIndex = [:]; dirty = true
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
        rebuildIndex()
    }
}
