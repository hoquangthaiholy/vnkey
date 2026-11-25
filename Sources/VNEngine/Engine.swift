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
    /// THỬ NGHIỆM (2026-11-25, mặc định tắt): xoá một phím gõ thừa làm từ đang nguyên văn trở lại thành tiếng Việt thì
    /// đổi chữ NGAY lúc xoá ("ddaayy" xoá một chữ -> "đây"), thay vì đợi tới lúc ngắt từ. Trái với luật "phím xoá
    /// không bao giờ sửa chữ khác"; xem bộ test `RetryOnBackspace` về những chỗ va chạm.
    public var retryOnBackspace = false
    /// Gõ tắt thông minh: tên -> nội dung. Bung khi gõ `\tên` (dấu `\` ở đầu từ) rồi ngắt từ. Rỗng = tắt.
    public var smartMacros: [String: String] = [:]
    /// Không biến đổi từ đứng ngay sau @ # / \ . _ : $ ~ = < & hoặc chữ số (email, đường dẫn, hashtag, tên biến).
    public var codeAware = true
    /// Đang gõ một mạch tiếng Anh thì từ mơ hồ cũng coi là tiếng Anh. Cần từ điển.
    public var contextAware = true
    /// Tự viết hoa chữ đầu câu (sau . ! ? hoặc xuống dòng).
    public var autoCapitalize = false
    /// Xoá khoảng trắng thừa trước , . ; ! ?
    public var tidyPunctuation = false
    /// Xoá ngay từ vừa gõ rồi gõ lại đúng chuỗi phím đó: đổi sang dạng còn lại (phím gốc ↔ tiếng Việt) và nhớ.
    public var learnFromRetype = true
    public init() {}
}

/// Tra từ điển để phân xử các từ hợp lệ ở cả hai ngôn ngữ. App cung cấp qua NSSpellChecker.
public protocol Lexicon: AnyObject {
    func isEnglish(_ word: String) -> Bool
    func isVietnamese(_ word: String) -> Bool
    /// Trong các ứng viên (chữ thường), từ nào hợp nhất với chữ đang hiện `typed` đứng sau các từ `context`;
    /// nil nếu không có ý kiến. Có thể chậm (vài ms): engine chỉ hỏi ở cuối một từ gõ chưa thành tiếng Việt.
    func rank(_ candidates: [String], after context: [String], typed: String) -> String?
    /// Các từ tiếng Anh mà từ điển đoán người dùng định gõ khi `word` sai chính tả, hay nhất đứng đầu. Có thể chậm.
    func englishGuesses(_ word: String) -> [String]
}

extension Lexicon {
    public func englishGuesses(_ word: String) -> [String] { [] }
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

    /// Từ người dùng muốn giữ nguyên phím gốc / giữ tiếng Việt (khoá = phím gốc viết thường).
    public var preferRaw: Set<String> = []
    public var preferVN: Set<String> = []
    public var onLearn: (() -> Void)?
    /// Đồng hồ cho các biến ngày giờ trong gõ tắt (`SmartMacro`); test thay bằng thời điểm cố định.
    public var now: () -> Date = { Date() }
    /// Giá trị của các biến gõ tắt mà engine không tự biết ("hoten", "clipboard"): app cung cấp.
    public var variable: ((String) -> String?)?
    /// Nội dung vừa được chèn do một gõ tắt bung ra ở phím vừa xử lý; nil nếu không. App dùng để làm sáng đoạn chữ đó.
    public private(set) var replaced: String?

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
        /// Chuỗi phím này là một lỗi gõ đã biết mà lần này người dùng để nguyên (đã đếm); quay lại sửa thì rút lại.
        var keptTypo: String? = nil
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
    /// Từ đang sửa là từ đã gõ xong, được mở lại bằng phím xoá. Thử nghiệm `retryOnBackspace` không áp dụng cho nó:
    /// xoá dần một từ tiếng Anh ("test" -> "tes") sẽ biến phần còn lại thành tiếng Việt ("té").
    private var reopened = false
    /// Vừa gõ dấu `\` ở đầu từ: từ kế tiếp là tên của một gõ tắt thông minh.
    private var prefixTyped = false
    /// Từ đang gõ đứng ngay sau dấu `\` ở đầu từ (`\homnay`).
    private var afterPrefix = false

    static let codeMarks: Set<Character> = ["@", "#", "/", "\\", ".", "_", ":", "$", "~", "=", "<", "&"]

    public init(config: Config = Config()) {
        self.config = config
        comp = Composer(config)
    }

    /// Quên mọi trạng thái: gọi khi con trỏ có thể đã di chuyển (chuột, mũi tên, đổi app, phím tắt).
    public func reset() {
        comp = Composer(config); screen = ""; history = []
        sepRun = ""; capBlocked = false; englishStreak = 0; reopened = false; prefixTyped = false; afterPrefix = false
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
        replaced = nil
        var fed = ch
        if comp.isEmpty, ch.isASCII, ch.isLetter {  // bắt đầu một từ mới
            comp = Composer(config)
            afterPrefix = prefixTyped && !config.smartMacros.isEmpty
            if afterPrefix || (config.codeAware && (sepRun.last.map { Engine.codeMarks.contains($0) || $0.isNumber } ?? false)) {
                comp.startLiteral()  // tên gõ tắt thông minh luôn là nguyên văn, kể cả khi tắt "ngữ cảnh code"
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
        prefixTyped = false
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
        // Dấu `\` ở ĐẦU TỪ mở một tên gõ tắt thông minh: trước nó là đầu dòng, khoảng trắng hoặc dấu mở ngoặc / nháy.
        // Sau một chữ ("C:\ten", "a\b") thì không: đó là đường dẫn.
        let wasPrefixed = afterPrefix
        afterPrefix = false
        prefixTyped = ch == "\\" && comp.isEmpty && (sepRun.last.map { $0.isWhitespace || "([{\"'“‘".contains($0) } ?? true)
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
        // Từ thành nguyên văn vì một phím gõ thừa ("ddaayy") rồi người dùng xoá phím đó đi: lúc ngắt từ, phần còn lại
        // được hiểu lại như vừa gõ mới ("ddaay" -> "đây"), giống khi họ gõ tiếp một chữ. Không làm lúc xoá lùi: phím
        // xoá không bao giờ được đụng tới màn hình (người dùng hỏi 2026-11-25).
        if let fresh = recomposed() { comp = fresh }
        let typed = comp.rawString
        // Gõ lại đúng từ vừa xoá: nhớ dạng còn lại TRƯỚC khi phân xử, để lần gõ này đã ra dạng đó.
        if let p = pending, p.typed == typed { learn(raw: typed, wantRaw: p.wantRaw) }
        let glued = config.codeAware && config.autoRestore && (ch == "_" || ch == "@")
        // Lỗi gõ quen tay: VNKey không tự sửa, chỉ ghi lại để bộ soát lỗi (`Proofreader`) đề nghị. Người dùng vừa tự
        // sửa thì ghi cặp (phím sai -> phím đúng); gõ một chuỗi đã từng sửa mà để nguyên thì đếm là "để nguyên".
        var keptTypo: String?
        if let model = context, !glued, !comp.codeLiteral, Engine.isPlainKeys(typed) {
            let key = typed.lowercased()
            if let wrong = corrected?.lowercased(), Engine.isPlainKeys(wrong), Engine.oneKeyApart(wrong, key) {
                model.recordTypo(wrong, fixed: key)
                note = "ghi một lần sửa lỗi gõ (\(wrong.count) -> \(key.count) phím)"  // không ghi nội dung
            } else if corrected == nil, model.keepTypo(key) {
                keptTypo = key
            }
        }
        let composed = comp.shown
        // Từ dính liền "_" hoặc "@" phía sau là tên biến / địa chỉ: giữ phím gốc.
        var final = glued ? comp.rawString : decide()
        var resumable = true
        if let m = expansion(for: final) { final = m; resumable = false; replaced = m }
        trackLanguage(final: final, composed: composed)
        // Ghi nhận từ người dùng tự gõ mà từ điển coi là tiếng Việt (không tính từ bung ra từ gõ tắt), kể cả từ
        // không dấu ("nay" trong "hôm nay", "to do"): số lần gõ dạng không dấu là bằng chứng duy nhất cho biết
        // người dùng có thật sự viết cặp từ ấy như vậy, để bộ soát lỗi không đề nghị "sửa" nhầm.
        var recorded: (word: String, prev: String?)?
        if let model = context, resumable, final == composed, lexicon?.isVietnamese(final.lowercased()) == true {
            recorded = (final.lowercased(), previousWord())
            model.record(recorded!.word, after: recorded!.prev)
        }

        var out = Output.pass
        if wasPrefixed, let template = config.smartMacros[typed.lowercased()] {
            // `\tên` của một gõ tắt thông minh: xoá cả dấu `\` lẫn tên, gõ nội dung (biến đã thay giá trị).
            final = SmartMacro.resolve(template, at: now(), extra: variable)
            resumable = false
            replaced = final
            out = Output(backspaces: screen.count + 1, text: final, passKey: true)
            if let last = history.indices.last, history[last].sep.hasSuffix("\\") { history[last].sep.removeLast() }
        } else if final != screen {
            let p = commonPrefix(screen, final)
            out = Output(backspaces: screen.count - p, text: String(final.dropFirst(p)), passKey: true)
        }
        history.append(
            Entry(
                comp: comp, raw: comp.rawString, composed: composed, final: final, sep: String(ch), resumable: resumable,
                typed: typed, recorded: recorded, keptTypo: keptTypo))
        if history.count > historyLimit { history.removeFirst() }
        if hard { history = [] }
        reopened = false
        freshBreak = !hard && resumable && composed != comp.rawString
        comp = Composer(config); screen = ""
        return out
    }

    /// `held`: phím xoá đang được giữ (sự kiện lặp). Khi đó không bao giờ đổi chữ.
    public func backspace(held: Bool = false) -> Output {
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
        let before = screen
        comp.backspace(dropTone: screen.last.map(Engine.carriesTone) ?? false)
        if !screen.isEmpty { screen.removeLast() }
        if comp.isEmpty {
            screen = ""
            retype = watch  // đã xoá hết từ vừa gõ: chờ xem có gõ lại y nguyên không
            watch = nil
        }
        // THỬ NGHIỆM: phần còn lại hiểu lại được thành tiếng Việt (và lúc ngắt từ sẽ không bị trả về phím gốc) thì
        // đổi chữ ngay. Phím xoá của người dùng bị nuốt; thay vào đó xoá tới chỗ hai chữ còn giống nhau rồi gõ phần mới.
        if comp.isEmpty {
            reopened = false
            prefixTyped = afterPrefix  // xoá hết tên gõ dở: vẫn đang đứng ngay sau dấu `\`
            afterPrefix = false
        }
        if config.retryOnBackspace, !held, !reopened, !comp.isEmpty, let fresh = recomposed(), fresh.shown != screen {
            let kept = comp
            comp = fresh
            let stays = decide() == fresh.shown
            comp = kept
            if stays {
                let p = commonPrefix(before, fresh.shown)
                comp = fresh
                screen = fresh.shown
                note = "hiểu lại từ ngay khi xoá (\(fresh.raw.count) phím)"
                return Output(backspaces: before.count - p, text: String(fresh.shown.dropFirst(p)), passKey: false)
            }
        }
        return .pass
    }

    /// Từ đang nguyên văn vì một phím gõ nhầm ("thii", "vieejk") và người dùng đã xoá bớt: khi họ gõ chữ
    /// kế tiếp, phần còn lại được hiểu như vừa gõ mới, để gõ tiếp tiếng Việt mà không phải xoá về tận
    /// khoảng trắng. Chỉ làm lúc có phím mới (không làm lúc xoá): xoá lùi không được đụng tới màn hình, và
    /// một từ đã hiểu lại mà màn hình còn là phím thô ("vieej") sẽ lệch nếu bị xoá tiếp.
    private func recomposed() -> Composer? {
        guard comp.retry, comp.isLiteral, !comp.codeLiteral, !comp.noRecompose else { return nil }
        if comp.raw.allSatisfy({ $0.isASCII && $0.isLetter }) {
            guard let fresh = Composer.replay(comp.raw, config), !fresh.isLiteral else { return nil }
            return fresh
        }
        // Phần còn lại là CHỮ đã có dấu chứ không phải chuỗi phím ("Đ" sau khi gõ "Ddj" rồi xoá "j": phím dấu gõ
        // lúc chưa có nguyên âm làm từ thành nguyên văn và giữ chữ đang hiện). Dịch chữ đó ngược về phím rồi gõ
        // lại; chỉ nhận khi ra đúng chữ đang có trên màn hình. Thiếu bước này "Ddj<ajt" ra "Đajt" (lỗi gặp thật).
        guard let keys = Engine.keys(for: comp.shown, config.method), let fresh = Composer.replay(keys, config),
            !fresh.isLiteral, fresh.shown == comp.shown
        else { return nil }
        return fresh
    }

    /// Chuỗi phím gõ ra đúng đoạn chữ tiếng Việt `text` theo kiểu gõ `method` ("Đạ" -> "Ddaj" / "D9a5"). nil nếu có ký
    /// tự không phải chữ cái.
    static func keys(for text: String, _ method: Method) -> [Character]? {
        var out: [Character] = []
        for ch in text.precomposedStringWithCanonicalMapping {
            guard let i = Charset.letterInfo(ch) else {
                guard ch.isASCII, ch.isLetter else { return nil }
                out.append(ch)
                continue
            }
            let base = Syl.unmark(i.plain)
            out.append(i.upper ? Character(base.uppercased()) : base)
            switch i.plain {
            case "đ": out.append(method.isTelex ? "d" : "9")
            case "â", "ê", "ô": out.append(method.isTelex ? base : "6")
            case "ă": out.append(method.isTelex ? "w" : "8")
            case "ơ", "ư": out.append(method.isTelex ? "w" : "7")
            default: break
            }
            if i.tone != .none {
                out.append(Array(method.isTelex ? "sfrxj" : "12345")[i.tone.rawValue - 1])
            }
        }
        return out
    }

    private static let toneMarks: Set<Unicode.Scalar> = ["\u{301}", "\u{300}", "\u{309}", "\u{303}", "\u{323}"]

    /// Ký tự đang mang dấu thanh (sắc, huyền, hỏi, ngã, nặng).
    static func carriesTone(_ ch: Character) -> Bool {
        String(ch).decomposedStringWithCanonicalMapping.unicodeScalars.contains(where: toneMarks.contains)
    }

    /// Quay lại sửa từ trước đó, giữ nguyên thứ tự phím đã gõ.
    private func resume(_ e: Entry) {
        reopened = true
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

    /// Từ đứng ngay trước từ đang gõ trong cùng một cụm (cách nhau đúng một dấu cách), chữ thường.
    private func previousWord() -> String? {
        guard let e = history.last, e.sep == " " else { return nil }
        return e.final.lowercased()
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
            // Giữa một mạch tiếng Anh, từ hợp lệ ở cả hai ngôn ngữ coi là tiếng Anh ("this" chứ không "thí"), TRỪ KHI chữ
            // tiếng Việt là từ rất thông dụng ("cos" là "có"): đang ở chế độ tiếng Việt thì tiếng Việt được ưu tiên (người
            // dùng chốt 2026-11-25). Không có ngoại lệ này thì "cos" bị trả lại, lần trả lại đó nối dài mạch tiếng Anh,
            // và gõ lại bao nhiêu lần vẫn ra "cos" (lỗi gặp thật).
            if config.contextAware, englishStreak >= 2, CommonWords.count(shown) < CommonWords.veryCommon { return raw }
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
        guard !comp.codeLiteral,
            let template = config.macros[key] ?? (config.expandTeen ? Engine.teenExpansions[key] : nil)
        else { return nil }
        let full = SmartMacro.resolve(template, at: now(), extra: variable)  // biến: "[ngay]" -> 25/11/2026
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
