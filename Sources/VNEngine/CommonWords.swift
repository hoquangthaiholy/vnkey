/// Độ thông dụng của các âm tiết tiếng Việt, từ một bảng tần suất đếm trên kho ngữ liệu thật (xem nguồn và
/// giấy phép ở đầu `CommonWordsData.swift`). Dùng cho hai việc khi đoán từ gõ thiếu dấu:
/// - chọn giữa các ứng viên khi chưa có bằng chứng nào từ chính người dùng ("được" thay vì "dược");
/// - phân biệt chữ gõ dở với từ thật. Từ điển của macOS coi gần như mọi âm tiết đúng cấu trúc là từ đúng
///   ("tiêng", "dúng", "ròi"); trong kho ngữ liệu những chữ đó hầu như không xuất hiện, còn từ thật dù hiếm
///   ("muôn", "trương", "dược") vẫn có vài trăm lần.
/// Kho ngữ liệu là phụ đề phim: nghiêng về văn nói, và có lẫn ít lỗi gõ của người làm phụ đề (nên một chữ CÓ
/// mặt với số đếm rất nhỏ chưa chắc là từ thật; vì vậy bảng bỏ các mục dưới `tableFloor`).
enum CommonWords {
    /// Bảng chỉ lưu âm tiết xuất hiện từ chừng này lần trở lên: đó là "từ điển" của VNKey. Chữ có dấu không nằm
    /// trong bảng bị coi là không thông dụng (nhiều khả năng gõ dở) và được thay bằng ứng viên thông dụng nhất.
    static let tableFloor = 100
    /// Mức "rất thông dụng": chuỗi phím trùng một từ tiếng Anh chỉ bị thay khi ứng viên đạt mức này.
    static let veryCommon = 5000
    /// Mức "thông dụng": ứng viên dưới mức này chỉ được thay cho chữ đã gõ khi có thêm bằng chứng (từ đứng trước
    /// hay đi với nó, hoặc chính người dùng đã gõ nó).
    static let common = 1000
    /// Hai ứng viên chênh nhau dưới chừng này lần được coi là cùng hạng: ngữ cảnh câu mới phân xử được.
    static let sameLeague = 50

    /// Các khoá của bảng theo thứ tự trong dữ liệu (giảm dần theo số lần). `CommonPairs` đánh số âm tiết theo thứ
    /// tự này, nên sinh lại bảng âm tiết thì phải sinh lại cả bảng cặp từ.
    static let keys: [String] = entries.map(\.key)
    private static let table: [String: Int] = Dictionary(entries.map { ($0.key, $0.count) }, uniquingKeysWith: { a, _ in a })

    private static let entries: [(key: String, count: Int)] = {
        var out: [(key: String, count: Int)] = []
        out.reserveCapacity(entryCount)
        var key: Substring?
        for part in data.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            if let k = key {
                out.append((String(k), Int(part) ?? 0))
                key = nil
            } else {
                key = part
            }
        }
        return out
    }()

    /// Số lần âm tiết này xuất hiện trong kho ngữ liệu; 0 nếu không có (hoặc dưới `tableFloor`). Không phân biệt
    /// hoa/thường và cách đặt dấu thanh.
    static func count(_ word: String) -> Int {
        Charset.syllableKey(word).flatMap { table[$0] } ?? 0
    }

    /// Trọng số để cộng chung với số lần chính người dùng đã gõ (mỗi lần của họ tính bằng 10): 1 cho mỗi 100 lần
    /// xuất hiện trong kho.
    static func weight(_ word: String) -> Int { count(word) / 100 }
}
