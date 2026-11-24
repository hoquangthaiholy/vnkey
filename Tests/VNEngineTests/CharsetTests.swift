import Testing

@testable import VNEngine

/// Văn bản bảng mã cũ viết bằng mã thoát để tệp test không phụ thuộc cách trình soạn thảo lưu ký tự Latin-1.
@Suite struct Charsets {
    static let all: [Character] = "aăâeêioôơuưy".flatMap { Letter.glyphs[$0]! } + ["đ", "Đ"]

    @Test(arguments: [
        ("Ti\u{D5}ng Vi\u{D6}t", "Tiếng Việt"),
        ("\u{AE}\u{AD}\u{EE}c", "được"),
        ("C\u{E9}ng ho\u{B5} x\u{B7} h\u{E9}i ch\u{F1} ngh\u{DC}a Vi\u{D6}t Nam", "Cộng hoà xã hội chủ nghĩa Việt Nam"),
        ("\u{A7}\u{B9}i h\u{E4}c, n\u{A8}m 2024!", "Đại học, năm 2024!"),
    ])
    func tcvn3(legacy: String, unicode: String) {
        #expect(Charset.convert(legacy, from: .tcvn3, to: .unicode) == unicode)
        #expect(Charset.convert(unicode, from: .unicode, to: .tcvn3) == legacy)
    }

    @Test(arguments: [
        ("Tie\u{E1}ng Vie\u{E4}t", "Tiếng Việt"),
        ("\u{F1}\u{F6}\u{F4}\u{EF}c", "được"),
        ("ng\u{F6}\u{F4}\u{F8}i", "người"),
        ("\u{D1}a\u{F8} Na\u{FC}ng", "Đà Nẵng"),
        ("\u{D1}\u{D6}\u{D4}\u{D8}NG", "ĐƯỜNG"),
        ("ch\u{F2} ngh\u{F3} k\u{F3} l\u{EE}", "chị nghĩ kĩ lỵ"),
        ("muo\u{E1}n thu\u{F9} qua\u{FB}", "muốn thú quả"),
    ])
    func vniWindows(legacy: String, unicode: String) {
        #expect(Charset.convert(legacy, from: .vniWindows, to: .unicode) == unicode)
        #expect(Charset.convert(unicode, from: .unicode, to: .vniWindows) == legacy)
    }

    @Test func vniChuHoaDauThuong() {
        #expect(Charset.convert("A\u{F9}nh", from: .vniWindows, to: .unicode) == "Ánh")
    }

    @Test(arguments: [
        ("Vie^.t Nam", "Việt Nam"),
        ("ddu+o+.c", "được"),
        ("DDa` Na(~ng", "Đà Nẵng"),
        ("me. to^i", "mẹ tôi"),
        ("ca? nha`", "cả nhà"),
    ])
    func viqr(legacy: String, unicode: String) {
        #expect(Charset.convert(legacy, from: .viqr, to: .unicode) == unicode)
        #expect(Charset.convert(unicode, from: .unicode, to: .viqr) == legacy)
    }

    /// Dấu chấm, dấu hỏi cuối câu không bị đọc thành thanh.
    @Test(arguments: [
        ("to^i ddi ho.c.", "tôi đi học."),
        ("anh ddi dda^u?", "anh đi đâu?"),
        ("To^i ddi. Anh o+? la.i.", "Tôi đi. Anh ở lại."),
        ("ve^` nha`. Ngu? ddi", "về nhà. Ngủ đi"),
        ("ve^` nha`. Ngu?", "về nhà. Ngu?"),
    ])
    func viqrDauCau(legacy: String, unicode: String) {
        #expect(Charset.convert(legacy, from: .viqr, to: .unicode) == unicode)
    }

    @Test func toHop() {
        let s = Charset.convert("Tiếng Việt", from: .unicode, to: .decomposed)
        #expect(Array(s.unicodeScalars).map(\.value) == [0x54, 0x69, 0xEA, 0x301, 0x6E, 0x67, 0x20, 0x56, 0x69, 0xEA, 0x323, 0x74])
        #expect(Array(Charset.convert(s, from: .decomposed, to: .unicode).unicodeScalars).count == 10)
    }

    /// Mọi chữ có dấu đi rồi về phải y nguyên (đặt giữa từ để VIQR không coi dấu là dấu câu).
    @Test(arguments: [Charset.decomposed, .vniWindows, .viqr])
    func diVe(cs: Charset) {
        for ch in Charsets.all {
            let word = "x\(ch)n"
            let there = Charset.convert(word, from: .unicode, to: cs)
            #expect(Array(Charset.convert(there, from: cs, to: .unicode).unicodeScalars) == Array(word.unicodeScalars), "\(ch) qua \(cs)")
        }
    }

    /// TCVN3 không có chữ hoa mang thanh: chữ đó về dạng thường, còn lại y nguyên.
    @Test func diVeTCVN3() {
        for ch in Charsets.all {
            let back = Charset.convert(Charset.convert(String(ch), from: .unicode, to: .tcvn3), from: .tcvn3, to: .unicode)
            let lossy = Charset.losesCase(String(ch), to: .tcvn3)
            #expect(back == (lossy ? String(ch).lowercased() : String(ch)), "\(ch)")
        }
        #expect(Charset.losesCase("VIỆT", to: .tcvn3))
        #expect(!Charset.losesCase("Việt Đức Ư", to: .tcvn3))
    }

    @Test(arguments: [
        ("Ti\u{D5}ng Vi\u{D6}t", Charset.tcvn3),
        ("Ti\u{D5}ng", .tcvn3),
        ("C\u{E9}ng ho\u{B5} x\u{B7} h\u{E9}i ch\u{F1} ngh\u{DC}a Vi\u{D6}t Nam (CHXHCN), 1945.", .tcvn3),
        ("Tie\u{E1}ng Vie\u{E4}t", .vniWindows),
        ("ng\u{F6}\u{F4}\u{F8}i \u{F1}\u{F6}\u{F4}\u{EF}c m\u{F4}\u{F8}i", .vniWindows),
        ("to^i ddi ho.c", .viqr),
    ])
    func nhanRa(text: String, expected: Charset) {
        #expect(Charset.detect(text) == expected)
    }

    @Test(arguments: [
        "Tiếng Việt", "là", "hello world", "", "   ",
        "caf\u{E9} d\u{E9}j\u{E0} vu, o\u{F9} est le gar\u{E7}on",
        "o\u{F9}", "\u{E8}", "se\u{F1}or", "na\u{EF}ve", "\u{FC}ber", "S\u{E3}o Paulo",
        "add (a+b)^2", "x^2 + y^2", "What's up? I don't know.", "e.g. a.m.",
    ])
    func khongNhanNham(text: String) {
        #expect(Charset.detect(text) == nil)
    }

    @Test func boDau() {
        #expect(Charset.stripMarks("Đường Trần Hưng Đạo, quận 1") == "Duong Tran Hung Dao, quan 1")
        #expect(Charset.stripMarks(Charset.convert("Nguyễn", from: .unicode, to: .decomposed)) == "Nguyen")
    }
}
