/// Sinh các từ có thể là ý định của người gõ khi từ đang gõ thiếu dấu ("duọc", "đươc", "duoc" -> "được", "dược"…).
/// Chỉ THÊM dấu: không đổi chữ cái, không bỏ dấu mũ/móc/thanh mà người dùng đã gõ.
enum Predictor {
    private static let stopFinals: Set<String> = ["c", "ch", "p", "t"]
    private static let allTones: [Tone] = [.none, .sac, .huyen, .hoi, .nga, .nang]

    private static func mark(of c: Character) -> Mark {
        switch c {
        case "â", "ê", "ô": return .hat
        case "ă": return .breve
        case "ơ", "ư": return .horn
        default: return .none
        }
    }

    /// Các biến thể hợp lệ về cấu tạo âm tiết, khác với từ đang hiện. Chưa lọc theo từ điển.
    static func candidates(for comp: Composer, teen: Bool) -> [Composer] {
        guard !comp.isLiteral, let cluster = comp.cluster(), comp.letters.allSatisfy({ $0.base.isLetter }) else { return [] }
        let letters = comp.letters
        let bases = String(letters[cluster].map(\.base))
        let typed = letters[cluster].map(\.plain)

        // Các vần cùng chữ cái, giữ nguyên dấu mũ/móc đã gõ.
        var nuclei: [[Character]] = []
        for key in Syl.nuclei.keys where key.count == bases.count && String(key.map(Syl.unmark)) == bases {
            let chars = Array(key)
            if zip(typed, chars).allSatisfy({ t, c in t == Syl.unmark(t) || t == c }) { nuclei.append(chars) }
        }
        if !nuclei.contains(typed) { nuclei.append(typed) }  // kể cả cụm đang có (để chỉ thêm đ hoặc thanh)

        let canBar = letters[0].base == "d" && letters[0].mark == .none
        let final = String(letters[cluster.upperBound...].map(\.base))
        let tones: [Tone] =
            comp.tone != .none ? [comp.tone] : stopFinals.contains(final) ? [.sac, .nang] : allTones

        var out: [Composer] = []
        for bar in canBar ? [false, true] : [false] {
            for nucleus in nuclei {
                for tone in tones {
                    var c = comp
                    if bar { c.letters[0].mark = .bar }
                    for (i, ch) in zip(cluster, nucleus) { c.letters[i].mark = mark(of: ch) }
                    c.tone = tone
                    guard Syl.isValid(c.plainChars, tone: tone, teen: teen) else { continue }
                    c.keepComposed = true  // Engine.decide() giữ nguyên từ đã đoán
                    c.lateBar = false
                    if c.shown != comp.shown { out.append(c) }
                }
            }
        }
        return out
    }
}
