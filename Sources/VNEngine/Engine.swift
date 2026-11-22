import Foundation

public struct Config: Sendable, Equatable {
    public var method: Method = .telex
    /// true: hoà, thuỷ — false: hòa, thủy.
    public var modernTone = false
    /// Telex: phím "w" đứng một mình thành "ư".
    public var standaloneW = true
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
    public init() {}
}

/// Tra từ điển để phân xử các từ hợp lệ ở cả hai ngôn ngữ. App cung cấp qua NSSpellChecker.
public protocol Lexicon: AnyObject {
    func isEnglish(_ word: String) -> Bool
    func isVietnamese(_ word: String) -> Bool
}

/// Việc cần làm trên màn hình sau một phím.
public struct Output: Equatable, Sendable {
    /// Số ký tự cần xoá lùi trước con trỏ.
    public var backspaces = 0
    /// Văn bản cần chèn sau khi xoá.
    public var text = ""
    /// Phím gốc có được đi tiếp tới ứng dụng (sau `backspaces`/`text`) hay không.
    public var passKey = true

    public static let pass = Output()
    public var isPass: Bool { backspaces == 0 && text.isEmpty && passKey }
}

public final class Engine {
    public var config: Config { didSet { reset() } }
    public weak var lexicon: Lexicon?

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

    static let codeMarks: Set<Character> = ["@", "#", "/", "\\", ".", "_", ":", "$", "~", "=", "<", "&"]

    public init(config: Config = Config()) {
        self.config = config
        comp = Composer(config)
    }

    /// Quên mọi trạng thái: gọi khi con trỏ có thể đã di chuyển (chuột, mũi tên, đổi app, phím tắt).
    public func reset() {
        comp = Composer(config); screen = ""; history = []
        sepRun = ""; capBlocked = false; englishStreak = 0
    }

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
        var fed = ch
        if comp.isEmpty, ch.isASCII, ch.isLetter {  // bắt đầu một từ mới
            comp = Composer(config)
            if config.codeAware, let l = sepRun.last, Engine.codeMarks.contains(l) || l.isNumber {
                comp.startLiteral()
            } else if config.autoCapitalize, !capBlocked, ch.isLowercase, atSentenceStart() {
                fed = Character(ch.uppercased())
            }
        }
        if ch.isASCII, ch.isLetter || ch.isNumber, comp.feed(fed) {
            let new = comp.shown
            let out = diff(from: screen, to: new, typed: ch)
            screen = new
            return out
        }
        return breakWord(ch)
    }

    private func breakWord(_ ch: Character) -> Output {
        let hard = ch.isNewline || ch == "\t"
        defer {
            sepRun = String((sepRun + String(ch)).suffix(8))
            capBlocked = false
        }
        guard !comp.isEmpty else {
            comp = Composer(config)
            if config.tidyPunctuation, ",.;!?".contains(ch), sepRun == " ", history.last?.sep == " " {
                history[history.count - 1].sep = ""
                sepRun = ""
                history[history.count - 1].sep.append(ch)
                return Output(backspaces: 1, text: "", passKey: true)
            }
            if hard || history.isEmpty { history = [] } else { history[history.count - 1].sep.append(ch) }
            return .pass
        }
        sepRun = ""
        if let fixed = transpositionFix() { comp = fixed }
        let composed = comp.shown
        // Từ dính liền "_" hoặc "@" phía sau là tên biến / địa chỉ: giữ phím gốc.
        let gluedCode = config.codeAware && config.autoRestore && (ch == "_" || ch == "@")
        var final = gluedCode ? comp.rawString : decide()
        var resumable = true
        if let m = expansion(for: final) { final = m; resumable = false }
        trackLanguage(final: final, composed: composed)

        var out = Output.pass
        if final != screen {
            let p = commonPrefix(screen, final)
            out = Output(backspaces: screen.count - p, text: String(final.dropFirst(p)), passKey: true)
        }
        history.append(
            Entry(comp: comp, raw: comp.rawString, composed: composed, final: final, sep: String(ch), resumable: resumable))
        if history.count > historyLimit { history.removeFirst() }
        if hard { history = [] }
        comp = Composer(config); screen = ""
        return out
    }

    public func backspace() -> Output {
        capBlocked = true
        if comp.isEmpty {
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
        comp.backspace()
        let new = comp.shown
        var out = Output.pass
        if new != String(screen.dropLast()) {  // vd dấu thanh đổi vị trí: hoàn -> hòa
            let p = commonPrefix(screen, new)
            out = Output(backspaces: screen.count - p, text: String(new.dropFirst(p)), passKey: false)
        }
        screen = new
        return out
    }

    /// Quay lại sửa từ trước đó, giữ nguyên thứ tự phím đã gõ.
    private func resume(_ e: Entry) {
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

    /// Thử đổi chỗ hai phím liền nhau; nhận nếu ra đúng MỘT từ tiếng Việt có dấu.
    private func transpositionFix() -> Composer? {
        guard config.fixTransposition, config.autoRestore, let lex = lexicon else { return nil }
        let raw = comp.raw
        guard (3...12).contains(raw.count), !comp.cancelled, !comp.keepComposed, !comp.codeLiteral else { return nil }
        if !comp.isLiteral, comp.hasVowel,
            Syl.isValid(comp.plainChars, tone: comp.tone, teen: config.teenInitials)
        { return nil }
        let key = String(raw).lowercased()
        guard !preferRaw.contains(key), !lex.isEnglish(key) else { return nil }
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

    private func trackLanguage(final: String, composed: String) {
        let raw = comp.rawString
        if final.contains(where: { !$0.isASCII }) {
            englishStreak = 0
        } else if final == raw, !comp.codeLiteral, raw.count >= 2,
            composed != raw || comp.isLiteral, lexicon?.isEnglish(raw.lowercased()) == true
        {
            englishStreak += 1
        }
    }

    /// Đổi qua lại giữa phím gốc và tiếng Việt cho từ đang gõ / từ vừa gõ xong, và ghi nhớ lựa chọn.
    public func toggleLast() -> Output {
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
        "post", "fix", "box",
    ]

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

        // Gõ lặp để huỷ dấu ("tass" -> "tas") được tôn trọng, trừ khi chuỗi phím gốc là từ tiếng Anh ("pass", "off").
        func afterCancel() -> String {
            guard let lex = lexicon else { return shown }
            return lex.isEnglish(key) ? raw : shown
        }
        if comp.isLiteral { return comp.cancelled ? afterCancel() : shown }
        if !comp.hasVowel { return shown }  // viết tắt toàn phụ âm: đc, đt...
        if !Syl.isValid(comp.plainChars, tone: comp.tone, teen: config.teenInitials) {
            return comp.cancelled ? afterCancel() : raw
        }
        if comp.cancelled { return shown }
        if Engine.builtinEnglish.contains(key) { return raw }
        if let lex = lexicon, lex.isEnglish(key) {
            if !lex.isVietnamese(shown.lowercased()) { return raw }
            if config.contextAware, englishStreak >= 2 { return raw }
        }
        return shown
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

    private func diff(from old: String, to new: String, typed: Character) -> Output {
        if new == old + String(typed) { return .pass }
        let p = commonPrefix(old, new)
        return Output(backspaces: old.count - p, text: String(new.dropFirst(p)), passKey: false)
    }
}
