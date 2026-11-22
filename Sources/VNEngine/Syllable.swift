import Foundation

/// Luật cấu tạo âm tiết tiếng Việt: âm đầu + vần (nguyên âm + âm cuối) + thanh.
/// Dùng để (1) phát hiện sớm từ không thể là tiếng Việt, (2) quyết định khôi phục khi kết thúc từ.
enum Syl {
    static let vowels: Set<Character> = Set("aăâeêioôơuưy")

    static let standardInitials = [
        "", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n", "ng", "ngh",
        "nh", "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x",
    ]
    /// Âm đầu kiểu teen: fải, jờ, zậy, dzô, wá...
    static let teenInitials = ["f", "j", "w", "z", "dz"]

    private static let all = ["c", "ch", "m", "n", "ng", "nh", "p", "t"]
    private static let open = [""]

    /// Nguyên âm (đã có dấu mũ/móc) -> các âm cuối hợp lệ ("" = âm tiết mở).
    static let nuclei: [String: [String]] = [
        "a": open + all,
        "ă": ["c", "m", "n", "ng", "p", "t"],
        "â": ["c", "m", "n", "ng", "p", "t"],
        "e": open + ["c", "m", "n", "ng", "p", "t"],
        "ê": open + ["ch", "m", "n", "nh", "p", "t"],
        "i": open + ["ch", "m", "n", "nh", "p", "t"],
        "o": open + ["c", "m", "n", "ng", "p", "t"],
        "ô": open + ["c", "m", "n", "ng", "p", "t"],
        "ơ": open + ["m", "n", "p", "t"],
        "u": open + ["c", "m", "n", "ng", "p", "t"],
        "ư": open + ["c", "m", "n", "ng", "t"],
        "y": open + ["ch", "n", "nh", "t"],
        // Nguyên âm đôi không nhận âm cuối
        "ai": open, "ao": open, "au": open, "ay": open, "âu": open, "ây": open,
        "eo": open, "êu": open, "ia": open, "iu": open, "oi": open, "ôi": open, "ơi": open,
        "ui": open, "ưa": open, "ưi": open, "ưu": open, "ua": open, "uơ": open,
        // Nguyên âm đôi bắt buộc / có thể có âm cuối
        "iê": ["c", "m", "n", "ng", "p", "t"],
        "yê": ["m", "n", "ng", "t"],
        "uô": ["c", "m", "n", "ng", "t"],
        "ươ": ["c", "m", "n", "ng", "p", "t"],
        "oa": open + all,
        "oă": ["c", "m", "n", "ng", "t"],
        "oe": open + ["n", "t"],
        "oo": ["c", "ng"],
        "uâ": ["n", "ng", "t"],
        "uê": open + ["ch", "n", "nh"],
        "uy": open + ["ch", "n", "nh", "p", "t"],
        "uyê": ["n", "t"],
        // Nguyên âm ba
        "iêu": open, "yêu": open, "oai": open, "oao": open, "oay": open, "oeo": open,
        "uây": open, "uôi": open, "uya": open, "uyu": open, "ươi": open, "ươu": open,
    ]

    static func unmark(_ c: Character) -> Character {
        switch c {
        case "ă", "â": return "a"
        case "ê": return "e"
        case "ô", "ơ": return "o"
        case "ư": return "u"
        case "đ": return "d"
        default: return c
        }
    }

    /// Vần không dấu -> hợp các âm cuối của mọi biến thể có dấu (vd "uo" = uô ∪ ươ ∪ uơ).
    static let unmarkedNuclei: [String: Set<String>] = {
        var out: [String: Set<String>] = [:]
        for (k, v) in nuclei { out[String(k.map(unmark)), default: []].formUnion(v) }
        return out
    }()

    static let unmarkedNucleusPrefixes: Set<String> = {
        var out: Set<String> = [""]
        for k in unmarkedNuclei.keys { for n in 1...k.count { out.insert(String(k.prefix(n))) } }
        return out
    }()

    private static func initialSets(_ list: [String]) -> (exact: Set<String>, prefixes: Set<String>) {
        var exact: Set<String> = [], prefixes: Set<String> = ["", "q"]
        for i in list {
            let u = String(i.map(unmark))
            exact.insert(i); exact.insert(u)
            for n in 0...u.count { prefixes.insert(String(u.prefix(n))) }
        }
        return (exact, prefixes)
    }
    private static let std = initialSets(standardInitials)
    private static let teen = initialSets(standardInitials + teenInitials)

    private static func isV(_ c: Character) -> Bool { vowels.contains(c) }

    private struct Parts { var ini: String; var nuc: String; var fin: String }

    /// Tách âm đầu / nguyên âm / âm cuối. "qu" và "gi" có thể cho 2 cách tách.
    private static func parse(_ s: [Character]) -> [Parts] {
        let n = s.count
        var i = 0
        while i < n && !isV(s[i]) { i += 1 }
        let c0 = String(s[0..<i])
        var starts = [(c0, i)]
        if c0 == "q", i < n, s[i] == "u" {
            starts = [("qu", i + 1)]
        } else if c0 == "g", i + 1 < n, s[i] == "i", isV(s[i + 1]) {
            starts.append(("gi", i + 1))
        }
        var out: [Parts] = []
        for (ini, st) in starts {
            var e = st
            while e < n && isV(s[e]) { e += 1 }
            let fin = String(s[e...])
            if fin.contains(where: isV) { continue }
            out.append(Parts(ini: ini, nuc: String(s[st..<e]), fin: fin))
        }
        return out
    }

    /// Âm tiết hoàn chỉnh, đúng chính tả (chữ thường, có dấu mũ/móc, thanh truyền riêng).
    /// `ignoreToneRule`: bỏ qua luật "âm cuối c/ch/p/t phải có thanh sắc hoặc nặng" — dùng để nhận ra từ
    /// đúng cấu trúc nhưng người gõ chưa (hoặc quên) bỏ dấu thanh, vd "đươc".
    static func isValid(_ s: [Character], tone: Tone, teen allowTeen: Bool, ignoreToneRule: Bool = false) -> Bool {
        let inis = allowTeen ? teen.exact : std.exact
        for p in parse(s) where inis.contains(p.ini) {
            var finals = nuclei[p.nuc] ?? []
            if p.ini == "qu" {
                if p.nuc.isEmpty { continue }
                finals += nuclei["u" + p.nuc] ?? []
            }
            guard finals.contains(p.fin) else { continue }
            // Âm cuối c/ch/p/t chỉ đi với thanh sắc hoặc nặng.
            if !ignoreToneRule, ["c", "ch", "p", "t"].contains(p.fin), tone != .sac, tone != .nang { continue }
            return true
        }
        return false
    }

    /// Chuỗi (đã bỏ dấu) còn có thể phát triển thành một âm tiết tiếng Việt hay không.
    static func isValidPrefix(_ s: [Character], teen allowTeen: Bool) -> Bool {
        let sets = allowTeen ? teen : std
        if !s.contains(where: isV) { return sets.prefixes.contains(String(s)) }
        for p in parse(s) where sets.exact.contains(p.ini) {
            let nucs = p.ini == "qu" ? [p.nuc, "u" + p.nuc] : [p.nuc]
            for nuc in nucs {
                if p.fin.isEmpty {
                    if unmarkedNucleusPrefixes.contains(nuc) { return true }
                } else if let finals = unmarkedNuclei[nuc], finals.contains(where: { $0.hasPrefix(p.fin) }) {
                    return true
                }
            }
        }
        return false
    }
}
