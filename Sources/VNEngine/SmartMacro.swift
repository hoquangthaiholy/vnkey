import Foundation

/// Biến trong nội dung gõ tắt (người dùng yêu cầu 2026-11-25): viết trong ngoặc vuông, được thay bằng giá trị lúc gõ
/// tắt bung ra ("[ngay]" -> 25/11/2026). Dùng được ở cả bảng gõ tắt thường lẫn bảng gõ tắt thông minh (`\tên`).
/// Ngày giờ viết theo lối Việt Nam, không theo cài đặt vùng của máy.
public enum SmartMacro {
    /// Tên biến và ý nghĩa, theo thứ tự hiện trong Cài đặt. "hoten" và "clipboard" do app cung cấp
    /// (`Engine.variable`); "ngay+N" / "ngay-N" là ngày cách hôm nay N ngày.
    public static let variables = [
        "ngay", "gio", "thu", "thang", "nam", "ngaydai", "homqua", "ngaymai", "ngay+7", "tuan", "amlich", "hoten", "clipboard",
    ]
    private static let weekdays = ["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"]

    private static func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    private static func short(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(two(c.day ?? 1))/\(two(c.month ?? 1))/\(c.year ?? 0)"
    }

    private static func value(_ name: Substring, _ date: Date, _ calendar: Calendar) -> String? {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        func shifted(_ days: Int) -> String? { calendar.date(byAdding: .day, value: days, to: date).map { short($0, calendar) } }
        switch name {
        case "ngay": return short(date, calendar)
        case "gio": return "\(two(c.hour ?? 0)):\(two(c.minute ?? 0))"
        case "thu": return weekdays[max(0, min(6, (c.weekday ?? 1) - 1))]
        case "thang": return "\(c.month ?? 1)"
        case "nam": return "\(c.year ?? 0)"
        case "ngaydai": return "ngày \(c.day ?? 1) tháng \(c.month ?? 1) năm \(c.year ?? 0)"
        case "homqua": return shifted(-1)
        case "ngaymai": return shifted(1)
        case "tuan":
            var iso = Calendar(identifier: .iso8601)
            iso.timeZone = calendar.timeZone
            return "\(iso.component(.weekOfYear, from: date))"
        case "amlich":
            // Lịch âm của macOS là lịch Trung Quốc: gần như luôn trùng lịch âm Việt Nam, có thể lệch một ngày ở vài
            // thời điểm do khác múi giờ tính điểm sóc.
            var lunar = Calendar(identifier: .chinese)
            lunar.timeZone = calendar.timeZone
            let l = lunar.dateComponents([.month, .day], from: date)  // (tháng nhuận cần macOS 14 mới hỏi được: không ghi)
            return "ngày \(l.day ?? 1) tháng \(l.month ?? 1) âm lịch"
        default:
            // "ngay+7", "ngay-25": ngày cách hôm nay chừng đó ngày.
            guard name.hasPrefix("ngay"), name.count > 5, let n = Int(name.dropFirst(5)), n <= 36_500 else { return nil }
            let sign = name.dropFirst(4).first
            guard sign == "+" || sign == "-" else { return nil }
            return shifted(sign == "+" ? n : -n)
        }
    }

    /// Thay các biến "[tên]" trong `text` bằng giá trị tại thời điểm `date`. Tên engine không biết thì hỏi `extra`
    /// (app trả "hoten", "clipboard"). Ngoặc vuông không chứa tên biến thì để nguyên.
    public static func resolve(_ text: String, at date: Date, calendar: Calendar = .current, extra: ((String) -> String?)? = nil) -> String {
        guard text.contains("[") else { return text }
        var out = "", rest = Substring(text)
        while let open = rest.firstIndex(of: "[") {
            out += rest[..<open]
            let after = rest[rest.index(after: open)...]
            if let close = after.firstIndex(of: "]"), let v = value(after[..<close], date, calendar) ?? extra?(String(after[..<close])) {
                out += v
                rest = after[after.index(after: close)...]
            } else {
                out.append("[")
                rest = after
            }
        }
        return out + rest
    }
}
