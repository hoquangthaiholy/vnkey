import Foundation

// Logic thuần của app (không chạm tới event tap, cửa sổ hay Accessibility) để kiểm thử tự động được.

/// Mặt nạ phím bổ trợ, trùng giá trị với NSEvent.ModifierFlags và CGEventFlags.
public enum Mods {
    public static let shift: UInt = 1 << 17
    public static let control: UInt = 1 << 18
    public static let option: UInt = 1 << 19
    public static let command: UInt = 1 << 20
    public static let all: UInt = shift | control | option | command
}

/// Phím tắt: tổ hợp phím bổ trợ + một phím, hoặc chỉ phím bổ trợ (code = -1, nhấn rồi thả).
public struct Hotkey: Equatable {
    public static let modMask = Mods.all

    public var code: Int
    public var mods: UInt
    public var keyLabel: String

    public static let defaultToggle = Hotkey(code: -1, mods: Mods.control | Mods.shift, keyLabel: "")
    public static let defaultRestore = Hotkey(code: 6, mods: Mods.control | Mods.option, keyLabel: "Z")

    public var string: String { "\(code):\(mods):\(keyLabel)" }
    public var isModifierOnly: Bool { code < 0 }

    public init(code: Int, mods: UInt, keyLabel: String) {
        self.code = code; self.mods = mods & Mods.all; self.keyLabel = keyLabel
    }

    public init?(string: String) {
        let p = string.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard p.count == 3, let c = Int(p[0]), let m = UInt(p[1]), m & Mods.all != 0 else { return nil }
        self.init(code: c, mods: m, keyLabel: String(p[2]))
    }

    public var label: String {
        var s = ""
        if mods & Mods.control != 0 { s += "⌃" }
        if mods & Mods.option != 0 { s += "⌥" }
        if mods & Mods.shift != 0 { s += "⇧" }
        if mods & Mods.command != 0 { s += "⌘" }
        return s + keyLabel
    }

    /// Khớp với một lần nhấn phím thường.
    public func matches(code: Int, mods: UInt) -> Bool {
        !isModifierOnly && self.code == code && self.mods == mods & Mods.all
    }
}

/// Theo dõi phím bổ trợ để nhận ra "nhấn rồi thả mà không kèm phím nào khác".
public struct ModifierTracker {
    private var peak: UInt = 0
    private var dirty = false
    public init() {}

    /// Có phím thường hoặc chuột chen vào: lần thả này không tính là phím tắt.
    public mutating func interrupted() { dirty = true }

    /// Trả về tập phím bổ trợ lớn nhất đã giữ khi vừa thả hết một cách "sạch", ngược lại nil.
    public mutating func flagsChanged(_ mods: UInt) -> UInt? {
        let m = mods & Mods.all
        if m != 0 {
            if m & peak == peak { peak = m }
            return nil
        }
        let result = dirty || peak == 0 ? nil : peak
        peak = 0; dirty = false
        return result
    }
}

public enum KeyKind: Equatable {
    case backspace, newline, tab
    /// Phím di chuyển con trỏ / thoát: engine phải quên trạng thái.
    case navigation
    case character(Character)
    case unprintable
}

/// Phân loại một lần nhấn phím (không có ⌘/⌃/⌥) theo mã phím và ký tự macOS sinh ra.
public func classifyKey(code: Int, chars: String) -> KeyKind {
    switch code {
    case 51: return .backspace
    case 36, 76: return .newline
    case 48: return .tab
    case 53, 117, 115, 116, 119, 121, 123...126: return .navigation
    default:
        guard chars.count == 1, let ch = chars.first, let u = ch.unicodeScalars.first,
            u.value >= 0x20, u.value != 0x7F, !(0xF700...0xF8FF).contains(u.value)
        else { return .unprintable }
        return .character(ch)
    }
}

public enum SendStep: Equatable {
    case arrowLeft, arrowRight
    case backspace(Int)
    case text(String)
    /// Phát lại phím gốc của người dùng.
    case original
}

public struct SendPlan: Equatable {
    public var mode: String
    public var steps: [SendStep]
}

/// Quyết định chuỗi phím phát ra cho ứng dụng đích từ kết quả của engine.
public enum SendPlanner {
    /// Spotlight (tiến trình "campo" trên macOS mới): gợi ý không nằm trong nội dung ô nhập, ký tự rỗng
    /// không gạt được nó, và phím xoá lùi đầu tiên chỉ gạt gợi ý chứ không xoá chữ.
    public static let nudgeApps: Set<String> = ["com.apple.campo", "com.apple.Spotlight"]

    /// App có gợi ý tự điền ngay trong ô nhập dưới dạng vùng bôi chọn.
    public static let emptyCharApps: Set<String> = [
        "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
        "com.apple.Safari", "org.mozilla.firefox", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "com.microsoft.Excel",
    ]

    public static let emptyChar = "\u{202F}"

    /// - Parameters:
    ///   - app: bundle ID của tiến trình đang thật sự nhận phím.
    ///   - selection: độ dài vùng bôi chọn trong ô nhập, nil nếu không biết.
    public static func plan(
        backspaces: Int, text: String, passKey: Bool, app: String, selection: Int?, fixAutocomplete: Bool
    ) -> SendPlan {
        var steps: [SendStep] = []
        var mode = "plain"
        var n = backspaces
        if n > 0, fixAutocomplete {
            if let sel = selection, sel > 0 {
                // Đang gõ dở mà có vùng bôi chọn = gợi ý tự điền: phím xoá đầu tiên chỉ xoá gợi ý.
                n += 1
                mode = "selection"
            } else if nudgeApps.contains(app) {
                // Nhích con trỏ trái rồi phải: gạt gợi ý mà không đổi nội dung; dù phím trái có bị
                // "nuốt" để gạt gợi ý hay không thì con trỏ vẫn về lại cuối.
                steps += [.arrowLeft, .arrowRight]
                mode = "nudge"
            } else if emptyCharApps.contains(app) {
                // Chèn một ký tự rỗng để "chốt" phần gợi ý, rồi xoá luôn ký tự đó.
                steps.append(.text(emptyChar))
                n += 1
                mode = "emptyChar"
            }
        }
        if n > 0 { steps.append(.backspace(n)) }
        if !text.isEmpty { steps.append(.text(text)) }
        if passKey { steps.append(.original) }
        return SendPlan(mode: mode, steps: steps)
    }

    public enum BackspaceRoute: Equatable {
        /// Để phím đi thẳng và cập nhật engine như thường.
        case normal
        /// Ứng dụng sẽ chỉ gạt phần gợi ý, không xoá chữ: cho phím đi thẳng, KHÔNG đụng tới engine.
        case suggestionOnly
        /// Không biết gợi ý có đang hiện không: tự gạt gợi ý rồi xoá, để engine và màn hình khớp nhau.
        case planned
    }

    /// Người dùng tự nhấn xoá lùi khi engine đang theo dõi chữ trước con trỏ.
    public static func userBackspace(app: String, selection: Int?, fixAutocomplete: Bool) -> BackspaceRoute {
        guard fixAutocomplete else { return .normal }
        if let sel = selection, sel > 0 { return .suggestionOnly }
        return nudgeApps.contains(app) ? .planned : .normal
    }

    /// Cắt văn bản thành các đoạn UTF-16 ngắn (một số app cắt chuỗi dài), không xẻ đôi cặp surrogate.
    public static func chunks(_ text: String, size: Int = 16) -> [[UInt16]] {
        let units = Array(text.utf16)
        var out: [[UInt16]] = []
        var i = 0
        while i < units.count {
            var end = min(i + size, units.count)
            if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) { end -= 1 }
            out.append(Array(units[i..<end]))
            i = end
        }
        return out
    }
}

public enum AppMode {
    /// Chế độ VN/EN khi chuyển sang một ứng dụng.
    public static func initial(
        bundle: String, excluded: Set<String>, perApp: Bool, states: [String: Bool], global: Bool
    ) -> Bool {
        if excluded.contains(bundle) { return false }
        if perApp, let on = states[bundle] { return on }
        return global
    }
}

/// Định dạng văn bản của các danh sách trong cửa sổ Cài đặt.
public enum ListFormat {
    /// Mỗi dòng một mục: bỏ khoảng trắng thừa, dòng trống và mục trùng; giữ thứ tự.
    public static func lines(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// "vn = Việt Nam" mỗi dòng -> [vn: Việt Nam]. Khoá viết thường; dòng sai định dạng bị bỏ qua.
    public static func macros(from text: String) -> [String: String] {
        var d: [String: String] = [:]
        for l in lines(text) {
            let p = l.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if p.count == 2, !p[0].isEmpty, !p[1].isEmpty { d[p[0].lowercased()] = p[1] }
        }
        return d
    }

    public static func text(from macros: [String: String]) -> String {
        macros.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)" }.joined(separator: "\n")
    }
}

/// Hiện ký tự điều khiển cho dễ đọc trong nhật ký.
public func showControl(_ s: String) -> String {
    var out = "\""
    for u in s.unicodeScalars {
        switch u {
        case "\n", "\r": out += "⏎"
        case "\t": out += "⇥"
        case " ": out += "␣"
        default: out += u.value < 0x20 || u.value == 0x202F ? "\\u{\(String(u.value, radix: 16))}" : String(u)
        }
    }
    return out + "\""
}
