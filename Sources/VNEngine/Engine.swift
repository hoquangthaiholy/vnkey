import Foundation

public struct Config: Sendable, Equatable {
    public var method: Method = .telex
    /// true: hoà, thuỷ — false: hòa, thủy.
    public var modernTone = false
    /// Telex: phím "w" đứng một mình thành "ư".
    public var standaloneW = true
    /// Telex: phím [ ] { } gõ ra ơ ư Ơ Ư.
    public var bracketKeys = false

    /// Phím này (ngoài chữ cái và chữ số) có thể là một phần của từ đang gõ.
    func isBracketKey(_ ch: Character) -> Bool {
        bracketKeys && method.isTelex && (ch == "[" || ch == "]" || ch == "{" || ch == "}")
    }
    /// Cho phép âm đầu teen f, j, w, z, dz (fải, zậy, jờ...).
    public var teenInitials = true
    /// Tự trả lại phím gốc khi từ không phải tiếng Việt.
    public var autoRestore = true
    /// Bung viết tắt teen (ko -> không...) khi kết thúc từ.
    public var expandTeen = false
    /// Gõ tắt do người dùng định nghĩa (khoá viết thường).
    public var macros: [String: String] = [:]
    /// Không biến đổi từ đứng ngay sau @ # / \ . _ : $ ~ = < & hoặc chữ số (email, đường dẫn, hashtag, tên biến).
    public var codeAware = true
    /// Sửa lỗi gõ đảo hai phím liền nhau (tieegns -> tiếng). Cần từ điển.
    public var fixTransposition = true
    /// Đang gõ một mạch tiếng Anh thì từ mơ hồ cũng coi là tiếng Anh. Cần từ điển.
    public var contextAware = true
    /// Tự viết hoa chữ đầu câu (sau . ! ? hoặc xuống dòng).
    public var autoCapitalize = false
    /// Xoá khoảng trắng thừa trước , . ; ! ?
    public var tidyPunctuation = false
    /// Xoá ngay từ vừa gõ rồi gõ lại đúng chuỗi phím đó: đổi sang dạng còn lại (phím gốc ↔ tiếng Việt) và nhớ.
    public var learnFromRetype = true
    /// Đoán từ định gõ khi từ có dấu nhưng chưa thành từ tiếng Việt đúng (duojc, đươc -> được). Cần từ điển.
    public var predict = true
    /// Tự sửa lỗi gõ mà người dùng đã tự sửa nhiều lần (goc -> gox = "gõ"). Cần `context`.
    public var fixTypos = true
    public init() {}
}

/// Tra từ điển để phân xử các từ hợp lệ ở cả hai ngôn ngữ. App cung cấp qua NSSpellChecker.
public protocol Lexicon: AnyObject {
    func isEnglish(_ word: String) -> Bool
    func isVietnamese(_ word: String) -> Bool
    /// Trong các ứng viên (chữ thường), từ nào hợp nhất với chữ đang hiện `typed` đứng sau các từ `context`;
    /// nil nếu không có ý kiến. Có thể chậm (vài ms): engine chỉ hỏi ở cuối một từ gõ chưa thành tiếng Việt.
    func rank(_ candidates: [String], after context: [String], typed: String) -> String?
}

extension Lexicon {
    public func rank(_ candidates: [String], after context: [String], typed: String) -> String? { nil }
}

/// Việc cần làm trên màn hình sau một phím.
public struct Output: Equatable, Sendable {
    /// Số ký tự cần xoá lùi trước con trỏ.
    public var backspaces = 0
    /// Văn bản cần chèn sau khi xoá.
    public var text = ""
    /// Phím gốc có được đi tiếp tới ứng dụng (sau `backspaces`/`text`) hay không.
    public var passKey = true

    public init(backspaces: Int = 0, text: String = "", passKey: Bool = true) {
        self.backspaces = backspaces; self.text = text; self.passKey = passKey
    }

    public static let pass = Output()
    public var isPass: Bool { backspaces == 0 && text.isEmpty && passKey }
}

public final class Engine {
    public var config: Config { didSet { reset() } }
    public weak var lexicon: Lexicon?
    /// Thói quen gõ của người dùng, để chọn từ theo ngữ cảnh khi đoán. Không có thì chỉ dùng danh sách dựng sẵn.
    public var context: ContextModel?
    /// Ghi chú về lần đoán từ ở phím vừa xử lý (cho nhật ký); rỗng nếu không đoán.
    public private(set) var note = ""
    /// Chữ vừa được VNKey tự sửa ở phím vừa xử lý (đoán dấu hoặc sửa gõ đảo phím), đúng như đang hiện trên màn
    /// hình: một từ, hoặc cả cụm hai từ kèm dấu cách khi sửa cả từ đứng trước. nil nếu không tự sửa gì. App dùng
    /// để nháy nhẹ lên đoạn chữ đó.
    public private(set) var fixedWord: String?

    /// Từ người dùng muốn giữ nguyên phím gốc / giữ tiếng Việt (khoá = phím gốc viết thường).
    public var preferRaw: Set<String> = []
    public var preferVN: Set<String> = []
    public var onLearn: (() -> Void)?

    private struct Entry {
        var comp: Composer
        var raw: String
        var composed: String
        var final: String
        var sep: String
        var resumable: Bool
        /// Chuỗi phím đúng như người dùng gõ (khác `raw` khi VNKey đã sửa gõ đảo phím).
        var typed: String
        /// Từ này đã được ghi vào thói quen gõ sau từ `prev`; quay lại sửa nó thì phải rút lại.
        var recorded: (word: String, prev: String?)? = nil
        /// VNKey đã thay chuỗi phím gõ sai `wrong` bằng `right` (lỗi gõ đã học).
        var typoFix: (wrong: String, right: String)? = nil
        /// Chuỗi phím này là một lỗi gõ đã biết mà lần này người dùng để nguyên (đã đếm); quay lại sửa thì rút lại.
        var keptTypo: String? = nil
        /// Từ này do VNKey đoán ra; đây là chữ đúng như người dùng đã gõ ("tiêng" khi đoán thành "tiếng").
        var asTyped: String? = nil
    }

    /// Dạng người dùng muốn nếu họ gõ lại từ này: true = giữ phím gốc.
    private struct Retype {
        var typed: String
        var wantRaw: Bool
    }

    private var comp: Composer
    private var screen = ""
    private var history: [Entry] = []
    private let historyLimit = 16
    /// Chuỗi ký tự ngắt từ kể từ từ gần nhất (để biết đầu câu, ngữ cảnh code).
    private var sepRun = ""
    /// Người dùng vừa xoá lùi: không tự viết hoa lại.
    private var capBlocked = false
    /// Số từ tiếng Anh liên tiếp vừa gõ.
    private var englishStreak = 0
    /// Từ gần nhất có hai dạng (phím gốc / tiếng Việt) và từ lúc đó chưa gõ chữ nào khác.
    private var freshBreak = false
    /// Người dùng đang xoá lùi chính từ đó.
    private var watch: Retype?
    /// Họ đã xoá hết từ đó; nếu gõ lại đúng chuỗi phím thì đổi sang dạng còn lại.
    private var retype: Retype?
    /// Chuỗi phím của từ ngay trước khi người dùng bắt đầu xoá nó. Nếu từ họ gõ xong sau đó chỉ khác đúng một
    /// phím thì đó là một lần sửa lỗi gõ ("goc" -> "gox"). Khác `watch`: gõ thêm chữ không làm mất nó.
    private var abandoned: String?

    static let codeMarks: Set<Character> = ["@", "#", "/", "\\", ".", "_", ":", "$", "~", "=", "<", "&"]

    public init(config: Config = Config()) {
        self.config = config
        comp = Composer(config)
    }

    /// Quên mọi trạng thái: gọi khi con trỏ có thể đã di chuyển (chuột, mũi tên, đổi app, phím tắt).
    public func reset() {
        comp = Composer(config); screen = ""; history = []
        sepRun = ""; capBlocked = false; englishStreak = 0
        forgetRecent()
    }

    private func forgetRecent() {
        freshBreak = false; watch = nil; retype = nil; abandoned = nil
    }

    /// Engine đang theo dõi chữ trước con trỏ (từ đang gõ hoặc từ vừa gõ xong).
    public var isTracking: Bool { !comp.isEmpty || !history.isEmpty }

    /// Từ đang gõ như engine tin là đang hiện trên màn hình.
    public var currentWord: String { screen }

    /// Trạng thái từ đang gõ, dùng cho nhật ký gỡ lỗi.
    public var debugState: String {
        var flags: [String] = []
        if comp.isLiteral { flags.append(comp.codeLiteral ? "code" : "literal") }
        if comp.cancelled { flags.append("cancelled") }
        if englishStreak > 0 { flags.append("en×\(englishStreak)") }
        return "raw=\"\(comp.rawString)\" shown=\"\(screen)\" hist=\(history.count)"
            + (flags.isEmpty ? "" : " [" + flags.joined(separator: ",") + "]")
    }

    // MARK: - Gõ

    public func type(_ ch: Character) -> Output {
        note = ""
        fixedWord = nil
        var fed = ch
        if comp.isEmpty, ch.isASCII, ch.isLetter {  // bắt đầu một từ mới
            comp = Composer(config)
            if config.codeAware, let l = sepRun.last, Engine.codeMarks.contains(l) || l.isNumber {
                comp.startLiteral()
            } else if config.autoCapitalize, !capBlocked, ch.isLowercase, atSentenceStart() {
                fed = Character(ch.uppercased())
            }
        }
        // Telex có bật phím ngoặc: [ ] { } là phím chữ (ơ, ư), trừ khi từ đang nguyên văn hoặc ở ngữ cảnh code.
        var bracket = false
        if config.isBracketKey(ch), !comp.isLiteral {
            if comp.isEmpty {
                let code = config.codeAware && (sepRun.last.map { Engine.codeMarks.contains($0) || $0.isNumber } ?? false)
                if !code { comp = Composer(config); bracket = true }
            } else {
                bracket = true
            }
        }
        if ch.isASCII, ch.isLetter, var fresh = recomposed(), fresh.feed(fed) { comp = fresh }
        else if !(ch.isASCII && (ch.isLetter || ch.isNumber || bracket) && comp.feed(fed)) { return breakWord(ch) }
        freshBreak = false; watch = nil  // đã gõ chữ khác: từ trước đó không còn là "vừa gõ"
        let new = comp.shown
        let out = diff(from: screen, to: new, typed: ch)
        screen = new
        return out
    }

    private func breakWord(_ ch: Character) -> Output {
        let hard = ch.isNewline || ch == "\t"
        defer {
            sepRun = String((sepRun + String(ch)).suffix(8))
            capBlocked = false
        }
        let pending = retype
        retype = nil
        let corrected = abandoned
        abandoned = nil
        guard !comp.isEmpty else {
            comp = Composer(config)
            if config.tidyPunctuation, ",.;!?".contains(ch), sepRun == " ", history.last?.sep == " " {
                history[history.count - 1].sep = ""
                sepRun = ""
                history[history.count - 1].sep.append(ch)
                return Output(backspaces: 1, text: "", passKey: true)
            }
            // Dãy dấu cách dài (giữ phím cách) thì thôi theo dõi từ trước, để `sep` không lớn mãi.
            if hard || history.isEmpty || history[history.count - 1].sep.count >= Engine.sepLimit {
                history = []
                freshBreak = false
            } else {
                history[history.count - 1].sep.append(ch)
            }
            return .pass
        }
        sepRun = ""
        let typed = comp.rawString
        // Gõ lại đúng từ vừa xoá: nhớ dạng còn lại TRƯỚC khi phân xử, để lần gõ này đã ra dạng đó.
        if let p = pending, p.typed == typed { learn(raw: typed, wantRaw: p.wantRaw) }
        let glued = config.codeAware && config.autoRestore && (ch == "_" || ch == "@")
        // Lỗi gõ quen tay. Người dùng vừa tự sửa: ghi nhận cặp (phím sai -> phím đúng). Không thì xem chuỗi
        // phím này có phải lỗi họ đã sửa đủ nhiều lần; thói quen của chính họ đi trước mọi phép đoán bên dưới.
        var typoFix: (wrong: String, right: String)?
        var keptTypo: String?
        if let model = context, !glued, !comp.codeLiteral, Engine.isPlainKeys(typed) {
            let key = typed.lowercased()
            if let wrong = corrected?.lowercased(), Engine.isPlainKeys(wrong), Engine.oneKeyApart(wrong, key) {
                model.recordTypo(wrong, fixed: key)
                note = "ghi một lần sửa lỗi gõ (\(wrong.count) -> \(key.count) phím)"  // không ghi nội dung
            } else if let fixed = self.typoFix(key, model) {
                typoFix = (key, fixed.rawString.lowercased())
                note = "sửa lỗi gõ quen (\(typed.count) phím)"
                comp = fixed
            } else if corrected == nil, model.keepTypo(key) {
                keptTypo = key
            }
        }
        if typoFix == nil, let fixed = transpositionFix() { comp = fixed }
        // Cả cụm hai từ gõ không dấu ("lam loi"): nếu người dùng hay gõ "lầm lỗi" thì sửa luôn cả từ đứng trước.
        let phrase = glued ? nil : phraseFix()
        let predicted = phrase?.comp ?? (glued ? nil : predict())
        let asTyped = predicted != nil && phrase == nil ? comp.shown : nil
        if let predicted { comp = predicted }
        let composed = comp.shown
        // Từ dính liền "_" hoặc "@" phía sau là tên biến / địa chỉ: giữ phím gốc.
        var final = glued ? comp.rawString : decide()
        // Từ đã đoán không còn khớp từng phím với từng chữ: quay lại sửa thì coi như chữ cố định.
        var resumable = predicted == nil
        if let m = expansion(for: final) { final = m; resumable = false }
        trackLanguage(final: final, composed: composed)
        if predicted != nil || typed != comp.rawString, final == composed { fixedWord = final }
        // Ghi nhận từ người dùng tự gõ mà từ điển coi là tiếng Việt (không tính từ do VNKey đoán, sửa hay bung ra),
        // kể cả từ không dấu ("nay" trong "hôm nay", "to do"): số lần gõ dạng không dấu là bằng chứng duy nhất
        // cho biết người dùng có thật sự viết cặp từ ấy như vậy, để không bị "sửa" nhầm.
        var recorded: (word: String, prev: String?)?
        if let model = context, predicted == nil, resumable, typed == comp.rawString, final == composed,
            lexicon?.isVietnamese(final.lowercased()) == true
        {
            recorded = (final.lowercased(), previousWord())
            model.record(recorded!.word, after: recorded!.prev)
        }

        var out = Output.pass
        if let phrase, let last = history.indices.last {
            // Xoá cả từ đứng trước, dấu cách và từ đang gõ rồi gõ lại cụm có dấu.
            let e = history[last]
            out = Output(backspaces: e.final.count + e.sep.count + screen.count, text: phrase.prev + e.sep + final, passKey: true)
            fixedWord = phrase.prev + e.sep + final  // app nháy cả hai từ vừa được thay
            if let r = e.recorded { context?.unrecord(r.word, after: r.prev) }  // lần gõ không dấu đó là gõ thiếu dấu
            history[last].final = phrase.prev
            history[last].composed = phrase.prev
            history[last].resumable = false
            history[last].recorded = nil
        } else if final != screen {
            let p = commonPrefix(screen, final)
            out = Output(backspaces: screen.count - p, text: String(final.dropFirst(p)), passKey: true)
        }
        history.append(
            Entry(
                comp: comp, raw: comp.rawString, composed: composed, final: final, sep: String(ch), resumable: resumable,
                typed: typed, recorded: recorded, typoFix: typoFix, keptTypo: keptTypo, asTyped: asTyped))
        if history.count > historyLimit { history.removeFirst() }
        if hard { history = [] }
        freshBreak = !hard && (resumable || predicted != nil) && (composed != comp.rawString || typed != comp.rawString)
        comp = Composer(config); screen = ""
        return out
    }

    public func backspace() -> Output {
        capBlocked = true
        if comp.isEmpty {
            retype = nil  // xoá lan sang chữ đứng trước: không còn là "xoá đúng một từ rồi gõ lại"
            abandoned = nil  // từ sắp được mở lại bên dưới (nếu có) mới là từ đang được sửa
            if !sepRun.isEmpty { sepRun.removeLast() }
            guard var e = history.popLast() else { return .pass }
            if !e.sep.isEmpty {
                e.sep.removeLast()
                if e.sep.isEmpty { resume(e) } else { history.append(e) }
                return .pass
            }
            resume(e)
        }
        guard !comp.isEmpty else { return .pass }
        if abandoned == nil { abandoned = comp.rawString }  // chỉ ghi nhớ; không phát phím nào
        // Xoá lùi LUÔN đi thẳng: màn hình mất đúng ký tự cuối, engine chỉ cập nhật trạng thái cho khớp.
        // Không bao giờ sửa chữ khác ở đây — phát phím xoá + chữ trong lúc người dùng đang giữ phím xoá
        // đã làm màn hình và engine lệch nhau. Nếu cách hiển thị chuẩn khác với màn hình (dấu thanh nằm
        // khác chỗ: "hoà" so với "hòa"), phím kế tiếp hoặc lúc kết thúc từ sẽ sửa.
        comp.backspace(dropTone: screen.last.map(Engine.carriesTone) ?? false)
        if !screen.isEmpty { screen.removeLast() }
        if comp.isEmpty {
            screen = ""
            retype = watch  // đã xoá hết từ vừa gõ: chờ xem có gõ lại y nguyên không
            watch = nil
        }
        return .pass
    }

    /// Từ đang nguyên văn vì một phím gõ nhầm ("thii", "vieejk") và người dùng đã xoá bớt: khi họ gõ chữ
    /// kế tiếp, phần còn lại được hiểu như vừa gõ mới, để gõ tiếp tiếng Việt mà không phải xoá về tận
    /// khoảng trắng. Chỉ làm lúc có phím mới (không làm lúc xoá): xoá lùi không được đụng tới màn hình, và
    /// một từ đã hiểu lại mà màn hình còn là phím thô ("vieej") sẽ lệch nếu bị xoá tiếp.
    private func recomposed() -> Composer? {
        guard comp.retry, comp.isLiteral, !comp.codeLiteral, !comp.noRecompose,
            comp.raw.allSatisfy({ $0.isASCII && $0.isLetter }),
            let fresh = Composer.replay(comp.raw, config), !fresh.isLiteral
        else { return nil }
        return fresh
    }

    private static let toneMarks: Set<Unicode.Scalar> = ["\u{301}", "\u{300}", "\u{309}", "\u{303}", "\u{323}"]

    /// Ký tự đang mang dấu thanh (sắc, huyền, hỏi, ngã, nặng).
    static func carriesTone(_ ch: Character) -> Bool {
        String(ch).decomposedStringWithCanonicalMapping.unicodeScalars.contains(where: toneMarks.contains)
    }

    /// Quay lại sửa từ trước đó, giữ nguyên thứ tự phím đã gõ.
    private func resume(_ e: Entry) {
        // Người dùng quay lại sửa từ này: lần gõ vừa rồi không tính là thói quen. Gõ xong nó sẽ được ghi lại.
        if let r = e.recorded { context?.unrecord(r.word, after: r.prev) }
        if let k = e.keptTypo { context?.unkeepTypo(k) }
        abandoned = e.typed
        if freshBreak, config.learnFromRetype {
            // Đã sửa đảo phím, hoặc đang hiện tiếng Việt -> gõ lại nghĩa là muốn phím gốc; đang hiện phím gốc
            // (đã tự trả lại) -> muốn tiếng Việt.
            watch = Retype(typed: e.typed, wantRaw: e.typed != e.raw || e.final != e.raw)
        }
        freshBreak = false
        comp = e.comp
        if !e.resumable || e.final != comp.shown { comp.forceLiteral(e.final) }
        screen = e.final
        sepRun = ""
    }

    /// Đầu câu: ngay sau xuống dòng, hoặc sau đúng một dấu . ! ? rồi tới khoảng trắng ("..." không tính).
    private func atSentenceStart() -> Bool {
        var t = Substring(sepRun)
        while t.last == " " { t.removeLast() }
        guard let last = t.last else { return false }
        if last.isNewline { return true }
        guard t.count < sepRun.count else { return false }
        if last == "!" || last == "?" { return true }
        // Sau từ chỉ có một chữ thường là viết tắt (v.v., Q. 1), không phải hết câu.
        return t == "." && (history.last?.final.count ?? 0) >= 2
    }

    /// Chữ sẽ hiện khi gõ chuỗi phím này, để giao diện hiện một lỗi gõ đã học dưới dạng chữ ("gox" -> "gõ").
    public static func shown(forKeys keys: String, config: Config) -> String {
        Composer.replay(Array(keys), config)?.shown ?? keys
    }

    /// Chuỗi phím chỉ gồm chữ và số ASCII, ít nhất hai phím: thứ duy nhất được học làm lỗi gõ.
    static func isPlainKeys(_ s: String) -> Bool {
        s.count >= 2 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// Hai chuỗi phím khác nhau đúng một lỗi gõ: thay một phím, thừa hoặc thiếu một phím, đảo hai phím liền nhau.
    static func oneKeyApart(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        if x == y || abs(x.count - y.count) > 1 { return false }
        var i = 0
        while i < min(x.count, y.count), x[i] == y[i] { i += 1 }
        if x.count == y.count {
            if x[(i + 1)...] == y[(i + 1)...] { return true }  // thay một phím
            return i + 1 < x.count && x[i] == y[i + 1] && x[i + 1] == y[i] && x[(i + 2)...] == y[(i + 2)...]
        }
        let (long, short) = x.count > y.count ? (x, y) : (y, x)
        return long[(i + 1)...] == short[i...]
    }

    /// Chuỗi phím đang gõ là một lỗi gõ người dùng đã sửa đủ nhiều lần: trả về từ gõ đúng, giữ kiểu hoa/thường.
    /// Sửa cả khi từ điển coi chữ gõ ra là từ đúng: từ điển của macOS dễ dãi ("dúng" cũng được coi là đúng), và
    /// bằng chứng ở đây là chính các lần người dùng sửa. Thứ ngăn sửa nhầm là số lần họ gõ chuỗi đó rồi để nguyên
    /// (`ContextModel.keepTypo`): từ họ dùng thật ("ban") sẽ được giữ nhiều hơn số lần sửa.
    private func typoFix(_ key: String, _ model: ContextModel) -> Composer? {
        guard config.fixTypos, config.autoRestore, !comp.cancelled, !comp.keepComposed, !preferRaw.contains(key),
            let right = model.typoFix(for: key)
        else { return nil }
        let raw = comp.raw
        var keys = Array(right)
        if raw.count > 1, raw.allSatisfy({ !$0.isLetter || $0.isUppercase }) {
            keys = Array(right.uppercased())
        } else if raw.first?.isUppercase == true, let first = keys.first {
            keys[0] = Character(first.uppercased())
        }
        return Composer.replay(keys, config)
    }

    /// Thử đổi chỗ hai phím liền nhau; nhận nếu ra đúng MỘT từ tiếng Việt có dấu.
    private func transpositionFix() -> Composer? {
        guard config.fixTransposition, config.autoRestore, let lex = lexicon else { return nil }
        let raw = comp.raw
        // Quá 10 phím thì không thử: mỗi cách đảo là một lần gõ lại cả từ và một lần hỏi từ điển.
        guard (3...10).contains(raw.count), !comp.cancelled, !comp.keepComposed, !comp.codeLiteral else { return nil }
        if !comp.isLiteral, comp.hasVowel,
            Syl.isValid(comp.plainChars, tone: comp.tone, teen: config.teenInitials)
        { return nil }
        let key = String(raw).lowercased()
        guard !preferRaw.contains(key), !isEnglish(key) else { return nil }
        var found: Composer?
        for i in 0..<(raw.count - 1) where raw[i] != raw[i + 1] {
            var keys = raw
            keys.swapAt(i, i + 1)
            guard let c = Composer.replay(keys, config), !c.isLiteral, c.hasVowel,
                Syl.isValid(c.plainChars, tone: c.tone, teen: false)
            else { continue }
            let s = c.shown
            guard s.contains(where: { !$0.isASCII }), lex.isVietnamese(s.lowercased()) else { continue }
            if let f = found, f.shown != s { return nil }
            found = c
        }
        return found
    }

    /// Từ đứng ngay trước từ đang gõ trong cùng một cụm (cách nhau đúng một dấu cách), chữ thường.
    private func previousWord() -> String? {
        guard let e = history.last, e.sep == " " else { return nil }
        return e.final.lowercased()
    }

    /// Từ đang gõ và từ ngay trước nó đều không dấu, nhưng người dùng hay gõ đúng cụm đó có dấu: trả về từ đang
    /// gõ đã thêm dấu và chữ thay cho từ đứng trước. Bằng chứng duy nhất là thói quen của chính người dùng
    /// (`ContextModel.phrase`), nên không cần quanh đó có từ nào có dấu; chỉ không làm giữa một mạch tiếng Anh.
    private func phraseFix() -> (comp: Composer, prev: String)? {
        guard config.predict, config.autoRestore, let model = context, lexicon != nil,
            englishStreak == 0, !comp.isLiteral, comp.hasVowel, !comp.cancelled, !comp.keepComposed, !comp.codeLiteral,
            comp.markCount == 0, comp.tone == .none, expansion(for: comp.shown) == nil
        else { return nil }
        let key = comp.rawString.lowercased()
        guard !preferRaw.contains(key), !preferVN.contains(key), let e = history.last, e.sep == " ", e.resumable,
            e.typed == e.raw, e.final == e.raw, !e.final.isEmpty, e.final.allSatisfy({ $0.isASCII && $0.isLetter }),
            !preferRaw.contains(e.raw.lowercased())
        else { return nil }
        let plainPrev = e.final.lowercased(), plainWord = comp.shown.lowercased()
        guard let hit = model.phrase(plainPrev: plainPrev, plainWord: plainWord), hit.prev != plainPrev else { return nil }
        // Từ đang gõ: lấy đúng ứng viên có dấu (hoặc giữ nguyên nếu cụm đã học chỉ khác ở từ đứng trước).
        var fixed = comp
        if hit.word != plainWord {
            guard let c = Predictor.candidates(for: comp, teen: false).first(where: { $0.shown.lowercased() == hit.word }) else {
                return nil
            }
            fixed = c
        }
        fixed.keepComposed = true
        // Từ đứng trước: giữ kiểu viết hoa người dùng đã gõ.
        var prev = hit.prev
        if e.final.count > 1, e.final == e.final.uppercased() {
            prev = prev.uppercased()
        } else if let f = e.final.first, f.isUppercase {
            prev = prev.prefix(1).uppercased() + prev.dropFirst()
        }
        note = "đoán cụm \(e.final) \(comp.shown) -> \(prev) \(fixed.shown) (\(hit.count) lần đã gõ)"
        return (fixed, prev)
    }

    /// Một trong ba từ vừa gõ là tiếng Việt có dấu, và không đang ở giữa một mạch tiếng Anh.
    private var inVietnameseContext: Bool {
        englishStreak == 0 && history.suffix(3).contains(where: { $0.final.contains(where: { !$0.isASCII }) })
    }

    /// Đoán từ định gõ khi từ đang hiện không phải tiếng Việt đúng vì thiếu dấu. Xem `Predictor` về ứng viên;
    /// việc chọn đi qua bốn tầng, tầng nào quyết được thì dừng: cặp từ người dùng đã gõ -> gợi ý theo câu của từ
    /// điển hệ thống -> độ thông dụng -> chỉ có một ứng viên. Không quyết được thì trả nil (giữ hành vi cũ).
    private func predict() -> Composer? {
        guard config.predict, config.autoRestore, let lex = lexicon else { return nil }
        guard !comp.isLiteral, comp.hasVowel, comp.raw.count >= 2, !comp.cancelled, !comp.keepComposed,
            !comp.codeLiteral
        else { return nil }
        let key = comp.rawString.lowercased(), shown = comp.shown.lowercased()
        guard !preferRaw.contains(key), !preferVN.contains(key), !Engine.builtinEnglish.contains(key),
            !(comp.lateBar && Engine.lateBarEnglish.contains(key)), expansion(for: comp.shown) == nil
        else { return nil }
        let english = isEnglish(key)

        let marked = comp.markCount > 0 || comp.tone != .none
        let prev = previousWord()
        // Thứ tự người dùng chốt (2026-11-24):
        //  1. "Từ điển" của VNKey là bảng tần suất `CommonWords`. Chữ CÓ DẤU không nằm trong bảng là chữ không
        //     thông dụng — nhiều khả năng gõ dở — và được thay bằng ứng viên thông dụng nhất. Từ điển của macOS
        //     không còn được hỏi cho việc này (nó nhận gần như mọi âm tiết đúng cấu trúc: "tiêng", "dúng", "ròi").
        //  2. Người dùng sửa lại một lần thay như vậy đủ nhiều thì từ đã học đi trước: `typoFix` (chạy trước hàm
        //     này), `preferVN` / `preferRaw` (phím Đổi từ vừa gõ), và số lần họ tự gõ chữ đó.
        // Chữ CHƯA có dấu nào thì khác: chỉ thói quen của chính người dùng (cặp từ đã gõ) mới được thêm dấu.
        let shownCount = marked ? CommonWords.count(shown) : 0
        let real = marked ? shownCount >= CommonWords.tableFloor : lex.isVietnamese(shown)
        if english, !(marked && !real && inVietnameseContext) { return nil }
        if real, marked || context == nil || prev == nil { return nil }
        if !marked { guard context != nil, inVietnameseContext else { return nil } }

        var seen = Set<String>()
        let options = Predictor.candidates(for: comp, teen: false).compactMap { c -> (word: String, comp: Composer)? in
            let w = c.shown.lowercased()
            guard seen.insert(w).inserted else { return nil }
            return (marked ? CommonWords.count(w) >= CommonWords.tableFloor : lex.isVietnamese(w)) ? (w, c) : nil
        }
        guard !options.isEmpty else { return nil }
        // Chữ không có trong bảng mà chính người dùng hay gõ, không kém ứng viên nào: đó là từ của họ.
        if marked, let model = context {
            let mine = model.count(shown)
            if mine >= 2, mine >= (options.map { model.count($0.word) }.max() ?? 0) { return nil }
        }

        /// Ứng viên đứng đầu nếu nó hơn hẳn ứng viên thứ hai (ít nhất gấp đôi).
        func clearWinner(_ score: (String) -> Int, atLeast: Int) -> Int? {
            let scores = options.map { score($0.word) }
            guard let best = scores.max(), best >= atLeast else { return nil }
            let i = scores.firstIndex(of: best)!
            let second = scores.enumerated().filter { $0.offset != i }.map(\.element).max() ?? 0
            return best >= 2 * second ? i : nil
        }
        var pick: Int?, tier = 0
        if real {
            // Người dùng đã gõ cặp (từ trước -> ứng viên) ít nhất ba lần, và nhiều hơn số lần họ gõ cặp ấy ở
            // dạng không dấu. (Đòi "chưa từng gõ không dấu" thì vài lần gõ thử sẽ chặn việc học mãi mãi.)
            guard let model = context, let prev,
                let i = clearWinner({ model.pairCount($0, after: prev) }, atLeast: 3),
                model.pairCount(options[i].word, after: prev) > model.pairCount(shown, after: prev)
            else { return nil }
            pick = i; tier = 1
        } else if let model = context, let prev, let i = clearWinner({ model.pairCount($0, after: prev) }, atLeast: 2) {
            pick = i; tier = 1  // chính người dùng đã gõ cặp từ này
        } else if !marked {
            return nil
        } else {
            // Điểm = tần suất (cộng số lần chính người dùng gõ), chia 10 cho mỗi phím phải thêm nhiều hơn ứng viên
            // gần nhất: gõ thiếu một phím dễ xảy ra hơn thiếu hai ("dúng": đúng thiếu một, đứng thiếu hai).
            func missing(_ c: Composer) -> Int { (c.markCount - comp.markCount) + (c.tone != comp.tone ? 1 : 0) }
            let least = options.map { missing($0.comp) }.min() ?? 0
            let scores = options.map { o -> Int in
                var score = CommonWords.count(o.word) + 1000 * (context?.count(o.word) ?? 0)
                for _ in 0..<min(missing(o.comp) - least, 6) { score /= 10 }
                return score
            }
            let best = scores.max() ?? 0
            let top = scores.firstIndex(of: best) ?? 0
            // Các ứng viên cùng thiếu ít phím nhất và không kém từ đứng đầu quá 50 lần (việt / viết ≈ 1 : 10) là
            // "cùng hạng"; được / dược ≈ 350 : 1 thì không.
            let close = scores.indices.filter { missing(options[$0].comp) == least && scores[$0] * CommonWords.sameLeague > best }
            if close.count > 1, close.contains(top),
                // Vài ứng viên cùng hạng: để gợi ý theo câu của macOS xét từ đứng trước ("tiếng viêt" -> việt, "bài
                // viêt" -> viết). Chỉ đưa MỘT từ đứng trước: đo thực tế, thêm từ xa hơn làm gợi ý kém đi.
                let w = lex.rank(close.map { options[$0].word }, after: prev.map { [$0] } ?? [], typed: comp.shown),
                let i = close.first(where: { options[$0].word == w })
            {
                pick = i; tier = 2
            } else {
                pick = top; tier = 3  // không ai phân xử: lấy từ thông dụng nhất
            }
            // Chuỗi phím trùng một từ tiếng Anh ("dungs", "test"): chỉ thay khi ứng viên rất thông dụng.
            if english, let i = pick, CommonWords.count(options[i].word) < CommonWords.veryCommon { return nil }
        }
        guard let pick else { return nil }
        note = "đoán \(comp.shown) -> \(options[pick].comp.shown) (tầng \(tier), \(options.count) ứng viên)"
        return options[pick].comp
    }

    private func trackLanguage(final: String, composed: String) {
        let raw = comp.rawString
        if final.contains(where: { !$0.isASCII }) {
            englishStreak = 0
        } else if final == raw, !comp.codeLiteral, raw.count >= 2,
            composed != raw || comp.isLiteral, isEnglish(raw.lowercased())
        {
            englishStreak += 1
        }
    }

    /// Đổi qua lại giữa phím gốc và tiếng Việt cho từ đang gõ / từ vừa gõ xong, và ghi nhớ lựa chọn.
    public func toggleLast() -> Output {
        forgetRecent()
        if !comp.isEmpty {
            let raw = comp.rawString
            guard screen != raw else { return .pass }
            let p = commonPrefix(screen, raw)
            let out = Output(backspaces: screen.count - p, text: String(raw.dropFirst(p)), passKey: false)
            learn(raw: raw, wantRaw: true)
            comp.forceLiteral(raw); screen = raw
            return out
        }
        guard var e = history.popLast() else { return .pass }
        defer { history.append(e) }
        if let t = e.typoFix, e.final != e.typed {
            // Từ này vừa được sửa theo lỗi gõ đã học: trả lại đúng những phím đã gõ và quên cặp đó.
            let out = Output(backspaces: e.final.count + e.sep.count, text: e.typed + e.sep, passKey: false)
            context?.forgetTypo(t.wrong, fixed: t.right)
            e.comp.forceLiteral(e.typed)
            e.raw = e.typed; e.composed = e.typed; e.final = e.typed
            e.resumable = false; e.typoFix = nil
            return out
        }
        if let typedForm = e.asTyped, typedForm != e.raw, typedForm != e.composed {
            // Từ do VNKey đoán có ba dạng, đổi vòng: chữ đã đoán -> phím gốc -> chữ đúng như đã gõ -> chữ đã đoán.
            // Dạng thứ ba là lối ra cho từ thật mà bảng tần suất không có: chọn nó thì lần sau VNKey không thay nữa.
            let next = e.final == e.composed ? e.raw : e.final == e.raw ? typedForm : e.composed
            let out = Output(backspaces: e.final.count + e.sep.count, text: next + e.sep, passKey: false)
            let key = e.raw.lowercased()
            preferRaw.remove(key); preferVN.remove(key)
            if next == e.raw { preferRaw.insert(key) } else if next == typedForm { preferVN.insert(key) }
            onLearn?()
            e.final = next
            return out
        }
        guard e.composed != e.raw else { return .pass }
        let alt = e.final == e.raw ? e.composed : e.raw
        let out = Output(backspaces: e.final.count + e.sep.count, text: alt + e.sep, passKey: false)
        learn(raw: e.raw, wantRaw: alt == e.raw)
        e.final = alt
        return out
    }

    private func learn(raw: String, wantRaw: Bool) {
        let key = raw.lowercased()
        if wantRaw { preferRaw.insert(key); preferVN.remove(key) } else { preferVN.insert(key); preferRaw.remove(key) }
        onLearn?()
    }

    // MARK: - Quyết định khi kết thúc từ

    /// Từ tiếng Anh rất phổ biến mà gõ Telex ra âm tiết hợp lệ nhưng hiếm gặp.
    static let builtinEnglish: Set<String> = [
        "is", "as", "of", "if", "or", "us", "was", "for", "her", "more", "here", "test", "just", "first", "most",
        "post", "fix", "box", "now", "how", "see",
    ]

    /// Từ tiếng Anh thông dụng có hai chữ d mà gõ ra âm tiết Việt hợp lệ (dùng khi không có từ điển).
    static let lateBarEnglish: Set<String> = ["did", "dad", "deed", "dud", "dido", "dude"]

    static let teenExpansions: [String: String] = [
        "ko": "không", "hok": "không", "hem": "không", "dc": "được", "đc": "được", "ntn": "như thế nào",
        "bik": "biết", "bít": "biết", "trc": "trước", "vs": "với", "mn": "mọi người", "cx": "cũng",
        "nhìu": "nhiều", "iu": "yêu", "lm": "làm", "ns": "nói", "nt": "nhắn tin", "j": "gì", "z": "vậy",
        "r": "rồi", "ms": "mới",
    ]

    private func decide() -> String {
        let shown = comp.shown, raw = comp.rawString
        guard config.autoRestore, shown != raw else { return shown }
        let key = raw.lowercased()
        if preferRaw.contains(key) { return raw }
        if preferVN.contains(key) || comp.keepComposed { return shown }
        // Chữ đ do chữ d gõ muộn tạo ra: nếu chuỗi phím là một từ tiếng Anh ("did", "dad") thì giữ tiếng Anh.
        // Người gõ tiếng Việt muốn "đi", "đa" hầu như luôn gõ "ddi", "dda".
        if comp.lateBar, Engine.lateBarEnglish.contains(key) || isEnglish(key) { return raw }

        // Gõ lặp để huỷ dấu ("tass" -> "tas") được tôn trọng, trừ khi chuỗi phím gốc là từ tiếng Anh ("pass", "off").
        func afterCancel() -> String {
            return isEnglish(key) ? raw : shown
        }
        if comp.isLiteral { return comp.cancelled ? afterCancel() : shown }
        if !comp.hasVowel { return shown }  // viết tắt toàn phụ âm: đc, đt...
        if !Syl.isValid(comp.plainChars, tone: comp.tone, teen: config.teenInitials) {
            if comp.cancelled { return afterCancel() }
            // Sai duy nhất ở chỗ thiếu dấu thanh trước âm cuối c/ch/p/t ("đươc", "dât"): có thể là tiếng Việt
            // gõ quên dấu, cũng có thể là tiếng Anh ("data"). Có từ điển thì hỏi; không thì từ mang từ hai
            // dấu mũ/móc/đ trở lên coi là tiếng Việt và giữ nguyên để người dùng bỏ dấu tiếp.
            if Syl.isValid(comp.plainChars, tone: comp.tone, teen: config.teenInitials, ignoreToneRule: true) {
                if lexicon != nil { return isEnglish(key) ? raw : shown }
                return comp.markCount >= 2 ? shown : raw
            }
            return raw
        }
        if comp.cancelled { return shown }
        if Engine.builtinEnglish.contains(key) { return raw }
        if let lex = lexicon, isEnglish(key) {
            if !lex.isVietnamese(shown.lowercased()) { return raw }
            if config.contextAware, englishStreak >= 2 { return raw }
        }
        return shown
    }

    /// Chuỗi phím gốc có phải từ tiếng Anh không. Chuỗi có chữ số (phím dấu của VNI) thì không bao giờ:
    /// trình kiểm tra chính tả bỏ qua từ chứa số nên sẽ trả lời "đúng" một cách vô nghĩa.
    private func isEnglish(_ key: String) -> Bool {
        guard let lex = lexicon, key.allSatisfy(\.isLetter) else { return false }
        return lex.isEnglish(key)
    }

    private func expansion(for word: String) -> String? {
        let key = word.lowercased()
        guard let full = config.macros[key] ?? (config.expandTeen ? Engine.teenExpansions[key] : nil) else {
            return nil
        }
        if let f = word.first, f.isUppercase { return full.prefix(1).uppercased() + full.dropFirst() }
        return full
    }

    // MARK: - Tiện ích

    private func commonPrefix(_ a: String, _ b: String) -> Int {
        var n = 0
        for (x, y) in zip(a, b) { if x != y { break }; n += 1 }
        return n
    }

    static let sepLimit = 32

    private func diff(from old: String, to new: String, typed: Character) -> Output {
        if new.last == typed, new.dropLast() == old { return .pass }
        let p = commonPrefix(old, new)
        return Output(backspaces: old.count - p, text: String(new.dropFirst(p)), passKey: false)
    }
}
