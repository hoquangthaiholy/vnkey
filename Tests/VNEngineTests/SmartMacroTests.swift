import Foundation
import Testing

@testable import VNEngine

/// Gõ tắt thông minh (người dùng chốt 2026-11-25): gõ `\tên` (dấu `\` ở đầu từ) rồi ngắt từ thì bung ra nội dung; tên
/// do người dùng đặt; nội dung dùng được biến trong ngoặc vuông. Tiền tố `\` để không đụng gõ thường và ứng dụng khác.
@Suite struct SmartMacros {
    /// Thứ Tư, 25/11/2026, 15:07.
    static let fixed = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 15, minute: 7))!

    func engine(_ change: (inout Config) -> Void = { _ in }) -> Engine {
        var c = Config()
        c.smartMacros = ["homnay": "[ngay]", "bgio": "[gio]", "hoten": "[hoten]", "cty": "Công ty ABC"]
        change(&c)
        let e = Engine(config: c)
        e.now = { SmartMacros.fixed }
        e.variable = { $0 == "hoten" ? "Hồ Quang Thái" : nil }
        return e
    }

    @Test(arguments: [
        ("\\homnay ", "25/11/2026 "), ("xin \\homnay, ", "xin 25/11/2026, "), ("\\bgio\n", "15:07\n"), ("(\\homnay) ", "(25/11/2026) "),
        ("\\HOMNAY ", "25/11/2026 "), ("\\hoten ", "Hồ Quang Thái "), ("\\cty ", "Công ty ABC "),
        ("\\hom<<<homnay ", "25/11/2026 "),  // xoá tên gõ dở rồi gõ lại
        ("tooi \\cty nhes ", "tôi Công ty ABC nhé "),  // gõ tiếng Việt quanh đó vẫn bình thường
    ])
    func backslashNameExpands(keys: String, want: String) { #expect(run(keys, engine: engine()) == want) }

    /// Tên chưa định nghĩa, `\` không ở đầu từ (đường dẫn), và tên gõ không có `\`: không đụng tới.
    @Test(arguments: ["\\khongco ", "\\alpha \\n ", "C:\\homnay ", "a\\homnay ", "homnay ", "cty ", "\\ homnay "])
    func everythingElseIsLeftAlone(keys: String) { #expect(run(keys, engine: engine()) == keys) }

    @Test func emptyTableTurnsItOff() {
        #expect(run("\\homnay ", engine: engine { $0.smartMacros = [:] }) == "\\homnay ")
    }

    @Test func reportsWhatWasInserted() {
        let e = engine()
        _ = run("\\cty", engine: e)
        #expect(e.replaced == nil)
        _ = e.type(" ")
        #expect(e.replaced == "Công ty ABC")
        _ = e.type("a")
        #expect(e.replaced == nil)
    }

    @Test func variables() {
        func r(_ s: String) -> String { SmartMacro.resolve(s, at: SmartMacros.fixed) }
        #expect(r("[ngay] [gio] [thu] [thang] [nam]") == "25/11/2026 15:07 Thứ Tư 11 2026")
        #expect(r("[ngaydai]") == "ngày 25 tháng 11 năm 2026")
        #expect(r("[homqua] [ngaymai]") == "24/11/2026 26/11/2026")
        #expect(r("[ngay+7] [ngay-25] [ngay+0]") == "02/12/2026 31/10/2026 25/11/2026")
        #expect(r("[tuan]") == "48")
        #expect(r("[amlich]").hasPrefix("ngày ") && r("[amlich]").contains(" tháng "))
        #expect(r("[khonglabien] [ngay [ngay+x]") == "[khonglabien] [ngay [ngay+x]")
        #expect(SmartMacro.resolve("[hoten] [la]", at: SmartMacros.fixed) { $0 == "hoten" ? "An" : nil } == "An [la]")
    }

    /// Biến dùng được cả trong bảng gõ tắt thường (không tiền tố).
    @Test func variablesWorkInOrdinaryShortcuts() {
        let e = engine { $0.macros = ["kt": "Ký ngày [ngay] bởi [hoten]"] }
        #expect(run("kt ", engine: e) == "Ký ngày 25/11/2026 bởi Hồ Quang Thái ")
    }
}
