import Foundation

public enum Method: String, Sendable { case telex, vni }
public enum Tone: Int, Sendable { case none = 0, sac, huyen, hoi, nga, nang }

enum Mark { case none, hat, breve, horn, bar }

struct Letter {
    var base: Character
    var mark: Mark = .none
    var upper = false
    /// Chữ "ư" sinh ra từ phím w đứng một mình.
    var fromW = false

    var isVowel: Bool { "aeiouy".contains(base) }

    /// Chữ thường có dấu mũ/móc, chưa có thanh.
    var plain: Character {
        switch (base, mark) {
        case ("a", .hat): return "â"
        case ("a", .breve): return "ă"
        case ("e", .hat): return "ê"
        case ("o", .hat): return "ô"
        case ("o", .horn): return "ơ"
        case ("u", .horn): return "ư"
        case ("d", .bar): return "đ"
        default: return base
        }
    }

    func glyph(_ tone: Tone) -> String {
        var s = String(plain)
        switch tone {
        case .none: break
        case .sac: s += "\u{301}"
        case .huyen: s += "\u{300}"
        case .hoi: s += "\u{309}"
        case .nga: s += "\u{303}"
        case .nang: s += "\u{323}"
        }
        s = s.precomposedStringWithCanonicalMapping
        return upper ? s.uppercased() : s
    }
}

/// Trạng thái soạn của MỘT từ. Giữ nguyên chuỗi phím thô theo thứ tự gõ (`raw`)
/// và mỗi phím thuộc về chữ nào (`owner`) để có thể khôi phục / xoá lùi chính xác.
struct Composer {
    let method: Method
    let modernTone: Bool
    let standaloneW: Bool
    let teen: Bool

    var letters: [Letter] = []
    var tone: Tone = .none
    var raw: [Character] = []
    /// Với mỗi phím thô: chỉ số chữ mà nó tạo/sửa, -1 = phím thanh, -2 = phím đã bị huỷ.
    var owner: [Int] = []
    /// Khác nil = chế độ nguyên văn: từ không thể là tiếng Việt, phím sau chỉ nối thêm.
    var override: String?
    /// Người dùng đã gõ lặp phím để huỷ dấu (vd "ass" -> "as").
    var cancelled = false
    /// Từ toàn phụ âm có biến đổi (vd "đc"): giữ nguyên kết quả, không khôi phục.
    var keepComposed = false
    /// Từ nằm trong ngữ cảnh code (sau @ # / . _ hoặc chữ số): không biến đổi.
    var codeLiteral = false

    init(_ c: Config) {
        method = c.method; modernTone = c.modernTone; standaloneW = c.standaloneW; teen = c.teenInitials
    }

    var isEmpty: Bool { raw.isEmpty }
    var isLiteral: Bool { override != nil }
    var rawString: String { String(raw) }
    var shown: String { override ?? render() }
    var hasVowel: Bool { letters.contains(where: \.isVowel) }
    var plainChars: [Character] { letters.map(\.plain) }

    // MARK: - Nhập phím

    /// Trả về false nếu ký tự không thuộc về từ (vd chữ số VNI không áp dụng được) -> ngắt từ.
    mutating func feed(_ ch: Character) -> Bool {
        if ch.isNumber && (method != .vni || isLiteral || isEmpty) { return false }
        if override != nil {
            override!.append(ch); raw.append(ch); owner.append(-2)
            return true
        }
        let saved = self
        raw.append(ch)
        guard applyKey(Character(ch.lowercased()), upper: ch.isUppercase) else {
            self = saved
            return false
        }
        normalizeUO()
        if method == .telex, raw.count >= 3, raw.allSatisfy({ $0 == "w" || $0 == "W" }) {
            override = rawString  // "www": muốn chữ w thật, không phải "wư"
            return true
        }
        if !Syl.isValidPrefix(letters.map(\.base), teen: teen) { enterLiteral() }
        return true
    }

    /// Bắt đầu một từ không biến đổi.
    mutating func startLiteral() {
        override = ""; codeLiteral = true
    }

    /// Gõ lại một chuỗi phím từ đầu; nil nếu có phím không thuộc về từ.
    static func replay(_ keys: [Character], _ c: Config) -> Composer? {
        var comp = Composer(c)
        for k in keys where !comp.feed(k) { return nil }
        return comp
    }

    private mutating func enterLiteral() {
        keepComposed = !hasVowel && !cancelled
        override = (cancelled || !hasVowel) ? render() : rawString
    }

    /// Ép từ hiện tại về một chuỗi cố định (dùng khi khôi phục thủ công).
    mutating func forceLiteral(_ text: String) {
        override = text
        raw = Array(text)
        owner = Array(repeating: -2, count: raw.count)
        cancelled = false; keepComposed = false
    }

    mutating func backspace() {
        if override != nil {
            override!.removeLast()
            if override!.isEmpty { clear() } else { forceLiteral(override!) }
            return
        }
        guard !letters.isEmpty else { clear(); return }
        let idx = letters.count - 1
        letters.removeLast()
        dropKeys { $0 == idx || $0 == -2 }
        if cluster() == nil {
            tone = .none
            dropKeys { $0 == -1 }
        }
        cancelled = false
        if letters.isEmpty { clear() }
    }

    private mutating func clear() {
        letters = []; tone = .none; raw = []; owner = []; override = nil
        cancelled = false; keepComposed = false
    }

    private mutating func dropKeys(_ pred: (Int) -> Bool) {
        var r: [Character] = [], o: [Int] = []
        for (i, own) in owner.enumerated() where !pred(own) { r.append(raw[i]); o.append(own) }
        raw = r; owner = o
    }

    // MARK: - Luật phím

    private enum Outcome { case applied, cancelled, none }

    private mutating func applyKey(_ k: Character, upper: Bool) -> Bool {
        switch method {
        case .telex:
            switch k {
            case "s": return doTone(.sac, k, upper)
            case "f": return doTone(.huyen, k, upper)
            case "r": return doTone(.hoi, k, upper)
            case "x": return doTone(.nga, k, upper)
            case "j": return doTone(.nang, k, upper)
            case "z":
                if tone != .none { tone = .none; killToneKeys(); owner.append(-2); return true }
                appendLetter(k, upper); return true
            case "a", "e", "o":
                return attempt(k, upper, fallbackLetter: true) { $0.doHat(on: [k], k, upper) }
            case "w":
                return attempt(k, upper, fallbackLetter: true) {
                    $0.doW(k, upper, breve: true, horn: true, standalone: $0.standaloneW)
                }
            case "d":
                return attempt(k, upper, fallbackLetter: true) { $0.doBar(k, upper, adjacentOnly: true) }
            default:
                appendLetter(k, upper); return true
            }
        case .vni:
            switch k {
            case "1": return doTone(.sac, k, upper)
            case "2": return doTone(.huyen, k, upper)
            case "3": return doTone(.hoi, k, upper)
            case "4": return doTone(.nga, k, upper)
            case "5": return doTone(.nang, k, upper)
            case "0":
                guard tone != .none else { return false }
                tone = .none; killToneKeys(); owner.append(-2); return true
            case "6": return attempt(k, upper, fallbackLetter: false) { $0.doHat(on: ["a", "e", "o"], k, upper) }
            case "7":
                return attempt(k, upper, fallbackLetter: false) {
                    $0.doW(k, upper, breve: false, horn: true, standalone: false)
                }
            case "8":
                return attempt(k, upper, fallbackLetter: false) {
                    $0.doW(k, upper, breve: true, horn: false, standalone: false)
                }
            case "9": return attempt(k, upper, fallbackLetter: false) { $0.doBar(k, upper, adjacentOnly: false) }
            default:
                if k.isNumber { return false }
                appendLetter(k, upper); return true
            }
        }
    }

    /// Thử một phép biến đổi; chỉ nhận nếu kết quả vẫn có thể là tiếng Việt, không thì coi là chữ thường.
    private mutating func attempt(
        _ k: Character, _ upper: Bool, fallbackLetter: Bool, _ op: (inout Composer) -> Outcome
    ) -> Bool {
        var trial = self
        switch op(&trial) {
        case .cancelled:
            self = trial; return true
        case .applied:
            trial.normalizeUO()
            if Syl.isValidPrefix(trial.letters.map(\.base), teen: teen) { self = trial; return true }
        case .none: break
        }
        guard fallbackLetter else { return false }
        appendLetter(k, upper)
        return true
    }

    private mutating func appendLetter(_ k: Character, _ upper: Bool) {
        letters.append(Letter(base: k, upper: upper))
        owner.append(letters.count - 1)
    }

    private mutating func killToneKeys() {
        for i in owner.indices where owner[i] == -1 { owner[i] = -2 }
    }

    private mutating func doTone(_ t: Tone, _ k: Character, _ upper: Bool) -> Bool {
        let isLetterKey = method == .telex
        guard let c = cluster() else {
            if isLetterKey { appendLetter(k, upper) }
            return isLetterKey
        }
        if tone == t {  // gõ lặp -> huỷ thanh, trả lại chữ
            tone = .none; killToneKeys(); cancelled = true
            appendLetter(k, upper)
            return true
        }
        let fin = String(letters[c.upperBound...].map(\.base))
        if ["c", "ch", "p", "t"].contains(fin) && t != .sac && t != .nang {
            if isLetterKey { appendLetter(k, upper) }
            return isLetterKey
        }
        tone = t
        owner.append(-1)
        return true
    }

    private mutating func doHat(on bases: Set<Character>, _ k: Character, _ upper: Bool) -> Outcome {
        guard let c = cluster(),
            let i = c.reversed().first(where: { bases.contains(letters[$0].base) })
        else { return .none }
        if letters[i].mark == .hat {
            letters[i].mark = .none; cancelled = true
            appendLetter(k, upper)
            return .cancelled
        }
        letters[i].mark = .hat  // cũng cho đổi ă->â, ơ->ô để sửa gõ nhầm
        if i > c.lowerBound, letters[i - 1].base == "u", letters[i - 1].mark == .horn {
            letters[i - 1].mark = .none  // ươ -> uô, ưa -> uâ
        }
        owner.append(i)
        return .applied
    }

    private mutating func doBar(_ k: Character, _ upper: Bool, adjacentOnly: Bool) -> Outcome {
        guard let first = letters.first, first.base == "d" else { return .none }
        if first.mark == .bar {
            guard letters.count == 1 else { return .none }
            letters[0].mark = .none; cancelled = true
            appendLetter(k, upper)
            return .cancelled
        }
        if adjacentOnly && letters.count != 1 { return .none }
        letters[0].mark = .bar
        owner.append(0)
        return .applied
    }

    private mutating func cancelMarks(_ idx: [Int], _ k: Character, _ upper: Bool) -> Outcome {
        for i in idx { letters[i].mark = .none }
        cancelled = true
        appendLetter(k, upper)
        return .cancelled
    }

    private mutating func doW(_ k: Character, _ upper: Bool, breve: Bool, horn: Bool, standalone: Bool) -> Outcome {
        if let c = cluster() {
            let idx = Array(c)
            func find(_ b: Character) -> Int? { idx.last(where: { letters[$0].base == b }) }

            // u + o  ->  ươ / uơ
            if horn, let o = find("o"), o > c.lowerBound, letters[o - 1].base == "u" {
                let u = o - 1
                let oIsLast = o == letters.count - 1
                if letters[o].mark == .horn && (letters[u].mark == .horn || oIsLast) {
                    return cancelMarks([u, o], k, upper)
                }
                letters[o].mark = .horn
                if !oIsLast { letters[u].mark = .horn }
                owner.append(o)
                return .applied
            }
            if let a = find("a") {
                let u = (a > c.lowerBound && letters[a - 1].base == "u") ? a - 1 : nil
                if horn, let u, letters[u].mark == .horn { return cancelMarks([u], k, upper) }
                if horn, let u, letters[a].mark == .none {  // ua + w -> ưa
                    letters[u].mark = .horn; owner.append(u); return .applied
                }
                if breve {
                    if letters[a].mark == .breve { return cancelMarks([a], k, upper) }
                    letters[a].mark = .breve; owner.append(a); return .applied
                }
            }
            if horn, let o = find("o") {
                if letters[o].mark == .horn { return cancelMarks([o], k, upper) }
                letters[o].mark = .horn; owner.append(o); return .applied
            }
            if horn {
                if let u = idx.first(where: { letters[$0].base == "u" && letters[$0].mark == .none }) {
                    letters[u].mark = .horn; owner.append(u); return .applied
                }
                if let u = find("u") {  // đã là ư -> huỷ
                    if letters[u].fromW && u == letters.count - 1 {
                        letters[u] = Letter(base: k, upper: letters[u].upper)
                        cancelled = true
                        owner.append(u)
                        return .cancelled
                    }
                    return cancelMarks([u], k, upper)
                }
            }
        }
        guard standalone, !cancelled else { return .none }
        letters.append(Letter(base: "u", mark: .horn, upper: upper, fromW: true))
        owner.append(letters.count - 1)
        return .applied
    }

    /// "ưo"/"uơ" + chữ theo sau -> "ươ" (dduwocj, muowif, thuowng...). "thuở", "quơ" giữ nguyên.
    private mutating func normalizeUO() {
        guard let c = cluster() else { return }
        for i in c.dropLast() where letters[i].base == "u" && letters[i + 1].base == "o" {
            let u = letters[i].mark, o = letters[i + 1].mark
            guard i + 2 < letters.count else { continue }
            if (u == .horn && o == .none) || (u == .none && o == .horn) {
                letters[i].mark = .horn; letters[i + 1].mark = .horn
            }
        }
    }

    // MARK: - Hiển thị

    /// Cụm nguyên âm mang thanh (đã loại "u" của "qu" và "i" của "gi").
    func cluster() -> Range<Int>? {
        guard var s = letters.firstIndex(where: \.isVowel) else { return nil }
        var e = s
        while e < letters.count && letters[e].isVowel { e += 1 }
        if e - s >= 2, s == 1, letters[s].mark == .none {
            if letters[0].base == "q" && letters[s].base == "u" { s += 1 }
            else if letters[0].base == "g" && letters[s].base == "i" { s += 1 }
        }
        return s..<e
    }

    private func tonePosition() -> Int? {
        guard let c = cluster() else { return nil }
        let idx = Array(c)
        if let i = idx.last(where: { letters[$0].base == "o" && letters[$0].mark == .horn }) { return i }
        if let i = idx.last(where: { letters[$0].mark != .none }) { return i }
        switch idx.count {
        case 1: return idx[0]
        case 2:
            if c.upperBound < letters.count { return idx[1] }  // có âm cuối: toán, quyết
            let pair = String(idx.map { letters[$0].base })
            if modernTone && ["oa", "oe", "uy"].contains(pair) { return idx[1] }  // hoà, thuỷ
            return idx[0]
        default: return idx[1]
        }
    }

    func render() -> String {
        let tp = tone == .none ? nil : tonePosition()
        var s = ""
        for (i, l) in letters.enumerated() { s += l.glyph(i == tp ? tone : .none) }
        return s
    }
}
