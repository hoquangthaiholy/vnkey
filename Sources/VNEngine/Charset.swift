import Foundation

/// Bảng mã tiếng Việt. Văn bản bảng mã cũ (TCVN3, VNI Windows) tới clipboard dưới dạng chuỗi Unicode
/// mà mỗi byte được đọc theo Latin-1 ("TiÕng ViÖt", "Tieáng Vieät"), nên mọi phép chuyển ở đây là
/// chuỗi → chuỗi, đi qua dạng trung gian là Unicode dựng sẵn.
public enum Charset: String, CaseIterable, Sendable {
    /// Unicode dựng sẵn (NFC): mỗi chữ một ký tự.
    case unicode
    /// Unicode tổ hợp kiểu Việt Nam: chữ có mũ/móc dựng sẵn + dấu thanh rời ("ấ" = "â" + U+0301).
    case decomposed
    /// TCVN3 (ABC), phông .VnTime. Không có chữ hoa mang thanh: xem `losesCase`.
    case tcvn3
    /// VNI Windows, phông VNI-Times: chữ gốc + ký tự dấu.
    case vniWindows = "vni"
    /// VIQR: dấu viết bằng ký tự ASCII ("Vie^.t").
    case viqr

    public static func convert(_ s: String, from: Charset, to: Charset) -> String {
        from == to ? s : encode(decode(s, from), to)
    }

    /// Bỏ hết dấu: "Đường Trần Hưng Đạo" → "Duong Tran Hung Dao". Nhận Unicode dựng sẵn hoặc tổ hợp.
    public static func stripMarks(_ s: String) -> String {
        var out = ""
        for ch in s.precomposedStringWithCanonicalMapping {
            guard let i = T.info[ch] else { out.append(ch); continue }
            let base = String(i.plain == "đ" ? "d" : Syl.unmark(i.plain))
            out += i.upper ? base.uppercased() : base
        }
        return out.folding(options: .diacriticInsensitive, locale: nil)
    }

    /// Chuyển sang `to` có làm mất phân biệt hoa/thường không (TCVN3 không có "Á", "Ề"… viết hoa).
    public static func losesCase(_ s: String, to: Charset) -> Bool {
        to == .tcvn3 && s.precomposedStringWithCanonicalMapping.contains { T.info[$0].map { $0.upper && $0.tone != .none } ?? false }
    }

    /// Đoán bảng mã cũ của một đoạn văn bản. `nil` = không phải (hoặc không chắc), cứ coi là Unicode.
    /// Cách đoán: giải mã thử, đếm số từ đổi thành âm tiết tiếng Việt hợp lệ so với số từ đổi thành vô nghĩa.
    public static func detect(_ s: String) -> Charset? {
        var legacy = false
        for u in s.unicodeScalars {
            let v = u.value
            // Đã có chữ riêng của tiếng Việt trong Unicode (ă đ ơ ư, khối Latin Extended Additional, dấu rời).
            if (0x1EA0...0x1EF9).contains(v) || (0x300...0x323).contains(v) || T.vietnameseOnly.contains(v) { return nil }
            if (0xA1...0xFF).contains(v) { legacy = true }
        }
        let tokens = s.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return nil }

        func score(_ cs: Charset) -> (good: Int, bad: Int, longest: Int) {
            var good = 0, bad = 0, longest = 0
            for tok in tokens {
                let dec = decode(String(tok), cs)
                if dec == tok { continue }
                let words = dec.split(whereSeparator: { !$0.isLetter })
                if !words.isEmpty, words.allSatisfy({ isSyllable($0) }) {
                    good += 1; longest = max(longest, dec.count)
                } else {
                    bad += 1
                }
            }
            return (good, bad, longest)
        }
        func accepted(_ r: (good: Int, bad: Int, longest: Int)) -> Bool {
            if r.good >= 2 { return r.good >= 4 * r.bad }
            // Một từ lẻ: chỉ nhận khi cả đoạn là đúng từ đó và đủ dài ("où" tiếng Pháp cũng giải ra "ó").
            return r.good == 1 && r.bad == 0 && tokens.count == 1 && r.longest >= 3
        }

        if legacy {
            let a = score(.tcvn3), b = score(.vniWindows)
            let best: (Charset, (good: Int, bad: Int, longest: Int)) = a.good - a.bad >= b.good - b.bad ? (.tcvn3, a) : (.vniWindows, b)
            return accepted(best.1) ? best.0 : nil
        }
        // VIQR toàn ASCII nên dễ nhầm với văn bản thường: đòi có dấu mũ/móc/đ và không từ nào giải ra vô nghĩa.
        guard s.contains("^") || s.contains("+") || s.contains("(") || s.lowercased().contains("dd") else { return nil }
        let r = score(.viqr)
        return r.good >= 2 && r.bad == 0 ? .viqr : nil
    }

    /// Khoá chuẩn của một âm tiết tiếng Việt đúng chính tả: chữ thường đã bỏ thanh + số của thanh ("hoà" và "hòa"
    /// đều là "hoa2"). nil nếu không phải một âm tiết hợp lệ. Dùng để tra bảng tần suất mà không phụ thuộc cách
    /// đặt dấu thanh.
    public static func syllableKey(_ word: String) -> String? {
        var plain: [Character] = []
        var tone = Tone.none
        for ch in word.precomposedStringWithCanonicalMapping {
            if let i = T.info[ch] {
                if i.tone != .none {
                    if tone != .none { return nil }
                    tone = i.tone
                }
                plain.append(i.plain)
            } else {
                guard ch.isASCII, ch.isLetter, let l = ch.lowercased().first else { return nil }
                plain.append(l)
            }
        }
        guard !plain.isEmpty, Syl.isValid(plain, tone: tone, teen: false) else { return nil }
        return String(plain) + String(tone.rawValue)
    }

    // MARK: - Giải mã về Unicode dựng sẵn

    static func decode(_ s: String, _ cs: Charset) -> String {
        switch cs {
        case .unicode, .decomposed:
            return s.precomposedStringWithCanonicalMapping
        case .tcvn3:
            return String(s.map { T.tcvnDecode[$0] ?? $0 })
        case .vniWindows:
            let c = Array(s)
            var out = "", i = 0
            while i < c.count {
                if i + 1 < c.count, let ch = T.vniPairs[String([c[i], c[i + 1]])] {
                    out.append(ch); i += 2
                } else {
                    out.append(T.vniSingles[c[i]] ?? c[i]); i += 1
                }
            }
            return out
        case .viqr:
            return decodeVIQR(Array(s))
        }
    }

    private static func decodeVIQR(_ c: [Character]) -> String {
        var out = "", i = 0
        var toned = false  // từ đang đọc đã có thanh: ký tự dấu kế tiếp là dấu câu
        while i < c.count {
            let ch = c[i]
            if ch == "\\", i + 1 < c.count { out.append(c[i + 1]); i += 2; continue }
            if ch.isWhitespace { toned = false }
            if ch == "d" || ch == "D", i + 1 < c.count, c[i + 1] == "d" || c[i + 1] == "D" {
                out.append(ch == "D" ? "Đ" : "đ"); i += 2; continue
            }
            let low = Character(ch.lowercased())
            guard "aeiouy".contains(low) else { out.append(ch); i += 1; continue }
            var plain = low, j = i + 1
            if j < c.count {
                switch (low, c[j]) {
                case ("a", "^"): plain = "â"; j += 1
                case ("e", "^"): plain = "ê"; j += 1
                case ("o", "^"): plain = "ô"; j += 1
                case ("a", "("): plain = "ă"; j += 1
                case ("o", "+"): plain = "ơ"; j += 1
                case ("u", "+"): plain = "ư"; j += 1
                default: break
                }
            }
            var tone = 0
            if j < c.count, !toned, let t = T.viqrTones.firstIndex(of: c[j]), t > 0, !endsSentence(c, j) {
                tone = t; toned = true; j += 1
            }
            out.append(Letter.glyphs[plain]![tone + (ch.isUppercase ? 6 : 0)])
            i = j
        }
        return out
    }

    /// Dấu "." hoặc "?" ở cuối câu là dấu câu chứ không phải thanh: đứng cuối đoạn, hoặc sau nó là
    /// khoảng trắng rồi xuống dòng / chữ hoa. ("me. to^i" vẫn là "mẹ tôi".)
    private static func endsSentence(_ c: [Character], _ j: Int) -> Bool {
        guard c[j] == "." || c[j] == "?" else { return false }
        var k = j + 1
        if k == c.count { return true }
        guard c[k].isWhitespace else { return false }
        while k < c.count, c[k].isWhitespace {
            if c[k].isNewline { return true }
            k += 1
        }
        return k == c.count || c[k].isUppercase
    }

    // MARK: - Mã hoá từ Unicode dựng sẵn

    static func encode(_ s: String, _ cs: Charset) -> String {
        if cs == .unicode { return s }
        guard let table = T.encode[cs] else { return s }
        var out = ""
        for ch in s {
            if let m = table[ch] { out += m } else { out.append(ch) }
        }
        return out
    }

    private static func isSyllable(_ w: Substring) -> Bool {
        var plain: [Character] = []
        var tone = Tone.none
        for ch in w {
            if let i = T.info[ch] {
                if i.tone != .none {
                    if tone != .none { return false }
                    tone = i.tone
                }
                plain.append(i.plain)
            } else {
                guard ch.isASCII, ch.isLetter, let l = ch.lowercased().first else { return false }
                plain.append(l)
            }
        }
        return !plain.isEmpty && Syl.isValid(plain, tone: tone, teen: false)
    }
}

/// Các bảng tra, sinh một lần từ `Letter.glyphs`.
private enum T {
    typealias Info = (plain: Character, tone: Tone, upper: Bool)

    static let viqrTones: [Character] = ["\0", "'", "`", "?", "~", "."]
    static let vietnameseOnly: Set<UInt32> = [0x102, 0x103, 0x110, 0x111, 0x128, 0x129, 0x168, 0x169, 0x1A0, 0x1A1, 0x1AF, 0x1B0]

    /// TCVN3: mã chữ thường theo thứ tự thanh của `Tone` (không, sắc, huyền, hỏi, ngã, nặng).
    private static let tcvnRows: [Character: [UInt32]] = [
        "a": [0x61, 0xB8, 0xB5, 0xB6, 0xB7, 0xB9],
        "ă": [0xA8, 0xBE, 0xBB, 0xBC, 0xBD, 0xC6],
        "â": [0xA9, 0xCA, 0xC7, 0xC8, 0xC9, 0xCB],
        "e": [0x65, 0xD0, 0xCC, 0xCE, 0xCF, 0xD1],
        "ê": [0xAA, 0xD5, 0xD2, 0xD3, 0xD4, 0xD6],
        "i": [0x69, 0xDD, 0xD7, 0xD8, 0xDC, 0xDE],
        "o": [0x6F, 0xE3, 0xDF, 0xE1, 0xE2, 0xE4],
        "ô": [0xAB, 0xE8, 0xE5, 0xE6, 0xE7, 0xE9],
        "ơ": [0xAC, 0xED, 0xEA, 0xEB, 0xEC, 0xEE],
        "u": [0x75, 0xF3, 0xEF, 0xF1, 0xF2, 0xF4],
        "ư": [0xAD, 0xF8, 0xF5, 0xF6, 0xF7, 0xF9],
        "y": [0x79, 0xFD, 0xFA, 0xFB, 0xFC, 0xFE],
    ]
    /// TCVN3 chỉ có bảy chữ hoa riêng, đều không mang thanh.
    private static let tcvnUpper: [Character: UInt32] = ["ă": 0xA1, "â": 0xA2, "ê": 0xA3, "ô": 0xA4, "ơ": 0xA5, "ư": 0xA6]

    private static func str(_ codes: [UInt32]) -> String {
        var s = String.UnicodeScalarView()
        for c in codes { if let u = Unicode.Scalar(c) { s.append(u) } }
        return String(s)
    }

    private static func vni(_ p: Character, _ t: Int) -> String {
        let plain: [UInt32] = [0, 0xF9, 0xF8, 0xFB, 0xF5, 0xEF]       // ù ø û õ ï
        let hat: [UInt32] = [0xE2, 0xE1, 0xE0, 0xE5, 0xE3, 0xE4]      // â á à å ã ä
        let breve: [UInt32] = [0xEA, 0xE9, 0xE8, 0xFA, 0xFC, 0xEB]    // ê é è ú ü ë
        let i: [UInt32] = [0x69, 0xED, 0xEC, 0xE6, 0xF3, 0xF2]        // i í ì æ ó ò
        func with(_ base: UInt32) -> String { str(t == 0 ? [base] : [base, plain[t]]) }
        switch p {
        case "i": return str([i[t]])
        case "y" where t == 5: return str([0xEE])                     // î
        case "ă": return str([0x61, breve[t]])
        case "â": return str([0x61, hat[t]])
        case "ê": return str([0x65, hat[t]])
        case "ô": return str([0x6F, hat[t]])
        case "ơ": return with(0xF4)                                   // ô
        case "ư": return with(0xF6)                                   // ö
        default: return with(p.unicodeScalars.first!.value)
        }
    }

    private static func viqr(_ p: Character, _ t: Int) -> String {
        var s: String
        switch p {
        case "ă": s = "a("
        case "â": s = "a^"
        case "ê": s = "e^"
        case "ô": s = "o^"
        case "ơ": s = "o+"
        case "ư": s = "u+"
        default: s = String(p)
        }
        if t > 0 { s.append(viqrTones[t]) }
        return s
    }

    private static let built: (
        info: [Character: Info], encode: [Charset: [Character: String]],
        tcvnDecode: [Character: Character], vniPairs: [String: Character], vniSingles: [Character: Character]
    ) = {
        var info: [Character: Info] = ["đ": ("đ", .none, false), "Đ": ("đ", .none, true)]
        var dec: [Character: String] = [:], tcvn: [Character: String] = [:]
        var vniE: [Character: String] = [:], viqrE: [Character: String] = [:]
        var tcvnD: [Character: Character] = [:], pairs: [String: Character] = [:], singles: [Character: Character] = [:]

        func addVNI(_ legacy: String, _ ch: Character) {
            if legacy.count == 1 { singles[legacy.first!] = ch } else { pairs[legacy] = ch }
        }
        for (legacy, lower, upper) in [(str([0xF1]), Character("đ"), Character("Đ"))] {
            vniE[lower] = legacy; vniE[upper] = legacy.uppercased()
            addVNI(legacy, lower); addVNI(legacy.uppercased(), upper)
        }
        tcvn["đ"] = str([0xAE]); tcvn["Đ"] = str([0xA7])
        tcvnD[Character(str([0xAE]))] = "đ"; tcvnD[Character(str([0xA7]))] = "Đ"
        viqrE["đ"] = "dd"; viqrE["Đ"] = "DD"

        let tones = ["", "\u{301}", "\u{300}", "\u{309}", "\u{303}", "\u{323}"]
        for p in "aăâeêioôơuưy" {
            let row = Letter.glyphs[p]!
            for t in 0...5 {
                let lower = row[t], upper = row[t + 6]
                info[lower] = (p, Tone(rawValue: t)!, false)
                info[upper] = (p, Tone(rawValue: t)!, true)

                if t > 0 {
                    dec[lower] = String(row[0]) + tones[t]
                    dec[upper] = String(row[6]) + tones[t]
                }

                let code = str([tcvnRows[p]![t]])
                if code != String(lower) {
                    tcvn[lower] = code
                    tcvnD[Character(code)] = lower
                }
                if t == 0, let u = tcvnUpper[p] {
                    tcvn[upper] = str([u]); tcvnD[Character(str([u]))] = upper
                } else if t > 0 {
                    // Không có chữ hoa mang thanh: dùng mã chữ thường. Phải ghi cả khi mã trùng chính chữ
                    // thường ("ý" = 0xFD), nếu không "Ý" (0xDD) giữ nguyên rồi bị đọc lại thành "í".
                    tcvn[upper] = code
                }

                let v = vni(p, t)
                if v != String(lower) {
                    vniE[lower] = v; vniE[upper] = v.uppercased()
                    addVNI(v, lower); addVNI(v.uppercased(), upper)
                    // "Aù": chữ gốc hoa, ký tự dấu thường.
                    if v.count == 2 { pairs[v.prefix(1).uppercased() + v.dropFirst()] = upper }
                }

                let q = viqr(p, t)
                if q != String(lower) {
                    viqrE[lower] = q
                    viqrE[upper] = q.prefix(1).uppercased() + q.dropFirst()
                }
            }
        }
        return (info, [.decomposed: dec, .tcvn3: tcvn, .vniWindows: vniE, .viqr: viqrE], tcvnD, pairs, singles)
    }()

    static var info: [Character: Info] { built.info }
    static var encode: [Charset: [Character: String]] { built.encode }
    static var tcvnDecode: [Character: Character] { built.tcvnDecode }
    static var vniPairs: [String: Character] { built.vniPairs }
    static var vniSingles: [Character: Character] { built.vniSingles }
}
