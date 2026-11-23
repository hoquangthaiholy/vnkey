import Foundation

/// Nhật ký gỡ lỗi đầy đủ: mọi phím, kết quả của engine, cách gửi phím và các sự kiện hệ thống.
/// LƯU Ý: khi bật, tệp log chứa nguyên văn những gì bạn gõ (trừ ô mật khẩu — macOS không cho
/// bộ gõ thấy phím ở đó). Tệp chỉ nằm trên máy này: ~/Library/Logs/VNKey.log
///
/// Người gọi (thường là callback của event tap) chỉ dựng chuỗi và xếp nó vào hàng đợi; việc định dạng
/// giờ và ghi đĩa chạy ở luồng nền, nên một ổ đĩa chậm không làm trễ phím nào.
public enum Log {
    public static var enabled = false
    public static var url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/VNKey.log")
    private static let maxBytes: UInt64 = 5 << 20
    private static let queue = DispatchQueue(label: "local.vnkey.log", qos: .utility)

    // Chỉ đụng tới các biến dưới đây từ `queue`.
    private static var handle: FileHandle?
    private static var openedURL: URL?
    private static var size: UInt64 = 0
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    public static func write(_ line: @autoclosure () -> String) {
        guard enabled else { return }
        let text = line(), now = Date(), target = url
        queue.async { append(text, at: now, to: target) }
    }

    private static func append(_ text: String, at time: Date, to target: URL) {
        guard let data = "\(stamp.string(from: time)) \(text)\n".data(using: .utf8) else { return }
        if openedURL != target { close() }
        if handle != nil, size > maxBytes {  // quá 5 MB: giữ bản cũ thành .1 rồi ghi tệp mới
            close()
            let old = target.appendingPathExtension("1")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: target, to: old)
        }
        if handle == nil {
            if !FileManager.default.fileExists(atPath: target.path) {
                FileManager.default.createFile(atPath: target.path, contents: nil)
            }
            guard let h = try? FileHandle(forWritingTo: target) else { return }
            size = (try? h.seekToEnd()) ?? 0
            handle = h
            openedURL = target
        }
        // Lỗi ghi (đĩa đầy, tệp bị xoá) không được làm sập bộ gõ: bỏ dòng này và mở lại ở lần sau.
        do {
            try handle?.write(contentsOf: data)
            size += UInt64(data.count)
        } catch {
            close()
        }
    }

    private static func close() {
        try? handle?.close()
        handle = nil
        openedURL = nil
        size = 0
    }

    /// Chờ mọi dòng đang xếp hàng được ghi ra đĩa (gọi trước khi thoát hoặc trước khi đọc lại tệp).
    public static func flush() { queue.sync {} }

    public static func show(_ s: String) -> String { showControl(s) }
}
