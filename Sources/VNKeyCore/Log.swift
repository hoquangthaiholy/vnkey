import Foundation

/// Nhật ký gỡ lỗi đầy đủ: mọi phím, kết quả của engine, cách gửi phím và các sự kiện hệ thống.
/// LƯU Ý: khi bật, tệp log chứa nguyên văn những gì bạn gõ (trừ ô mật khẩu — macOS không cho
/// bộ gõ thấy phím ở đó). Tệp chỉ nằm trên máy này: ~/Library/Logs/VNKey.log
public enum Log {
    public static var enabled = false
    public static var url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/VNKey.log")
    private static var handle: FileHandle?
    private static let maxBytes: UInt64 = 5 << 20
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    public static func write(_ line: @autoclosure () -> String) {
        guard enabled, let data = "\(stamp.string(from: Date())) \(line())\n".data(using: .utf8) else { return }
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            handle?.seekToEndOfFile()
        }
        guard let h = handle else { return }
        if h.offsetInFile > maxBytes {  // quá 5 MB: giữ bản cũ thành .1 rồi ghi tệp mới
            try? h.close()
            handle = nil
            let old = url.appendingPathExtension("1")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
            write(line())
            return
        }
        h.write(data)
    }

    /// Đẩy mọi thứ còn trong bộ đệm ra đĩa.
    public static func flush() {}

    public static func show(_ s: String) -> String { showControl(s) }
}
