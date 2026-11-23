import Foundation
import Testing

@testable import VNEngine
@testable import VNKeyCore

@Suite struct Hotkeys {
    @Test func roundTrip() {
        for h in [Hotkey.defaultToggle, .defaultRestore, Hotkey(code: 49, mods: Mods.command | Mods.shift, keyLabel: "Space")] {
            #expect(Hotkey(string: h.string) == h)
        }
    }

    @Test(arguments: ["", "abc", "6:0:Z", "6:786432", "x:786432:Z"])
    func rejectsMalformed(s: String) { #expect(Hotkey(string: s) == nil) }

    @Test func labels() {
        #expect(Hotkey.defaultToggle.label == "⌃⇧")
        #expect(Hotkey.defaultRestore.label == "⌃⌥Z")
        #expect(Hotkey(string: "6:786432:a:b")?.keyLabel == "a:b")  // nhãn có thể chứa dấu ":"
    }

    @Test func matching() {
        let h = Hotkey.defaultRestore
        #expect(h.matches(code: 6, mods: Mods.control | Mods.option))
        #expect(h.matches(code: 6, mods: Mods.control | Mods.option | 1 << 8))  // bit ngoài mặt nạ bị bỏ qua
        #expect(!h.matches(code: 6, mods: Mods.control))
        #expect(!h.matches(code: 6, mods: Mods.control | Mods.option | Mods.shift))
        #expect(!h.matches(code: 7, mods: Mods.control | Mods.option))
        #expect(!Hotkey.defaultToggle.matches(code: -1, mods: Mods.control | Mods.shift))  // chỉ phím bổ trợ
    }
}

@Suite struct Modifiers {
    let cs = Mods.control | Mods.shift

    @Test func cleanPressAndRelease() {
        var t = ModifierTracker()
        #expect(t.flagsChanged(Mods.control) == nil)
        #expect(t.flagsChanged(cs) == nil)
        #expect(t.flagsChanged(Mods.shift) == nil)  // thả từng phím một
        #expect(t.flagsChanged(0) == cs)
        #expect(t.flagsChanged(0) == nil)  // không kích hoạt lần hai
    }

    @Test func keyInBetweenCancels() {
        var t = ModifierTracker()
        _ = t.flagsChanged(cs)
        t.interrupted()  // ví dụ ⌃⇧A
        #expect(t.flagsChanged(0) == nil)
        _ = t.flagsChanged(cs)  // lần sau vẫn hoạt động
        #expect(t.flagsChanged(0) == cs)
    }

    @Test func interruptionBeforePressDoesNotLeak() {
        var t = ModifierTracker()
        t.interrupted()
        #expect(t.flagsChanged(0) == nil)  // gõ phím thường rồi mới nhấn tổ hợp
        _ = t.flagsChanged(cs)
        #expect(t.flagsChanged(0) == cs)
    }

    @Test func singleShiftReportsItself() {
        var t = ModifierTracker()
        _ = t.flagsChanged(Mods.shift)
        #expect(t.flagsChanged(0) == Mods.shift)  // không trùng phím tắt mặc định nào
    }
}

@Suite struct Keys {
    @Test func classification() {
        #expect(classifyKey(code: 51, chars: "\u{7F}") == .backspace)
        #expect(classifyKey(code: 36, chars: "\r") == .newline)
        #expect(classifyKey(code: 76, chars: "\u{3}") == .newline)
        #expect(classifyKey(code: 48, chars: "\t") == .tab)
        for code in [53, 117, 115, 116, 119, 121, 123, 124, 125, 126] {
            #expect(classifyKey(code: code, chars: "\u{F702}") == .navigation)
        }
        #expect(classifyKey(code: 0, chars: "a") == .character("a"))
        #expect(classifyKey(code: 0, chars: "A") == .character("A"))
        #expect(classifyKey(code: 49, chars: " ") == .character(" "))
        #expect(classifyKey(code: 0, chars: "é") == .character("é"))
        #expect(classifyKey(code: 122, chars: "\u{F704}") == .unprintable)  // F1
        #expect(classifyKey(code: 0, chars: "") == .unprintable)  // phím chết
        #expect(classifyKey(code: 0, chars: "ab") == .unprintable)
    }
}

@Suite struct Planning {
    func plan(
        _ bs: Int, _ text: String, pass: Bool = false, app: String = "com.apple.TextEdit", sel: Int? = 0, fix: Bool = true,
        role: String = "?"
    ) -> SendPlan {
        SendPlanner.plan(
            backspaces: bs, text: text, passKey: pass, app: app, selection: sel, fixAutocomplete: fix, role: role)
    }

    @Test func fieldRoles() {
        for role in ["AXTextField", "AXComboBox", "AXSearchField"] {
            #expect(SendPlanner.shouldAskSelection(app: "com.apple.Safari", role: role))
        }
        for role in ["AXTextArea", "AXWebArea", "AXGroup", "?"] {
            #expect(!SendPlanner.shouldAskSelection(app: "com.apple.Safari", role: role))
        }
        #expect(!SendPlanner.shouldAskSelection(app: "com.apple.campo", role: "AXTextField"))
    }

    /// Trong nội dung trang web (vùng nhiều dòng) không có gợi ý nối đuôi: không chèn ký tự rỗng.
    @Test func browserPageContentIsPlain() {
        #expect(plan(1, "ô", app: "com.apple.Safari", sel: nil, role: "AXTextArea").steps == [.backspace(1), .text("ô")])
        #expect(plan(1, "ô", app: "com.apple.Safari", sel: nil, role: "AXWebArea").mode == "plain")
        #expect(plan(1, "ô", app: "com.apple.Safari", sel: nil, role: "AXTextField").mode == "emptyChar")
        #expect(plan(1, "ô", app: "com.apple.Safari", sel: nil, role: "?").mode == "emptyChar")  // không biết: giữ cách cũ
    }

    @Test func plain() {
        #expect(plan(1, "ô") == SendPlan(mode: "plain", steps: [.backspace(1), .text("ô")]))
        #expect(plan(0, "ô") == SendPlan(mode: "plain", steps: [.text("ô")]))
        #expect(plan(2, "", pass: true) == SendPlan(mode: "plain", steps: [.backspace(2), .original]))
    }

    @Test func spotlightNudges() {
        for app in ["com.apple.campo", "com.apple.Spotlight"] {
            #expect(plan(2, "ôi", app: app).steps == [.arrowLeft, .arrowRight, .backspace(2), .text("ôi")])
        }
        #expect(plan(0, "x", app: "com.apple.campo").steps == [.text("x")])  // không xoá thì không cần nhích
    }

    @Test func browserUsesEmptyChar() {
        let p = plan(1, "ô", app: "com.google.Chrome", sel: nil)
        #expect(p.mode == "emptyChar")
        #expect(p.steps == [.text(SendPlanner.emptyChar), .backspace(2), .text("ô")])
    }

    /// Lỗi nuốt ký tự ở thanh địa chỉ Safari (22/11/2026): Accessibility báo rõ không có vùng bôi chọn
    /// (sel = 0) thì không có gợi ý nào để chốt; chèn ký tự rỗng rồi xoá thêm một phím là thừa và
    /// có thể xoá lố chữ thật. Chỉ dùng ký tự rỗng khi KHÔNG biết vùng chọn.
    @Test func knownEmptySelectionIsPlain() {
        for app in ["com.apple.Safari", "com.google.Chrome"] {
            let p = plan(1, "â", app: app, sel: 0, role: "AXTextField")
            #expect(p.mode == "plain")
            #expect(p.steps == [.backspace(1), .text("â")])
            #expect(plan(1, "â", app: app, sel: nil, role: "AXTextField").mode == "emptyChar")
        }
    }

    @Test func selectionWinsOverAppLists() {
        for app in ["com.google.Chrome", "com.apple.campo", "com.apple.TextEdit"] {
            let p = plan(1, "ô", app: app, sel: 3)
            #expect(p.mode == "selection")
            #expect(p.steps == [.backspace(2), .text("ô")])
        }
    }

    @Test func fixCanBeTurnedOff() {
        #expect(plan(1, "ô", app: "com.apple.campo", sel: 3, fix: false).steps == [.backspace(1), .text("ô")])
    }

    @Test func chunking() {
        #expect(SendPlanner.chunks("").isEmpty)
        #expect(SendPlanner.chunks("tiếng").count == 1)
        let long = String(repeating: "ờ", count: 40)
        let parts = SendPlanner.chunks(long)
        #expect(parts.map(\.count) == [16, 16, 8])
        #expect(String(utf16CodeUnits: parts.flatMap { $0 }, count: 40) == long)
        // Emoji là cặp surrogate: không được xẻ đôi ở ranh giới đoạn.
        let emoji = String(repeating: "a", count: 15) + "😀" + "b"
        let e = SendPlanner.chunks(emoji)
        #expect(e.map(\.count) == [15, 3])
        #expect(e.allSatisfy { String(utf16CodeUnits: $0, count: $0.count).unicodeScalars.allSatisfy { $0.value != 0xFFFD } })
    }
}

@Suite struct Modes {
    func mode(_ b: String, excluded: Set<String> = [], perApp: Bool = false, states: [String: Bool] = [:], global: Bool = true)
        -> Bool
    {
        AppMode.initial(bundle: b, excluded: excluded, perApp: perApp, states: states, global: global)
    }

    @Test func rules() {
        #expect(mode("a"))
        #expect(!mode("a", global: false))
        #expect(!mode("term", excluded: ["term"]))
        #expect(!mode("term", excluded: ["term"], perApp: true, states: ["term": true]))  // loại trừ thắng
        #expect(!mode("a", perApp: true, states: ["a": false]))
        #expect(mode("a", perApp: true, states: ["a": true], global: false))
        #expect(mode("a", perApp: false, states: ["a": false]))  // tắt "nhớ theo app" thì bỏ qua trạng thái đã lưu
        #expect(mode("b", perApp: true, states: ["a": false]))  // app chưa có trạng thái: theo chế độ chung
    }
}

@Suite struct Lists {
    @Test func lines() {
        #expect(ListFormat.lines("  a \n\nb\r\na\n \n") == ["a", "b"])
        #expect(ListFormat.lines("").isEmpty)
    }

    @Test func macros() {
        let d = ListFormat.macros(from: "VN = Việt Nam\nkhông có dấu bằng\n = thiếu khoá\nx =\nurl = a=b\n  ko=không  ")
        #expect(d == ["vn": "Việt Nam", "url": "a=b", "ko": "không"])
        #expect(ListFormat.macros(from: ListFormat.text(from: d)) == d)
        #expect(ListFormat.text(from: ["b": "2", "a": "1"]) == "a = 1\nb = 2")
    }

    @Test func controlCharacters() {
        #expect(showControl("a b\n\t\u{202F}") == "\"a␣b⏎⇥\\u{202f}\"")
    }
}

// MARK: - Giả lập ô nhập để kiểm tra cả đường đi engine -> kế hoạch gửi -> màn hình

/// Mô hình ô nhập của vài loại ứng dụng. Đây là GIẢ THUYẾT về cách ứng dụng thật phản ứng, dựng từ
/// nhật ký và quan sát của người dùng; chúng bắt lỗi hồi quy chứ không thay được việc gõ thử thật.
struct Field {
    enum Kind {
        /// Ô thường: không có gợi ý.
        case plain
        /// Spotlight: gợi ý nằm ngoài nội dung; phím xoá đầu tiên chỉ gạt gợi ý.
        /// `leftAbsorbed`: phím ← chỉ gạt gợi ý (không dời con trỏ) hay vừa gạt vừa dời.
        case spotlight(leftAbsorbed: Bool)
        /// Trình duyệt: gợi ý được chèn vào sau con trỏ và bôi chọn.
        case browser
        /// Vùng soạn thảo nhiều dòng trong trang web: không có gợi ý nối đuôi.
        case browserPage
    }

    let kind: Kind
    var text = ""
    var caret = 0  // tính theo ký tự, từ đầu
    var suggestion = false  // kiểu Spotlight
    var selected = ""  // kiểu trình duyệt: phần gợi ý đang bôi chọn sau con trỏ

    var app: String {
        switch kind {
        case .plain: return "com.apple.TextEdit"
        case .spotlight: return "com.apple.campo"
        case .browser, .browserPage: return "com.google.Chrome"
        }
    }
    var role: String {
        if case .browserPage = kind { return "AXTextArea" }
        return "AXTextField"
    }
    /// Điều Accessibility báo về vùng chọn; nil khi app quyết định không hỏi (như KeyTap.focus).
    var axSelection: Int? { SendPlanner.shouldAskSelection(app: app, role: role) ? selected.count : nil }

    private var index: String.Index { text.index(text.startIndex, offsetBy: caret) }

    mutating func insert(_ s: String) {
        selected = ""
        text.insert(contentsOf: s, at: index)
        caret += s.count
        guard caret == text.count, let last = s.last, last.isLetter else { suggestion = false; return }
        switch kind {
        case .plain, .browserPage: break
        case .spotlight: suggestion = true
        case .browser: selected = "gợiý"
        }
    }

    mutating func backspace() {
        if !selected.isEmpty { selected = ""; return }
        if suggestion { suggestion = false; return }
        guard caret > 0 else { return }
        caret -= 1
        text.remove(at: index)
    }

    mutating func left() {
        if !selected.isEmpty { selected = ""; return }
        if suggestion {
            suggestion = false
            if case .spotlight(leftAbsorbed: true) = kind { return }
        }
        caret = max(0, caret - 1)
    }

    mutating func right() {
        selected = ""
        caret = min(text.count, caret + 1)
    }
}

/// Gõ một chuỗi phím qua engine và kế hoạch gửi, áp lên ô nhập giả. "<" = Backspace.
func typeInto(_ kind: Field.Kind, _ keys: String, fix: Bool = true) -> String {
    let engine = Engine()
    var field = Field(kind: kind)
    for ch in keys {
        func original() { if ch == "<" { field.backspace() } else { field.insert(String(ch)) } }
        var out: Output
        if ch == "<" {  // giống hệt nhánh .backspace trong KeyTap.keyDown
            var route = SendPlanner.BackspaceRoute.normal
            if fix, engine.isTracking {
                route = SendPlanner.userBackspace(app: field.app, selection: field.axSelection, fixAutocomplete: true)
            }
            if route == .suggestionOnly { original(); continue }
            out = engine.backspace()
            if out.isPass, route == .planned { out = Output(backspaces: 1, text: "", passKey: false) }
        } else {
            out = engine.type(ch)
        }
        if out.isPass { original(); continue }
        let plan = SendPlanner.plan(
            backspaces: out.backspaces, text: out.text, passKey: out.passKey, app: field.app,
            selection: out.backspaces > 0 && fix ? field.axSelection : nil, fixAutocomplete: fix, role: field.role)
        for step in plan.steps {
            switch step {
            case .arrowLeft: field.left()
            case .arrowRight: field.right()
            case .backspace(let n): for _ in 0..<n { field.backspace() }
            case .text(let t): if t == SendPlanner.emptyChar { field.selected = ""; field.text.insert(contentsOf: t, at: field.text.index(field.text.startIndex, offsetBy: field.caret)); field.caret += 1 } else { field.insert(t) }
            case .original: original()
            }
        }
    }
    return field.text
}

@Suite struct EndToEnd {
    static let cases: [(String, String)] = [
        ("toio ddang muoons timf", "tôi đang muốn tìm"),
        ("tooi", "tôi"),
        ("tieengs vieetj", "tiếng việt"),
        ("dduwowcj", "được"),
        ("user ", "user "),
        ("vieetj <s", "viết"),
        ("tieengs<<", "tiế"),
        ("hoanf<", "hoà"),
    ]

    @Test(arguments: cases) func plainField(keys: String, want: String) {
        #expect(typeInto(.plain, keys) == want)
    }

    @Test(arguments: cases) func spotlightLeftAbsorbed(keys: String, want: String) {
        #expect(typeInto(.spotlight(leftAbsorbed: true), keys) == want)
    }

    @Test(arguments: cases) func spotlightLeftMoves(keys: String, want: String) {
        #expect(typeInto(.spotlight(leftAbsorbed: false), keys) == want)
    }

    /// Trình duyệt: phím xoá lùi đầu tiên của người dùng chỉ gạt gợi ý (hành vi gốc của trình duyệt),
    /// nên engine phải giữ nguyên trạng thái ở lần nhấn đó.
    @Test(arguments: [
        ("toio ddang muoons timf", "tôi đang muốn tìm"), ("tooi", "tôi"), ("dduwowcj", "được"), ("user ", "user "),
        ("vieetj <s", "viết"), ("tieengs<", "tiếng"), ("tieengs<<", "tiến"), ("tieengs<<<", "tiế"), ("tieengs<<<f", "tiề"),
        ("hoanf<<", "hoà"),
    ])
    func browser(keys: String, want: String) {
        #expect(typeInto(.browser, keys) == want)
    }

    @Test(arguments: cases) func browserPageContent(keys: String, want: String) {
        #expect(typeInto(.browserPage, keys) == want)
    }

    @Test func backspaceRoutes() {
        typealias R = SendPlanner.BackspaceRoute
        func r(_ app: String, _ sel: Int?, _ fix: Bool = true) -> R {
            SendPlanner.userBackspace(app: app, selection: sel, fixAutocomplete: fix)
        }
        #expect(r("com.apple.TextEdit", 0) == .normal)
        #expect(r("com.apple.TextEdit", nil) == .normal)
        #expect(r("com.google.Chrome", 4) == .suggestionOnly)
        #expect(r("com.google.Chrome", 0) == .normal)
        #expect(r("com.apple.campo", 0) == .planned)
        #expect(r("com.apple.campo", 2) == .suggestionOnly)
        #expect(r("com.apple.campo", 0, false) == .normal)
    }

    /// Đối chứng: tắt bản sửa thì mô hình Spotlight phải tái hiện đúng lỗi người dùng đã thấy.
    @Test func modelReproducesOriginalBug() {
        #expect(typeInto(.spotlight(leftAbsorbed: true), "toio", fix: false) == "toôi")
        #expect(typeInto(.plain, "toio", fix: false) == "tôi")
    }
}

@Suite struct Perf {
    @Test func accumulates() {
        var p = PerfStats()
        p.key(2_000); p.key(4_000); p.key(1_500_000); p.key(12_000_000)
        p.ax(900_000); p.ax(100_000)
        #expect(p.keys == 4)
        #expect(p.over1ms == 2)
        #expect(p.over10ms == 1)
        #expect(p.maxNs == 12_000_000)
        #expect(p.axCalls == 2)
        #expect(p.axMaxNs == 900_000)
        #expect(p.summary == "phím=4 tb=3376µs max=12.00ms ≥1ms=2 ≥10ms=1 | ax=2 tb=500µs max=0.90ms")
        p.reset()
        #expect(p.keys == 0)
        #expect(p.summary.contains("tb=-µs"))
    }
}

@Suite struct ScreenChecks {
    @Test func compare() {
        typealias C = ScreenCheck
        #expect(C.compare(value: "tôi đang", caret: 8, expected: "đang") == .match)
        #expect(C.compare(value: "tôi đang gợi ý", caret: 8, expected: "đang") == .match)  // gợi ý nằm sau con trỏ
        #expect(C.compare(value: "to\u{302}i", caret: 4, expected: "tôi") == .match)  // dạng tổ hợp
        #expect(C.compare(value: "toôi", caret: 4, expected: "tôi") == .mismatch(expected: "tôi", actual: "toôi"))
        #expect(C.compare(value: "ây", caret: 2, expected: "Đây") == .mismatch(expected: "Đây", actual: "ây"))
        #expect(C.compare(value: "a😀tôi", caret: 6, expected: "tôi") == .match)  // con trỏ tính theo UTF-16
        #expect(C.compare(value: "tôi", caret: 99, expected: "tôi") == .match)
    }
}

/// Lỗi nuốt chữ trong Safari (22/11/2026): gõ "ddia" rồi "j" khi chưa nhả phím "a" thì đoạn "ịa" bị mất.
/// VNKey gửi chữ bằng sự kiện phím mang mã 0 (= phím A); ứng dụng thấy phím A đang được giữ nên coi đó
/// là phím lặp và bỏ qua. Sự kiện mang chữ phải dùng mã phím không trùng phím nào đang giữ.
@Suite struct Carriers {
    @Test func avoidsHeldKeys() {
        var h = HeldKeys()
        #expect(h.carrier == 0)
        h.down(0)  // đang giữ phím A
        #expect(h.carrier != 0)
        #expect(!h.isDown(h.carrier))
        h.up(0)
        #expect(h.carrier == 0)
    }

    @Test func manyKeysHeld() {
        var h = HeldKeys()
        for code in HeldKeys.candidates.dropLast() { h.down(code) }
        #expect(h.carrier == HeldKeys.candidates.last)
        h.down(HeldKeys.candidates.last!)
        #expect(HeldKeys.candidates.contains(h.carrier))  // hết lựa chọn: vẫn trả về một mã hợp lệ
        h.clear()
        #expect(h.carrier == 0)
    }

    @Test func forgetsStaleKeys() {
        var h = HeldKeys()
        h.down(0, at: 0)
        #expect(h.isDown(0, at: 1_000_000_000))
        #expect(!h.isDown(0, at: 3_000_000_000))  // lỡ mất sự kiện nhả phím: tự quên sau 2 giây
        #expect(h.carrier(at: 3_000_000_000) == 0)
    }
}

@Suite struct FocusPolicies {
    @Test func pointerAndArrowsKeepTheCache() {
        #expect(FocusPolicy.action(after: .pointer) == .refreshInBackground)
        #expect(FocusPolicy.action(after: .navigation) == .refreshInBackground)
    }

    @Test func leavingTheFieldDropsTheCache() {
        for e in [FocusPolicy.Event.shortcut, .fieldExit, .appSwitch, .system] {
            #expect(FocusPolicy.action(after: e) == .drop)
        }
    }

    @Test func heldBackspaceAsksOnce() {
        #expect(FocusPolicy.asksSelectionOnBackspace(repeated: false, hasPrevious: true))
        #expect(FocusPolicy.asksSelectionOnBackspace(repeated: true, hasPrevious: false))
        #expect(!FocusPolicy.asksSelectionOnBackspace(repeated: true, hasPrevious: true))
    }

    @Test func staleBackgroundLookupIsIgnored() {
        #expect(FocusPolicy.acceptsBackgroundResult(sameEpoch: true, haveFresh: false))
        #expect(!FocusPolicy.acceptsBackgroundResult(sameEpoch: false, haveFresh: false))
        #expect(!FocusPolicy.acceptsBackgroundResult(sameEpoch: true, haveFresh: true))
    }

    @Test func screenCheckWorksOnATailWindow() {
        // Chỉ đọc đoạn ngay trước con trỏ: caret = độ dài đoạn.
        let tail = "thanh địa"
        #expect(ScreenCheck.compare(value: tail, caret: tail.utf16.count, expected: "địa") == .match)
    }
}

@Suite struct Logging {
    @Test func linesAreWrittenInOrderAfterFlush() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vnkey-test-\(UUID().uuidString).log")
        let oldURL = Log.url, oldEnabled = Log.enabled
        defer { Log.flush(); Log.url = oldURL; Log.enabled = oldEnabled; try? FileManager.default.removeItem(at: url) }
        Log.url = url
        Log.enabled = true
        for i in 0..<50 { Log.write("dòng \(i)") }
        Log.flush()
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 50)
        #expect(lines.first?.hasSuffix("dòng 0") == true)
        #expect(lines.last?.hasSuffix("dòng 49") == true)
    }

    @Test func disabledLogDoesNotBuildTheLine() {
        let oldEnabled = Log.enabled
        defer { Log.enabled = oldEnabled }
        Log.enabled = false
        var built = false
        Log.write({ built = true; return "x" }())
        #expect(!built)
    }
}

@Suite struct SettingsRules {
    @Test func shiftPlusKeyIsNotAHotkey() {
        #expect(Hotkey(code: 0, mods: Mods.shift, keyLabel: "A").problem(other: nil) == .shiftOnly)
        #expect(Hotkey(code: 0, mods: Mods.shift | Mods.control, keyLabel: "A").problem(other: nil) == nil)
        #expect(Hotkey.defaultToggle.problem(other: .defaultRestore) == nil)
    }

    @Test func twoHotkeysMustDiffer() {
        #expect(Hotkey.defaultToggle.problem(other: .defaultToggle) == .duplicate)
        let z = Hotkey(code: 6, mods: Mods.control | Mods.option, keyLabel: "z")
        #expect(z.problem(other: .defaultRestore) == .duplicate)  // nhãn khác nhau vẫn là cùng một phím
    }

    @Test func malformedMacroLinesAreCounted() {
        #expect(ListFormat.skippedMacroLines(in: "vn = Việt Nam\n\nhn=Hà Nội") == 0)
        #expect(ListFormat.skippedMacroLines(in: "vn = Việt Nam\nsai dòng\n= thiếu khoá\nthiếu vế =") == 3)
    }
}

@Suite struct TableRules {
    @Test func macroRowsAreValidated() {
        let r = ListFormat.macros(fromRows: [
            ["VN", " Việt Nam "], ["", ""], ["hn", ""], ["", "thiếu khoá"], ["a b", "có dấu cách"], ["x1", "có số"],
            ["đc", "được"], ["vn", "Việt Nam 2"],
        ])
        #expect(r.macros == ["vn": "Việt Nam 2", "đc": "được"])
        #expect(r.skipped == 4)
    }

    @Test func macroRowsRoundTrip() {
        let m = ["vn": "Việt Nam", "hn": "Hà Nội"]
        #expect(ListFormat.macros(fromRows: ListFormat.rows(from: m)).macros == m)
    }

    @Test func learnedRowsSplitIntoTwoLists() {
        let r = ListFormat.learned(fromRows: [["This", "0"], ["test", "1"], ["", "0"], ["this", "1"], ["user", "0"]])
        #expect(r.raw == ["user"])
        #expect(r.vn == ["this", "test"])
        #expect(ListFormat.learnedRows(raw: ["user"], vn: ["test"]) == [["test", "1"], ["user", "0"]])
    }
}
