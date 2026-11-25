import Foundation

/// Việc người dùng nhờ mô hình ngôn ngữ làm với một câu (bảng "Cả câu", người dùng yêu cầu 2026-11-25). Chỉ `fix` đi
/// qua `SentenceFilter.merge`; các việc còn lại là viết lại nên lấy nguyên câu mô hình trả về.
public enum SentenceTask: String, CaseIterable, Sendable {
    case fix, improve, rewrite, shorten, expand, translate
    /// Viết thành câu hoàn chỉnh từ vài ý hoặc từ khoá người dùng gõ (2026-11-25).
    case compose

    /// Câu có chữ mang dấu tiếng Việt thì coi là tiếng Việt; không thì coi là tiếng Anh. (Câu tiếng Việt gõ không dấu
    /// sẽ bị coi là tiếng Anh: người dùng nên chạy `fix` trước.)
    public static func isVietnamese(_ sentence: String) -> Bool {
        sentence.precomposedStringWithCanonicalMapping.contains { !$0.isASCII && Charset.letterInfo($0) != nil }
    }

    /// Chỉ dẫn đưa cho mô hình, viết bằng chính ngôn ngữ của câu: đo 2026-11-25, chỉ dẫn tiếng Việt cho câu tiếng Anh
    /// làm mô hình trả lời bằng tiếng Việt dù đã dặn giữ nguyên ngôn ngữ.
    public func instructions(for sentence: String) -> String {
        let vi = SentenceTask.isVietnamese(sentence)
        let tail = vi
            ? " Chỉ trả về kết quả bằng tiếng Việt, không giải thích, không đặt trong dấu ngoặc kép."
            : " Return only the result, in English, with no explanation and no quotation marks."
        switch self {
        case .fix: return SentenceFilter.instructions
        case .improve:
            return (vi
                ? "Hãy sửa câu người dùng đưa cho rõ ràng, tự nhiên và đúng ngữ pháp hơn. Giữ nguyên ý; câu hỏi vẫn là câu hỏi."
                : "Improve the user's sentence so it is clear, natural and grammatically correct. Keep the meaning; a question stays a question.") + tail
        case .rewrite:
            return (vi
                ? "Hãy viết lại câu người dùng đưa bằng cách diễn đạt khác. Giữ nguyên ý; câu hỏi vẫn là câu hỏi."
                : "Rewrite the user's sentence with different wording. Keep the meaning; a question stays a question.") + tail
        case .shorten:
            return (vi
                ? "Hãy viết lại câu người dùng đưa cho ngắn gọn hơn bằng cách bỏ từ thừa. Giữ nguyên ý nghĩa: câu hỏi vẫn là câu hỏi, không đổi khẳng định thành phủ định."
                : "Make the user's sentence shorter by removing unnecessary words. Keep the meaning: a question stays a question, and do not turn a statement into its opposite.") + tail
        case .expand:
            return (vi
                ? "Hãy viết lại câu người dùng đưa cho dài hơn và chi tiết hơn: thêm từ ngữ làm rõ ý, kết quả phải dài hơn câu gốc, tối đa hai câu. Không thêm sự việc mới."
                : "Make the user's sentence longer and more detailed: add wording that clarifies it; the result must be longer than the original, two sentences at most. Do not add new facts.") + tail
        case .translate:
            return vi
                ? "Translate the user's Vietnamese sentence into English. Return only the English translation, with no explanation and no quotation marks."
                : "Hãy dịch câu người dùng đưa sang tiếng Việt. Chỉ trả về bản dịch tiếng Việt, không giải thích, không đặt trong dấu ngoặc kép."
        case .compose:
            return (vi
                ? "Người dùng đưa vài ý, ghi chú hoặc từ khoá. Hãy viết chúng thành câu văn hoàn chỉnh, tự nhiên, lịch sự vừa phải, tối đa hai câu. Chỉ dùng thông tin người dùng đưa, không thêm sự việc mới."
                : "The user gives a few notes or keywords. Write them out as complete, natural sentences, two at most. Use only the information given; do not add new facts.") + tail
        }
    }

    /// Lời nhắn gửi cho mô hình: với `fix` là chính câu đó (yêu cầu nằm trong chỉ dẫn); với việc khác thì nhắc lại yêu
    /// cầu ngay trước câu, vì chỉ dẫn chung không đủ giữ mô hình đúng việc (đo 2026-11-25).
    public func prompt(for sentence: String) -> String {
        if self == .fix { return sentence }
        let vi = SentenceTask.isVietnamese(sentence)
        let ask: String
        switch self {
        case .fix: ask = ""
        case .improve: ask = vi ? "Sửa câu sau cho rõ ràng và tự nhiên hơn (giữ nguyên ý):" : "Improve this sentence (keep the meaning, answer in English):"
        case .rewrite: ask = vi ? "Viết lại câu sau bằng cách diễn đạt khác (giữ nguyên ý):" : "Rewrite this sentence with different wording (keep the meaning, answer in English):"
        case .shorten: ask = vi ? "Viết câu sau ngắn gọn hơn (giữ nguyên ý nghĩa):" : "Make this sentence shorter (keep the meaning, answer in English):"
        case .expand: ask = vi ? "Viết câu sau dài và chi tiết hơn (không thêm sự việc mới):" : "Make this sentence longer and more detailed (no new facts, answer in English):"
        case .translate: ask = vi ? "Translate this Vietnamese sentence into English:" : "Dịch câu tiếng Anh sau sang tiếng Việt:"
        case .compose: ask = vi ? "Viết các ý sau thành câu hoàn chỉnh (không thêm sự việc mới):" : "Write these notes out as complete sentences (no new facts, answer in English):"
        }
        return ask + "\n" + sentence
    }

    /// Dọn câu trả lời của mô hình cho việc này: `fix` thì lọc theo câu gốc; việc khác thì bỏ khoảng trắng và cặp ngoặc
    /// kép bao ngoài (mô hình hay tự thêm).
    public func clean(_ answer: String, original: String) -> String {
        var text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if self == .fix { return SentenceFilter.merge(original: original, proposed: text) }
        for (open, close) in [("\"", "\""), ("“", "”"), ("'", "'")] where text.count > 2 && text.hasPrefix(open) && text.hasSuffix(close) {
            text = String(text.dropFirst().dropLast())
        }
        return text.replacingOccurrences(of: "\n", with: " ")
    }
}

/// Lọc kết quả "sửa cả câu" của một mô hình ngôn ngữ (thử nghiệm 2026-11-25): mô hình sửa chính tả khá tốt nhưng tự
/// thêm dấu câu, viết hoa đầu câu, và dịch từ tiếng Anh xen trong câu. Bộ lọc so câu gốc với câu mô hình trả về theo
/// từng từ và CHỈ nhận những chỗ một từ được sửa dấu hoặc sửa âm; mọi thứ khác giữ đúng như người dùng đã gõ.
public enum SentenceFilter {
    /// Chỉ dẫn đưa cho mô hình (dùng chung cho `vnkey-tool fix-sentence` và ứng dụng).
    public static let instructions = """
        Bạn là công cụ sửa chính tả tiếng Việt. Người dùng đưa một câu. Hãy trả về đúng câu đó sau khi sửa lỗi chính tả \
        và thêm các dấu còn thiếu. Giữ nguyên từ ngữ, thứ tự từ, dấu câu và cách viết hoa; không thêm bớt ý; không giải \
        thích. Chỉ trả về câu đã sửa, trên một dòng.
        """

    /// Đoạn văn chứa đoạn `range`: từ sau dấu xuống dòng gần nhất bên trái tới trước dấu xuống dòng bên phải, bỏ khoảng
    /// trắng hai đầu. nil nếu dài quá `limit` ký tự hoặc rỗng.
    public static func paragraph(in text: String, around range: Range<Int>, limit: Int = 1200) -> Range<Int>? {
        let units = Array(text.utf16)
        guard range.lowerBound >= 0, range.upperBound <= units.count, range.lowerBound <= range.upperBound else { return nil }
        func ends(_ u: UInt16) -> Bool { u == 0x0A || u == 0x0D }
        func blank(_ u: UInt16) -> Bool { u == 0x20 || u == 0x09 || u == 0xA0 }
        var start = range.lowerBound, end = range.upperBound
        while start > 0, !ends(units[start - 1]) { start -= 1 }
        while end < units.count, !ends(units[end]) { end += 1 }
        while start < end, blank(units[start]) { start += 1 }
        while end > start, blank(units[end - 1]) { end -= 1 }
        guard end > start, end - start <= limit else { return nil }
        return start..<end
    }

    /// Câu chứa đoạn `range` trong `text` (vị trí UTF-16): từ sau dấu kết câu / xuống dòng gần nhất bên trái tới
    /// trước dấu kết câu / xuống dòng gần nhất bên phải, bỏ khoảng trắng hai đầu. nil nếu câu dài quá `limit` ký tự
    /// (không đưa cả đoạn văn cho mô hình) hoặc chỉ có một từ.
    public static func sentence(in text: String, around range: Range<Int>, limit: Int = 400) -> Range<Int>? {
        let units = Array(text.utf16)
        guard range.lowerBound >= 0, range.upperBound <= units.count, range.lowerBound <= range.upperBound else { return nil }
        func ends(_ u: UInt16) -> Bool { u == 0x2E || u == 0x21 || u == 0x3F || u == 0x2026 || u == 0x0A || u == 0x0D }
        func blank(_ u: UInt16) -> Bool { u == 0x20 || u == 0x09 || u == 0xA0 }
        var start = range.lowerBound, end = range.upperBound
        while start > 0, !ends(units[start - 1]) { start -= 1 }
        while end < units.count, !ends(units[end]) { end += 1 }
        while start < end, blank(units[start]) { start += 1 }
        while end > start, blank(units[end - 1]) { end -= 1 }
        guard end - start <= limit, units[start..<end].contains(where: blank) else { return nil }
        return start..<end
    }
    private enum Piece {
        case word(String)
        case gap(String)
    }

    /// Tách câu thành từ (chữ cái, chữ số, dấu nháy giữa từ) và phần ngăn cách (khoảng trắng, dấu câu).
    private static func pieces(_ text: String) -> [Piece] {
        var out: [Piece] = []
        var word = "", gap = ""
        for ch in text {
            if ch.isLetter || ch.isNumber {
                if !gap.isEmpty { out.append(.gap(gap)); gap = "" }
                word.append(ch)
            } else {
                if !word.isEmpty { out.append(.word(word)); word = "" }
                gap.append(ch)
            }
        }
        if !word.isEmpty { out.append(.word(word)) }
        if !gap.isEmpty { out.append(.gap(gap)) }
        return out
    }

    /// Dạng để so hai từ: chữ thường, bỏ hết dấu ("Việt", "viet", "viêt" đều là "viet").
    private static func plain(_ word: String) -> String { Charset.stripMarks(word.precomposedStringWithCanonicalMapping).lowercased() }

    private static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty || y.isEmpty { return max(x.count, y.count) }
        var row = Array(0...y.count)
        for i in 1...x.count {
            var previous = row[0]
            row[0] = i
            for j in 1...y.count {
                let next = min(previous + (x[i - 1] == y[j - 1] ? 0 : 1), row[j] + 1, row[j - 1] + 1)
                previous = row[j]
                row[j] = next
            }
        }
        return row[y.count]
    }

    /// Có nhận `proposed` thay cho `original` không: nó phải là một âm tiết tiếng Việt đúng chính tả, khác hẳn từ gốc
    /// (không chỉ khác hoa/thường hay chỗ đặt dấu thanh), và gần từ gốc: cùng chữ cái khi bỏ dấu (thêm / sửa dấu),
    /// hoặc lệch không quá hai chữ (lẫn âm: "dới" -> "với", "trưng" -> "chưng", "riệu" -> "rượu"). Một từ bị thay
    /// bằng từ khác hẳn ("data" -> "dữ") thì không nhận.
    private static func accepts(_ original: String, _ proposed: String) -> Bool {
        guard let fixed = Charset.syllableKey(proposed) else { return false }
        if Charset.syllableKey(original) == fixed { return false }
        let a = plain(original), b = plain(proposed)
        return a == b || (distance(a, b) <= 2 && abs(a.count - b.count) <= 1 && a.count >= 2)
    }

    /// Câu gốc với những từ được mô hình sửa dấu / sửa âm; dấu câu, khoảng trắng, hoa thường và mọi từ khác giữ nguyên
    /// như câu gốc. Mô hình thêm, bớt hay đổi hẳn từ ở đoạn nào thì đoạn đó lấy theo câu gốc.
    public static func merge(original: String, proposed: String) -> String {
        let source = pieces(original)
        let old = source.compactMap { p -> String? in if case .word(let w) = p { return w } else { return nil } }
        let new = pieces(proposed).compactMap { p -> String? in if case .word(let w) = p { return w } else { return nil } }
        // Ghép hai dãy từ bằng dãy con chung dài nhất trên dạng bỏ dấu: từ khớp là mốc neo.
        let a = old.map(plain), b = new.map(plain)
        var table = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        if !a.isEmpty, !b.isEmpty {
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var result = old
        var i = 0, j = 0, startI = 0, startJ = 0
        func settle(_ endI: Int, _ endJ: Int) {
            // Đoạn giữa hai mốc neo: cùng số từ thì xét từng cặp, khác số từ (mô hình thêm bớt từ) thì giữ câu gốc.
            guard endI - startI == endJ - startJ else { return }
            for k in 0..<(endI - startI) where accepts(old[startI + k], new[startJ + k]) {
                result[startI + k] = Proofreader.cased(new[startJ + k].lowercased(), like: old[startI + k])
            }
        }
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                settle(i, j)
                if accepts(old[i], new[j]) { result[i] = Proofreader.cased(new[j].lowercased(), like: old[i]) }
                i += 1; j += 1
                startI = i; startJ = j
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        settle(a.count, b.count)
        var out = "", index = 0
        for p in source {
            switch p {
            case .gap(let g): out += g
            case .word:
                out += result[index]
                index += 1
            }
        }
        return out
    }

    /// Hai câu giống nhau khi không tính hoa/thường và chỗ đặt dấu thanh ("khoẻ" như "khỏe").
    public static func same(_ a: String, _ b: String) -> Bool {
        func keys(_ s: String) -> [String] {
            pieces(s).map { p in
                switch p {
                case .word(let w): return Charset.syllableKey(w) ?? w.lowercased()
                case .gap(let g): return g
                }
            }
        }
        return keys(a) == keys(b)
    }
}
