import Testing

@testable import VNEngine

/// Gõ tự do: các phím dấu (thanh, mũ/móc, chữ d thứ hai) có thể đến ở bất kỳ lúc nào sau chữ cái mà
/// chúng bổ nghĩa, còn các chữ cái nền giữ nguyên thứ tự. "dduwowcj", "duojwcd", "duodwc" đều là "được".
struct FreeOrderWord: CustomStringConvertible, Sendable {
    let want: String
    /// Các chữ cái nền theo thứ tự.
    let base: String
    /// Phím dấu và số chữ cái nền tối thiểu phải gõ trước nó.
    let marks: [(key: Character, after: Int)]
    var description: String { want }

    init(_ want: String, _ base: String, _ marks: [(Character, Int)]) {
        self.want = want; self.base = base; self.marks = marks.map { (key: $0.0, after: $0.1) }
    }

    /// Mọi cách xen phím dấu vào chuỗi chữ cái nền thoả điều kiện "sau chữ nó bổ nghĩa".
    var orders: [String] {
        var out: Set<String> = []
        let letters = Array(base)
        func go(_ typed: String, _ nextBase: Int, _ left: [Int]) {
            if nextBase == letters.count && left.isEmpty { out.insert(typed); return }
            if nextBase < letters.count { go(typed + String(letters[nextBase]), nextBase + 1, left) }
            for (i, m) in left.enumerated() where marks[m].after <= nextBase {
                var rest = left
                rest.remove(at: i)
                go(typed + String(marks[m].key), nextBase, rest)
            }
        }
        go("", 0, Array(marks.indices))
        return out.sorted()
    }
}

@Suite struct FreeOrder {
    /// (từ, chữ cái nền, [(phím dấu, gõ sau chữ nền thứ mấy)]).
    /// Phím thanh: sau nguyên âm đầu của vần. Phím w: sau chữ nó móc. Chữ lặp (aa, ee, oo, dd): sau chữ gốc.
    static let words: [FreeOrderWord] = [
        .init("được", "duoc", [("d", 1), ("w", 3), ("j", 2)]),
        .init("đường", "duong", [("d", 1), ("w", 3), ("f", 2)]),
        .init("người", "nguoi", [("w", 4), ("f", 3)]),
        .init("nước", "nuoc", [("w", 3), ("s", 2)]),
        .init("mười", "muoi", [("w", 3), ("f", 2)]),
        .init("rượu", "ruou", [("w", 3), ("j", 2)]),
        .init("tiếng", "tieng", [("e", 3), ("s", 2)]),
        .init("việt", "viet", [("e", 3), ("j", 2)]),
        .init("điện", "dien", [("d", 1), ("e", 3), ("j", 2)]),
        .init("không", "khong", [("o", 3)]),
        .init("đã", "da", [("d", 1), ("x", 2)]),
        .init("đặt", "dat", [("d", 1), ("w", 2), ("j", 2)]),
        .init("đấy", "day", [("d", 1), ("a", 2), ("s", 2)]),
        .init("quyết", "quyet", [("e", 4), ("s", 3)]),
        .init("giữa", "giua", [("w", 3), ("x", 3)]),
        .init("hoặc", "hoac", [("w", 3), ("j", 2)]),
        .init("cũng", "cung", [("x", 2)]),
        .init("những", "nhung", [("w", 3), ("x", 3)]),
        .init("trường", "truong", [("w", 4), ("f", 3)]),
        .init("thuở", "thuo", [("w", 4), ("r", 3)]),
        .init("ngoài", "ngoai", [("f", 3)]),
        .init("mất", "mat", [("a", 2), ("s", 2)]),
        .init("Đồng", "Dong", [("d", 1), ("o", 2), ("f", 2)]),
    ]

    /// Chữ d gõ muộn cũng thành đ ("duojwcd", "duodwc"), nhưng không được biến từ tiếng Anh có hai chữ d
    /// thành tiếng Việt: "did" không phải "đi", "dad" không phải "đa". Muốn "đi" thì gõ "ddi".
    @Test(arguments: [
        ("duojwcd ", "được "), ("duodwcj ", "được "), ("duocdwj ", "được "), ("dungd ", "đung "),
        ("duodwc ", "đươc "),  // quên dấu thanh: giữ chữ đã có dấu để bỏ dấu tiếp, không trả về phím gốc
        ("duodwc <j", "được"), ("data ", "data "),
        ("did ", "did "), ("dad ", "dad "), ("deed ", "deed "), ("dud ", "dud "), ("died ", "died "),
        ("ddi ", "đi "), ("dda ", "đa "), ("ddee ", "đê "),
        ("dided ", "dided "), ("add ", "add "), ("odd ", "odd "), ("ddd", "dd"),
        ("dadx<", "đ"), ("did~", "did"),
    ])
    func lateD(keys: String, want: String) { #expect(run(keys) == want) }

    /// Có từ điển: từ tiếng Anh bất kỳ có chữ d muộn cũng được trả lại, không chỉ danh sách dựng sẵn.
    @Test(arguments: [("dido ", "dido "), ("duojwcd ", "được "), ("dadx ", "đã ")])
    func lateDWithLexicon(keys: String, want: String) { #expect(run(keys, lexicon: LateDLexicon.shared) == want) }

    @Test(arguments: words) func everyOrder(word: FreeOrderWord) {
        let orders = word.orders
        #expect(orders.count > 0)
        var failures: [String] = []
        for keys in orders {
            let got = run(keys + " ", lexicon: FakeLexicon.shared)
            if got != word.want + " " { failures.append("\(keys) -> \(got)") }
        }
        #expect(failures.isEmpty, "\(failures.count)/\(orders.count) thứ tự gõ sai: \(failures.prefix(8).joined(separator: ", "))")
    }
}

final class LateDLexicon: Lexicon {
    static let shared = LateDLexicon()
    func isEnglish(_ w: String) -> Bool { ["dido", "did", "dad"].contains(w) }
    func isVietnamese(_ w: String) -> Bool { ["được", "đã", "đi", "đa", "đio"].contains(w) }
}
