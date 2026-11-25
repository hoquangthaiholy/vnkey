import Foundation

/// Một chỗ trong văn bản mà VNKey nghĩ là gõ sai, kèm chữ đề nghị thay. VNKey không tự thay: app gạch chân và
/// người dùng chọn.
public struct ProofIssue: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// Từ có dấu nhưng chưa thành từ ("viêt", "đươc").
        case missingMark
        /// Phím dấu thanh gõ trượt sang phím kề bên ("veeg" là "về").
        case slippedKey
        /// Hai phím gõ đảo chỗ ("tieegns" là "tiếng").
        case swappedKeys
        /// Lỗi gõ người dùng đã tự sửa nhiều lần ("goc" là "gõ").
        case learnedTypo
        /// Từ có dấu thanh gõ nhầm ("vễ" là "về").
        case wrongTone
        /// Chữ đúng cấu tạo âm tiết nhưng không phải từ, và từ gần nhất khác nó ở một cặp âm hay lẫn ("dới" là "với").
        case spelling
        /// Hai từ liền nhau cùng cần sửa, hoặc một cụm không dấu mà người dùng hay gõ có dấu.
        case phrase
        /// Từ tiếng Anh sai chính tả.
        case english
    }
    /// Vị trí tính theo đơn vị UTF-16 trong văn bản được soát (khớp `CFRange` của Accessibility).
    public var range: Range<Int>
    /// Chữ đang hiện: một từ, hoặc cả cụm.
    public var text: String
    public var kind: Kind
    /// Tối đa ba chữ đề nghị, hợp nhất đứng đầu.
    public var suggestions: [String]
    /// Sai chính tả (người viết tưởng chữ đó đúng) chứ không phải gõ nhầm phím. App tô hai loại bằng hai màu.
    public var isMisspelling: Bool { kind == .spelling || kind == .english }

    public init(range: Range<Int>, text: String, kind: Kind, suggestions: [String]) {
        self.range = range; self.text = text; self.kind = kind; self.suggestions = suggestions
    }
}

/// Soát một đoạn văn bản: tìm từ nghi gõ sai và chữ đề nghị thay. Thay cho việc tự sửa trong `Engine` (người dùng
/// chốt 2026-11-25: VNKey không tự thay chữ nữa, chỉ còn tự trả lại từ tiếng Anh). Vì không tự thay nên không cần
/// các ngưỡng "thắng rõ ràng" của bản tự sửa; thứ phải giữ chặt là KHÔNG gạch chân từ đúng:
/// - từ có dấu chỉ bị gạch khi nó không có trong bảng tần suất, người dùng không hay gõ nó, và có ứng viên trong bảng;
/// - từ không dấu là một âm tiết đúng cấu tạo ("goc", "nhat", "toi") không bao giờ bị gạch riêng lẻ (người ta vẫn
///   viết không dấu), trừ lỗi gõ chính họ đã sửa nhiều lần và cụm họ hay gõ có dấu;
/// - chữ không ra từ nào chỉ bị gạch khi có chữ đề nghị.
/// Không giữ trạng thái giữa các lần gọi. `lexicon` và `context` không an toàn giữa các luồng: gọi ở cùng luồng với
/// `Engine`.
public final class Proofreader {
    public var config = Config()
    public var lexicon: Lexicon?
    public var context: ContextModel?
    /// Có soát từ tiếng Anh không.
    public var checkEnglish = false
    /// Một từ đơn hiếm nhưng có trong từ điển, không được từ bên cạnh ủng hộ, chỉ bị gạch khi đề nghị đứng đầu là
    /// thêm dấu và gặp ít nhất chừng này lần trong kho ngữ liệu. Là tham số để `vnkey-tool rare-words` so các ngưỡng.
    public var rareWordFloor = 1000
    /// Số lần một âm tiết gặp trong kho ngữ liệu (0 nếu dưới 100 lần), cho công cụ đo.
    public static func frequency(of word: String) -> Int { CommonWords.count(word) }
    /// Từ không soát (chữ thường): từ người dùng bảo bỏ qua, từ đã nhớ là giữ phím gốc / giữ tiếng Việt.
    public var skip: Set<String> = []

    public init() {}

    private struct Token {
        var text: String
        var lower: String
        var range: Range<Int>
        /// Cách từ đứng trước chỉ bằng dấu cách (cùng một cụm).
        var joined: Bool
        var code: Bool
        var marked: Bool { text.contains { !$0.isASCII } }
    }

    private struct Finding {
        var kind: ProofIssue.Kind
        var suggestions: [String]
    }

    private static let limit = 3
    /// Chữ đang hiện của mỗi lỗi gõ đã học (chữ thường) -> chuỗi phím đúng. Dựng lại ở đầu mỗi lần soát: bảng lỗi gõ
    /// lưu theo chuỗi phím ("muoon"), còn trên màn hình là chữ ("muôn").
    private var learned: [String: String] = [:]
    private static let addressMarks: Set<Character> = [".", "/", ":", "\\"]

    /// `caret`: vị trí con trỏ (UTF-16); từ chứa nó hoặc đứng ngay trước nó là từ đang gõ dở, chưa soát.
    public func check(_ text: String, caret: Int? = nil) -> [ProofIssue] {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return [] }
        learned = [:]
        for t in context?.knownTypos() ?? [] {
            learned[t.wrong] = t.right
            if let c = Composer.replay(Array(t.wrong), config) { learned[c.shown.lowercased()] = t.right }
        }
        var findings = [Finding?](repeating: nil, count: tokens.count)
        var issues: [ProofIssue] = []
        var taken = Set<Int>()

        func usable(_ t: Token) -> Bool {
            if let caret, caret >= t.range.lowerBound, caret <= t.range.upperBound { return false }
            if t.code || t.text.count < 2 || skip.contains(t.lower) { return false }
            return !(t.text == t.text.uppercased() && t.text != t.lower)  // viết hoa toàn bộ: chữ viết tắt
        }
        func slice(_ a: Token, _ b: Token) -> (range: Range<Int>, gap: String) {
            let u = Array(text.utf16)
            return (a.range.lowerBound..<b.range.upperBound, String(utf16CodeUnits: Array(u[a.range.upperBound..<b.range.lowerBound]), count: b.range.lowerBound - a.range.upperBound))
        }

        // Cụm không dấu mà người dùng hay gõ có dấu ("lam loi" -> "lầm lỗi"): bằng chứng là thói quen của chính họ.
        if let model = context {
            for i in tokens.indices.dropFirst() where tokens[i].joined && !taken.contains(i - 1) {
                let a = tokens[i - 1], b = tokens[i]
                guard usable(a), usable(b), !a.marked, !b.marked,
                    let hit = model.phrase(plainPrev: a.lower, plainWord: b.lower), hit.prev != a.lower || hit.word != b.lower
                else { continue }
                let s = slice(a, b)
                issues.append(
                    ProofIssue(
                        range: s.range, text: a.text + s.gap + b.text, kind: .phrase,
                        suggestions: [Proofreader.cased(hit.prev, like: a.text) + s.gap + Proofreader.cased(hit.word, like: b.text)]))
                taken.insert(i - 1); taken.insert(i)
            }
        }

        for (i, t) in tokens.enumerated() where !taken.contains(i) && usable(t) {
            let prev = t.joined ? tokens[i - 1] : nil
            let next = i + 1 < tokens.count && tokens[i + 1].joined ? tokens[i + 1] : nil
            findings[i] = learnedTypo(t) ?? (t.marked ? missingMark(t, prev, next) ?? wrongCompound(t, prev, next) : plainWord(t, prev, next))
        }

        // Hai từ liền nhau cùng cần sửa: gộp thành một chỗ, đề nghị cả cụm (cặp nào hay đi với nhau đứng trước).
        var i = 0
        while i < tokens.count {
            guard let f = findings[i] else { i += 1; continue }
            let t = tokens[i]
            if i + 1 < tokens.count, tokens[i + 1].joined, let g = findings[i + 1] {
                let u = tokens[i + 1], s = slice(t, u)
                var combos: [(text: String, score: Int, order: Int)] = []
                for (x, a) in f.suggestions.enumerated() {
                    for (y, b) in g.suggestions.enumerated() {
                        let la = a.lowercased(), lb = b.lowercased()
                        let score = 1000 * (context?.pairCount(lb, after: la) ?? 0) + CommonPairs.count(lb, after: la)
                        combos.append((a + s.gap + b, score, x + y))
                    }
                }
                combos.sort { ($0.score, -$0.order) > ($1.score, -$1.order) }
                issues.append(
                    ProofIssue(
                        range: s.range, text: t.text + s.gap + u.text, kind: f.kind == .spelling && g.kind == .spelling ? .spelling : .phrase,
                        suggestions: Array(combos.prefix(Proofreader.limit).map(\.text))))
                i += 2
            } else {
                issues.append(ProofIssue(range: t.range, text: t.text, kind: f.kind, suggestions: f.suggestions))
                i += 1
            }
        }
        return issues.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    // MARK: - Tách từ

    /// Từ = một mạch chữ cái (dấu nháy đơn giữa hai chữ cái thuộc về từ: "don't"). Chỉ dấu cách nối hai từ thành
    /// một cụm, như khi đếm bảng cặp âm tiết (`CommonPairs.encode`); dấu câu, chữ số, xuống dòng cắt mạch.
    private func tokenize(_ text: String) -> [Token] {
        let chars = Array(text)
        var offsets = [Int](repeating: 0, count: chars.count + 1)
        for (i, c) in chars.enumerated() { offsets[i + 1] = offsets[i] + c.utf16.count }
        func at(_ i: Int) -> Character? { i >= 0 && i < chars.count ? chars[i] : nil }
        let vni = !config.method.isTelex
        /// Mạch chữ-và-số kết thúc ở `i` có bắt đầu bằng một chữ cái không (số đứng đầu thì là con số, không phải từ).
        func started(_ i: Int) -> Bool {
            var j = i - 1
            while j >= 0, chars[j].isNumber, chars[j].isASCII { j -= 1 }
            return j >= 0 && chars[j].isLetter
        }
        func isWord(_ i: Int) -> Bool {
            guard let c = at(i) else { return false }
            if c.isLetter { return true }
            // VNI: chữ số đứng sau chữ cái là phím dấu của từ đó ("tie61gn", "gor4").
            if vni, c.isNumber, c.isASCII, at(i - 1).map({ $0.isLetter || $0.isNumber }) ?? false { return i > 0 && started(i) }
            return (c == "'" || c == "’") && (at(i - 1)?.isLetter ?? false) && (at(i + 1)?.isLetter ?? false)
        }
        var out: [Token] = []
        var i = 0, lastEnd: Int?
        while i < chars.count {
            guard isWord(i) else { i += 1; continue }
            let start = i
            while isWord(i) { i += 1 }
            let before = at(start - 1), after = at(i), after2 = at(i + 1)
            var code = before.map { Engine.codeMarks.contains($0) || $0.isNumber } ?? false
            if let after {
                if after == "_" || after == "@" || after.isNumber {
                    code = true
                } else if Proofreader.addressMarks.contains(after), let after2, after2.isLetter || after2.isNumber || after2 == "/" {
                    code = true  // tên miền, tên tệp, địa chỉ: "viêt.vn", "a.txt", "http://"
                }
            }
            let joined = lastEnd.map { $0 < start && chars[$0..<start].allSatisfy { $0 == " " } } ?? false
            let word = String(chars[start..<i])
            out.append(
                Token(
                    text: word, lower: word.precomposedStringWithCanonicalMapping.lowercased(),
                    range: offsets[start]..<offsets[i], joined: joined, code: code))
            lastEnd = i
        }
        return out
    }

    // MARK: - Từ có dấu

    private static func mark(of plain: Character) -> Mark {
        switch plain {
        case "â", "ê", "ô": return .hat
        case "ă": return .breve
        case "ơ", "ư": return .horn
        case "đ": return .bar
        default: return .none
        }
    }

    /// Dựng lại trạng thái gõ của một từ từ chính các chữ đang hiện (không có chuỗi phím), để hỏi `Predictor`.
    private func composer(from word: String) -> Composer? {
        var c = Composer(config)
        for ch in word.precomposedStringWithCanonicalMapping {
            var plain = ch, upper = false
            if let i = Charset.letterInfo(ch) {
                if i.tone != .none {
                    if c.tone != .none { return nil }
                    c.tone = i.tone
                }
                plain = i.plain; upper = i.upper
            } else {
                guard ch.isASCII, ch.isLetter, let l = ch.lowercased().first else { return nil }
                plain = l; upper = ch.isUppercase
            }
            var letter = Letter(base: Syl.unmark(plain))
            letter.mark = Proofreader.mark(of: plain)
            letter.upper = upper
            c.letters.append(letter)
        }
        return c
    }

    private typealias Option = (word: String, mine: Int, corpus: Int, base: Int)

    /// Từ có dấu nhưng không có trong bảng. Hai cách hiểu:
    /// - GÕ NHẦM (`.missingMark`): thiếu phím dấu ("viêt", "đươc", "tiêng"). Đề nghị các cách THÊM dấu ra từ trong bảng;
    /// - SAI CHÍNH TẢ (`.spelling`): chữ là âm tiết đúng cấu tạo, và đổi một cặp âm hay lẫn thì ra từ trong bảng ("dới"
    ///   là "với"; xem `mixups`).
    /// Mọi ứng viên xếp chung theo cặp từ chính người dùng đã gõ, rồi cặp trong kho ngữ liệu (với từ trước lẫn từ sau),
    /// rồi độ thông dụng; ứng viên đứng đầu thuộc cách hiểu nào thì chỗ đó mang loại ấy ("việc dới" -> với: sai chính
    /// tả; "nhiệt dới" -> đới: gõ thiếu). Chữ không phải âm tiết đúng cấu tạo luôn là gõ nhầm.
    private func missingMark(_ t: Token, _ prev: Token?, _ next: Token?) -> Finding? {
        if CommonWords.count(t.lower) >= CommonWords.tableFloor { return nil }
        if (context?.count(t.lower) ?? 0) >= 2 { return nil }  // từ của chính người dùng
        // Âm tiết là một phần của từ ghép với từ bên cạnh ("bánh chưng": "chưng" không có trong bảng tần suất): từ thật.
        if inCompound(t.lower, prev, next) { return nil }
        var marked: [Option] = []
        if let comp = composer(from: t.text), comp.hasVowel { marked = markOptions(for: comp, prev, next) }
        var mixed: [Option] = []
        if Charset.syllableKey(t.lower) != nil {
            let known = Set(marked.map { $0.word.lowercased() })
            mixed = mixups(t.lower).filter { !known.contains($0) }.map { w in
                let around = neighbours(w, prev, next)
                return (Proofreader.cased(w, like: t.text), around.mine, around.corpus, CommonWords.count(w) + 1000 * (context?.count(w) ?? 0))
            }
        }
        // Gõ nhầm phím dấu thanh ("vễ" là "về"): thử mọi thanh khác. Ít chắc hơn hai cách trên nên điểm thông dụng chia 10;
        // từ bên cạnh vẫn quyết định trước ("đi vễ nhà" -> về).
        var retoned: [Option] = []
        if Charset.syllableKey(t.lower) != nil {
            let known = Set((marked + mixed).map { $0.word.lowercased() })
            retoned = otherTones(t.lower).filter { !known.contains($0) }.map { w in
                let around = neighbours(w, prev, next)
                return (Proofreader.cased(w, like: t.text), around.mine, around.corpus, (CommonWords.count(w) + 1000 * (context?.count(w) ?? 0)) / 10)
            }
        }
        // Xếp ổn định: bằng điểm thì cách thêm dấu (ít thay đổi hơn) đứng trước, rồi lẫn âm, rồi đổi thanh.
        let tagged = marked.map { ($0, ProofIssue.Kind.missingMark) } + mixed.map { ($0, .spelling) } + retoned.map { ($0, .wrongTone) }
        let all = tagged.enumerated().sorted { a, b in
            let x = a.element.0, y = b.element.0
            return (x.mine, x.corpus, x.base, -a.offset) > (y.mine, y.corpus, y.base, -b.offset)
        }
        guard let top = all.first else { return nil }
        // Từ đơn hiếm nhưng có thật theo từ điển ("quẫy", "rưng", "tậu", "cốm"): chỉ gạch khi
        // - đề nghị đứng đầu là THÊM DẤU ra một từ thông dụng (≥ `rareWordFloor` = 1000 lần): "rưng" -> rừng, "dúng" ->
        //   đúng, "ròi" -> rồi. Gõ thiếu một phím dấu là lỗi gõ hay gặp nhất;
        // - hoặc đề nghị đứng đầu hay đi với từ bên cạnh (cặp của người dùng, bảng cặp, từ ghép).
        // Đề nghị kiểu lẫn âm hay đổi thanh mà không có từ bên cạnh ủng hộ thì bỏ: với một từ có thật đó chỉ là phỏng
        // đoán ("tậu" không phải "tạo" viết sai). Đo trên 2.894 từ hiếm của từ điển (`vnkey-tool rare-words`,
        // 2026-11-25): ngưỡng 1000 cho mọi loại gạch 1.200 từ thật; chỉ tính loại thêm dấu thì còn 165.
        // "Hay đi với từ bên cạnh" với loại thêm dấu là có trong bảng cặp; với loại lẫn âm / đổi thanh phải mạnh hơn
        // nhiều (`strongPair`), vì một từ rất thông dụng đi được với gần như mọi từ ("ấy tạo" có trong bảng cặp, nhưng
        // "anh ấy tậu xe" không sai).
        let best = top.element.0
        if Compounds.isRareWord(t.lower), best.mine == 0 {
            let addsMark = top.element.1 == .missingMark
            let supported = best.corpus >= (addsMark ? CommonPairs.floor : Proofreader.strongPair)
            if !supported, !addsMark || CommonWords.count(best.word) < rareWordFloor { return nil }
        }
        return Finding(kind: top.element.1, suggestions: Array(all.prefix(Proofreader.limit).map { $0.element.0.word }))
    }

    /// Các cách thêm dấu cho `comp` ra từ có trong bảng, đã xếp thứ tự (gõ thiếu một phím dễ xảy ra hơn thiếu hai:
    /// "dúng" là "đúng" trước "đứng"). Kể cả chính `comp` nếu chữ nó hiện đã là một từ trong bảng (khi `comp` dựng từ
    /// chuỗi phím còn nằm nguyên trên màn hình: "tieesng" là "tiếng").
    private func markOptions(for comp: Composer, _ prev: Token?, _ next: Token?) -> [Option] {
        var seen = Set<String>()
        let options = ([comp] + Predictor.candidates(for: comp, teen: false)).filter {
            let w = $0.shown.lowercased()
            return CommonWords.count(w) >= CommonWords.tableFloor && seen.insert(w).inserted
        }
        func missing(_ c: Composer) -> Int { (c.markCount - comp.markCount) + (c.tone != comp.tone ? 1 : 0) }
        let least = options.map(missing).min() ?? 0
        return options.map { c -> Option in
            let w = c.shown.lowercased()
            let around = neighbours(w, prev, next)
            var base = CommonWords.count(w) + 1000 * (context?.count(w) ?? 0)
            for _ in 0..<min(missing(c) - least, 6) { base /= 10 }
            return (c.shown, around.mine, around.corpus, base)
        }.sorted { ($0.mine, $0.corpus, $0.base) > ($1.mine, $1.corpus, $1.base) }
    }

    private func marks(for comp: Composer, _ prev: Token?, _ next: Token?) -> Finding? {
        let ranked = markOptions(for: comp, prev, next)
        return ranked.isEmpty ? nil : Finding(kind: .missingMark, suggestions: Array(ranked.prefix(Proofreader.limit).map(\.word)))
    }

    // MARK: - Sai chính tả

    // Bảng lỗi chính tả thường gặp trong tiếng Việt, xếp theo vị trí trong âm tiết. Nguồn là các nhóm lỗi quen thuộc
    // trong sách dạy chính tả: lẫn do phát âm vùng miền (Bắc: l/n, ch/tr, s/x, d/gi/r; Nam: v/d, n/ng, t/c, hỏi/ngã,
    // vần ngắn ă/â; Bắc Trung Bộ: hỏi/ngã/nặng) và lẫn do quy tắc viết (c/k, g/gh, ng/ngh, i/y). Mỗi nhóm là các cách
    // viết người ta hay dùng nhầm cho nhau; ứng viên chỉ được nhận khi là âm tiết đúng và có trong bảng tần suất.

    /// Âm đầu.
    private static let initialMixups: [[String]] = [
        ["d", "gi", "r", "v"],  // da/gia/ra; Nam Bộ đọc v thành d ("dới" là "với")
        ["s", "x"], ["ch", "tr"], ["l", "n"],
        ["c", "k"], ["g", "gh"], ["ng", "ngh"],  // quy tắc: k, gh, ngh đứng trước i, e, ê
        ["d", "nh"],  // Nam Bộ: "nhiều" / "diều"
        ["h", "qu"], ["qu", "v"],  // "hoang" / "quang", "quay" / "vay"
    ]
    /// Âm cuối.
    private static let finalMixups: [[String]] = [
        ["n", "ng", "nh"],  // an/ang, in/inh, ên/ênh
        ["t", "c", "ch"],  // at/ac, it/ich, êt/êch
    ]
    /// Vần (phần nguyên âm, kể cả bán âm cuối i/y/o/u).
    private static let nucleusMixups: [[String]] = [
        ["i", "y"],  // lí/lý, kĩ/kỹ
        ["i", "iê"], ["u", "uô"], ["ư", "ươ"],  // kím/kiếm, chuột/chụt, bưu/bươu
        ["iu", "iêu", "ưu", "ươu"],  // hưu/hươu, rượu/riệu, lưu/liu
        ["êu", "iêu"],
        ["ui", "uôi", "uy"],  // mũi/muỗi, quí/quý
        ["ưi", "ươi"],
        ["ai", "ay", "ây"],  // tai/tay, mày/mầy
        ["ao", "au", "âu"],  // sao/sau, màu/mầu
        ["oai", "oay"], ["oi", "ôi", "ơi"],
        ["ă", "â"],  // vần ngắn: chăn/chân, sắp/sấp
        ["o", "ô"], ["ô", "ơ"],  // ong/ông, hôn/hơn
        ["e", "ê"], ["ê", "iê"],
        ["oa", "ua"], ["oe", "ue"], ["uâ", "uô"],
    ]
    /// Thanh: hỏi / ngã (Nam, Trung), ngã / nặng (Nghệ Tĩnh).
    private static let toneMixups: [[Tone]] = [[.hoi, .nga], [.nga, .nang]]

    /// Các từ trong bảng khác `word` (chữ thường, một âm tiết đúng cấu tạo) đúng MỘT chỗ hay lẫn: âm đầu, vần, âm
    /// cuối hoặc thanh.
    private func mixups(_ word: String, anySyllable: Bool = false) -> [String] {
        let (plain, tone) = Proofreader.split(word)
        var out: [String] = []
        func add(_ ini: String, _ nuc: String, _ fin: String, _ tone: Tone) {
            let chars = Array(ini + nuc + fin)
            guard Syl.isValid(chars, tone: tone, teen: false), let w = spell(chars, tone), w != word,
                anySyllable || CommonWords.count(w) >= CommonWords.tableFloor, !out.contains(w)
            else { return }
            out.append(w)
        }
        for p in Syl.parse(plain) {
            for group in Proofreader.initialMixups where group.contains(p.ini) {
                for other in group where other != p.ini { add(other, p.nuc, p.fin, tone) }
            }
            for group in Proofreader.finalMixups where group.contains(p.fin) {
                for other in group where other != p.fin { add(p.ini, p.nuc, other, tone) }
            }
            for group in Proofreader.nucleusMixups where group.contains(p.nuc) {
                for other in group where other != p.nuc { add(p.ini, other, p.fin, tone) }
            }
            for group in Proofreader.toneMixups where group.contains(tone) {
                for other in group where other != tone { add(p.ini, p.nuc, p.fin, other) }
            }
        }
        return out
    }

    /// Tách một từ (chữ thường) thành các chữ cái đã bỏ thanh và thanh của nó.
    private static func split(_ word: String) -> (plain: [Character], tone: Tone) {
        var plain: [Character] = []
        var tone = Tone.none
        for ch in word {
            if let i = Charset.letterInfo(ch) {
                if i.tone != .none { tone = i.tone }
                plain.append(i.plain)
            } else {
                plain.append(ch)
            }
        }
        return (plain, tone)
    }

    /// Các từ trong bảng chỉ khác `word` ở dấu thanh (kể cả không dấu). Chỉ cho từ đang mang một dấu thanh: từ chưa có
    /// thanh là việc của phần thêm dấu.
    private func otherTones(_ word: String) -> [String] {
        let (plain, tone) = Proofreader.split(word)
        guard tone != .none else { return [] }
        var out: [String] = []
        for other in [Tone.none, .sac, .huyen, .hoi, .nga, .nang] where other != tone {
            guard Syl.isValid(plain, tone: other, teen: false), let w = spell(plain, other),
                CommonWords.count(w) >= CommonWords.tableFloor, !out.contains(w)
            else { continue }
            out.append(w)
        }
        return out
    }

    /// Chữ là một âm tiết có thật nhưng đứng sai chỗ ("bánh trưng", "dữ gìn", "sữa chữa"): nó không tạo thành từ ghép
    /// với từ bên cạnh, cặp đó KHÔNG HỀ gặp trong kho ngữ liệu, người dùng chưa từng gõ cặp đó, còn đổi một âm hay lẫn
    /// thì ra một từ ghép trong từ điển. Điều kiện chặt để không gạch từ đúng: "ăn chưa" hay gặp nên không bị đổi
    /// thành "ăn trưa". Không đụng tới i / y ("xử lí" và "xử lý" đều được chấp nhận).
    private func wrongCompound(_ t: Token, _ prev: Token?, _ next: Token?) -> Finding? {
        guard CommonWords.count(t.lower) >= CommonWords.tableFloor, prev != nil || next != nil,
            !inCompound(t.lower, prev, next), neighbours(t.lower, prev, next).mine == 0
        else { return nil }
        func plainIY(_ w: String) -> String { String(Charset.stripMarks(w).map { $0 == "y" ? "i" : $0 }) }
        var found: [(word: String, support: Int)] = []
        for v in mixups(t.lower, anySyllable: true) where plainIY(v) != plainIY(t.lower) || Charset.stripMarks(v) == Charset.stripMarks(t.lower) {
            var support = 0
            if let p = prev?.lower, Compounds.contains(p, v), CommonPairs.count(t.lower, after: p) == 0 {
                support += 1 + CommonPairs.count(v, after: p)
            }
            if let n = next?.lower, Compounds.contains(v, n), CommonPairs.count(n, after: t.lower) == 0 {
                support += 1 + CommonPairs.count(n, after: v)
            }
            if support > 0 { found.append((Proofreader.cased(v, like: t.text), support)) }
        }
        guard !found.isEmpty else { return nil }
        found.sort { $0.support > $1.support }
        return Finding(kind: .spelling, suggestions: Array(found.prefix(Proofreader.limit).map(\.word)))
    }

    /// Viết một âm tiết (chữ thường đã có dấu mũ/móc, thanh truyền riêng) thành chữ, dấu thanh đặt đúng chỗ.
    private func spell(_ plain: [Character], _ tone: Tone) -> String? {
        var c = Composer(config)
        for ch in plain {
            var letter = Letter(base: Syl.unmark(ch))
            letter.mark = Proofreader.mark(of: ch)
            c.letters.append(letter)
        }
        c.tone = tone
        let s = c.shown
        return s.isEmpty ? nil : s
    }

    /// Điểm cộng khi ứng viên tạo thành một từ ghép trong từ điển với từ bên cạnh: ngang một cặp gặp vài trăm lần
    /// trong kho ngữ liệu (từ điển không có số đếm).
    private static let compoundBonus = 300
    /// Mức "hay đi với từ bên cạnh" đủ để nghi một từ hiếm CÓ THẬT là viết sai của từ khác (lẫn âm, đổi thanh): các
    /// cặp với từ bên cạnh gặp tổng cộng từ 100 lần, hoặc là từ ghép trong từ điển (`compoundBonus` đã vượt mức này).
    /// Thử 40 / 60 / 100 / 200 (2026-11-25): ở 40 "anh ấy tậu xe" bị gạch nhầm, ở 200 "trời xắp mưa" bị bỏ sót.
    private static let strongPair = 100

    private func inCompound(_ w: String, _ prev: Token?, _ next: Token?) -> Bool {
        (prev.map { Compounds.contains($0.lower, w) } ?? false) || (next.map { Compounds.contains(w, $0.lower) } ?? false)
    }

    /// Từ `w` hay đi với hai từ bên cạnh tới đâu: theo thói quen của người dùng, và theo kho ngữ liệu cùng từ điển
    /// từ ghép.
    private func neighbours(_ w: String, _ prev: Token?, _ next: Token?) -> (mine: Int, corpus: Int) {
        var mine = 0, corpus = 0
        if let p = prev?.lower {
            mine += context?.pairCount(w, after: p) ?? 0
            corpus += CommonPairs.count(w, after: p) + (Compounds.contains(p, w) ? Proofreader.compoundBonus : 0)
        }
        if let n = next?.lower {
            mine += context?.pairCount(n, after: w) ?? 0
            corpus += CommonPairs.count(n, after: w) + (Compounds.contains(w, n) ? Proofreader.compoundBonus : 0)
        }
        return (mine, corpus)
    }

    /// Lỗi gõ chính người dùng đã sửa đủ nhiều lần ("goc" -> "gox" = gõ, "muôn" -> "muốn"), kể cả khi chữ gõ ra là một
    /// từ thật: bằng chứng là các lần họ sửa, và số lần họ để nguyên (`ContextModel.keepTypo`) chặn sửa nhầm.
    private func learnedTypo(_ t: Token) -> Finding? {
        guard let right = learned[t.lower],
            let fixed = Composer.replay(Array(Proofreader.cased(right, like: t.text)), config), fixed.shown != t.text
        else { return nil }
        return Finding(kind: .learnedTypo, suggestions: [fixed.shown])
    }

    // MARK: - Từ không dấu

    private func plainWord(_ t: Token, _ prev: Token?, _ next: Token?) -> Finding? {
        let keys = Array(t.text)
        let plainKeys = Engine.isPlainKeys(t.text)
        if Engine.builtinEnglish.contains(t.lower) || lexicon?.isEnglish(t.lower) == true { return nil }
        if Charset.syllableKey(t.lower) != nil { return nil }  // âm tiết không dấu đúng cấu tạo: người ta vẫn viết vậy
        if plainKeys, let comp = Composer.replay(keys, config) {
            if let f = swapped(keys, comp) ?? slipped(keys, comp, prev, next) { return f }
            // Chuỗi phím còn nằm nguyên trên màn hình vì gõ ra chữ chưa thành từ ("duojc" là "duọc"), hoặc gõ khi
            // VNKey đang tắt ("tieesng"): đề nghị từ có dấu gần nhất.
            if !comp.isLiteral, comp.hasVowel, comp.shown.contains(where: { !$0.isASCII }), let f = marks(for: comp, prev, next) {
                return f
            }
            // Chữ chưa có dấu nào, kết thúc bằng c/ch/p/t ("viet", "duoc"): âm tiết như vậy bắt buộc có dấu sắc hoặc
            // nặng. Người viết không dấu vẫn viết thế, nên chỉ gạch khi từ bên cạnh CÓ dấu (họ đang gõ có dấu).
            if !comp.isLiteral, comp.hasVowel, comp.tone == .none, prev?.marked == true || next?.marked == true,
                ["c", "p", "t"].contains(where: { t.lower.hasSuffix($0) }) || t.lower.hasSuffix("ch"), let f = marks(for: comp, prev, next)
            {
                return f
            }
        }
        return english(t, prev, next)
    }

    /// Đổi chỗ hai phím liền nhau thì ra một từ có dấu trong bảng ("tieegns" -> "tiếng").
    private func swapped(_ keys: [Character], _ comp: Composer) -> Finding? {
        guard (3...10).contains(keys.count) else { return nil }
        if !comp.isLiteral, comp.hasVowel, Syl.isValid(comp.plainChars, tone: comp.tone, teen: config.teenInitials) { return nil }
        var found: [(word: String, count: Int)] = []
        for i in 0..<(keys.count - 1) where keys[i] != keys[i + 1] {
            var k = keys
            k.swapAt(i, i + 1)
            guard let c = Composer.replay(k, config), !c.isLiteral, c.hasVowel,
                Syl.isValid(c.plainChars, tone: c.tone, teen: false)
            else { continue }
            let s = c.shown, n = CommonWords.count(s)
            guard s.contains(where: { !$0.isASCII }), n >= CommonWords.tableFloor, !found.contains(where: { $0.word == s }) else { continue }
            found.append((s, n))
        }
        guard !found.isEmpty else { return nil }
        found.sort { $0.count > $1.count }
        return Finding(kind: .swappedKeys, suggestions: Array(found.prefix(Proofreader.limit).map(\.word)))
    }

    /// Phím gõ ra -> các phím dấu thanh nằm sát nó trên bàn phím QWERTY (phím người dùng có thể đã định gõ). Chỉ gồm
    /// phụ âm. Không có "k" (sát "j"): chữ teen hay kết thúc bằng k ("bik", "hok", "ak"). Không có nguyên âm và m, n:
    /// chúng là phần cuối bình thường của một từ ("ae", "hom").
    private static let telexSlips: [Character: [Character]] = [
        "d": ["s", "f", "r", "x"], "z": ["s", "x"], "g": ["f"], "v": ["f"], "c": ["f", "x"], "t": ["f", "r"], "h": ["j"],
    ]
    private static let vniSlips: [Character: [Character]] = [
        "q": ["1", "2"], "w": ["2", "3"], "e": ["3", "4"], "r": ["4", "5"], "t": ["5"], "6": ["5"],
    ]

    /// Đổi phím CUỐI thành phím dấu thanh nằm sát nó thì ra một từ trong bảng hay đi với từ bên cạnh ("đó lag" ->
    /// "đó là": g sát f; "tôi veeg" -> "tôi về"). Phải có từ bên cạnh ủng hộ: "lag" đứng một mình là từ mượn.
    private func slipped(_ keys: [Character], _ comp: Composer, _ prev: Token?, _ next: Token?) -> Finding? {
        guard (2...10).contains(keys.count), comp.tone == .none, let last = keys.last, let low = last.lowercased().first,
            let intended = (config.method.isTelex ? Proofreader.telexSlips : Proofreader.vniSlips)[low],
            !Predictor.candidates(for: comp, teen: false).contains(where: { CommonWords.count($0.shown) >= CommonWords.tableFloor })
        else { return nil }
        var found: [(word: String, corpus: Int)] = []
        for k in intended {
            var fixed = keys
            fixed[fixed.count - 1] = last.isUppercase ? Character(k.uppercased()) : k
            guard let c = Composer.replay(fixed, config), !c.isLiteral, c.tone != .none,
                CommonWords.count(c.shown) >= CommonWords.tableFloor
            else { continue }
            let around = neighbours(c.shown.lowercased(), prev, next)
            let support = around.corpus + 1000 * around.mine
            if support >= CommonPairs.floor, !found.contains(where: { $0.word == c.shown }) { found.append((c.shown, support)) }
        }
        guard !found.isEmpty else { return nil }
        found.sort { $0.corpus > $1.corpus }
        return Finding(kind: .slippedKey, suggestions: Array(found.prefix(Proofreader.limit).map(\.word)))
    }

    /// Từ tiếng Anh sai chính tả: chỉ khi được bật, từ điển có chữ đề nghị, và không đứng cạnh một từ tiếng Việt có
    /// dấu (ở đó chữ lạ thường là chữ teen, tên riêng). Từ viết hoa chữ đầu coi là tên riêng.
    private func english(_ t: Token, _ prev: Token?, _ next: Token?) -> Finding? {
        guard checkEnglish, let lex = lexicon, t.text.count >= 3, t.text.first?.isLowercase == true,
            t.text.allSatisfy({ $0.isASCII }), Engine.teenExpansions[t.lower] == nil,
            prev?.marked != true, next?.marked != true
        else { return nil }
        let guesses = lex.englishGuesses(t.lower).filter { $0.lowercased() != t.lower }
        guard !guesses.isEmpty else { return nil }
        return Finding(kind: .english, suggestions: Array(guesses.prefix(Proofreader.limit)))
    }

    // MARK: - Thêm dấu cả câu

    /// Sửa cả câu KHÔNG cần mô hình ngôn ngữ (đường dự phòng cho máy không có Apple Intelligence, người dùng chốt
    /// 2026-11-25): chọn cho mỗi từ một cách viết sao cho cả câu "thuận" nhất, bằng bảng tần suất âm tiết, bảng cặp âm
    /// tiết, từ điển từ ghép và thói quen của người dùng (thuật toán Viterbi: mỗi từ được chọn theo cả từ trước lẫn từ
    /// sau). Ứng viên của một từ là chính nó và các cách THÊM dấu ra từ có trong bảng; từ có dấu mà không có trong bảng
    /// thì thêm cả các cách lẫn âm / đổi thanh. Từ có dấu đã đúng, từ tiếng Anh, chữ viết tắt, ngữ cảnh code giữ nguyên.
    /// Chỉ sửa chính tả và dấu: không viết lại, không dịch.
    public func restore(_ text: String) -> String {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return text }
        learned = [:]
        // Ứng viên của từng từ (chữ thường); phần tử đầu luôn là chính từ đó.
        var options: [[String]] = []
        var english = [Bool](repeating: false, count: tokens.count)
        /// Từ có dấu, có trong bảng, nhưng có cách viết khác tạo thành từ ghép với từ bên cạnh: không được ưu tiên giữ.
        var contested = [Bool](repeating: false, count: tokens.count)
        for (i, t) in tokens.enumerated() {
            var list = [t.lower]
            let fixed = t.code || skip.contains(t.lower) || (t.text.count > 1 && t.text == t.text.uppercased() && t.text != t.lower)
                || !t.text.allSatisfy(\.isLetter)
            // Từ tiếng Anh không bị khoá cứng: từ điển tiếng Anh nhận cả "co", "lam", "hop", "dang", "hoc". Nó chỉ được
            // cộng điểm cho cách viết gốc; câu quanh nó là tiếng Việt thì ứng viên có dấu vẫn thắng.
            english[i] = !t.marked && (Engine.builtinEnglish.contains(t.lower) || lexicon?.isEnglish(t.lower) == true)
            if !fixed {
                let prev = t.joined ? tokens[i - 1] : nil
                let next = i + 1 < tokens.count && tokens[i + 1].joined ? tokens[i + 1] : nil
                if t.marked, CommonWords.count(t.lower) >= CommonWords.tableFloor {
                    // Từ có dấu, có trong bảng: chỉ xét đổi khi một cách viết lẫn âm tạo thành TỪ GHÉP với từ bên cạnh
                    // ("chia sẽ" -> sẻ, "bánh trưng" -> chưng, "dữ gìn" -> giữ).
                    // Từ đang viết đã tạo thành từ ghép với từ bên cạnh ("ngày tết") thì không xét.
                    if !inCompound(t.lower, prev, next) {
                        list += mixups(t.lower, anySyllable: true).filter { inCompound($0, prev, next) }
                        contested[i] = list.count > 1
                    }
                } else if t.marked {
                    list += (missingMark(t, prev, next)?.suggestions ?? []).map { $0.lowercased() }
                } else if let comp = composer(from: t.text), comp.hasVowel {
                    var seen: Set<String> = [t.lower]
                    let marked = Predictor.candidates(for: comp, teen: false).map { $0.shown.lowercased() }
                        .filter { CommonWords.count($0) >= CommonWords.tableFloor && seen.insert($0).inserted }
                        .sorted { CommonWords.count($0) > CommonWords.count($1) }
                    list += marked.prefix(8)
                }
            }
            options.append(list)
        }
        // Điểm của một từ: độ thông dụng (thang log). Từ gốc không có trong bảng (chữ chưa có dấu, chữ lạ) được một
        // điểm sàn thấp, nên chỉ thắng khi không ứng viên nào hợp.
        func emission(_ w: String, original: Bool, marked: Bool, english: Bool, contested: Bool) -> Double {
            let n = CommonWords.count(w) + 1000 * (context?.count(w) ?? 0)
            var score = log(Double(n) + 1)
            if original, !contested { score += (marked ? 2 : n > 0 ? 0 : 2) + (english ? 3 : 0) }
            return score
        }
        func transition(_ a: String, _ b: String) -> Double {
            let n = CommonPairs.count(b, after: a) + 1000 * (context?.pairCount(b, after: a) ?? 0) + (Compounds.contains(a, b) ? Proofreader.compoundBonus : 0)
            return 2 * log(Double(n) + 1)
        }
        var best: [[Double]] = [], back: [[Int]] = []
        for i in tokens.indices {
            var row: [Double] = [], from: [Int] = []
            for (k, w) in options[i].enumerated() {
                let e = emission(w, original: k == 0, marked: tokens[i].marked, english: english[i], contested: contested[i])
                if i == 0 || !tokens[i].joined {
                    // Đầu câu hoặc sau dấu câu: không có từ đứng trước để xét, nhưng vẫn nối tiếp điểm tốt nhất phía trước.
                    let carry = i == 0 ? 0 : (best[i - 1].max() ?? 0)
                    row.append(carry + e)
                    from.append(i == 0 ? 0 : best[i - 1].firstIndex(of: best[i - 1].max() ?? 0) ?? 0)
                } else {
                    var top = -Double.infinity, arg = 0
                    for (j, p) in options[i - 1].enumerated() {
                        let s = best[i - 1][j] + transition(p, w)
                        if s > top { top = s; arg = j }
                    }
                    row.append(top + e)
                    from.append(arg)
                }
            }
            best.append(row)
            back.append(from)
        }
        var pick = [Int](repeating: 0, count: tokens.count)
        pick[tokens.count - 1] = best[tokens.count - 1].firstIndex(of: best[tokens.count - 1].max() ?? 0) ?? 0
        for i in stride(from: tokens.count - 1, to: 0, by: -1) { pick[i - 1] = back[i][pick[i]] }
        // Ghép lại: thay từng từ theo vị trí UTF-16, từ cuối lên để vị trí phía trước không xê dịch.
        var units = Array(text.utf16)
        for i in tokens.indices.reversed() where pick[i] != 0 {
            let word = Proofreader.cased(options[i][pick[i]], like: tokens[i].text)
            units.replaceSubrange(tokens[i].range, with: Array(word.utf16))
        }
        return String(utf16CodeUnits: units, count: units.count)
    }

    /// `word` (chữ thường) viết theo kiểu hoa/thường của `sample`.
    static func cased(_ word: String, like sample: String) -> String {
        if sample.count > 1, sample == sample.uppercased(), sample != sample.lowercased() { return word.uppercased() }
        if let f = sample.first, f.isUppercase { return word.prefix(1).uppercased() + word.dropFirst() }
        return word
    }
}
