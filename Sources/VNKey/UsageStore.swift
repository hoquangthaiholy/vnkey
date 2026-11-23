import Foundation
import VNEngine
import VNKeyCore

/// Nơi giữ và lưu bảng đếm từ / cặp từ người dùng hay gõ (`UsageModel`), dùng để đoán từ theo ngữ cảnh.
/// Tệp chỉ nằm trên máy: ~/Library/Application Support/VNKey/usage.json. Chỉ gọi từ luồng chính.
enum UsageStore {
    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VNKey/usage.json")
    private(set) static var model = UsageModel()
    private static let queue = DispatchQueue(label: "local.vnkey.usage", qos: .utility)

    static func load() {
        if let data = try? Data(contentsOf: url), let m = UsageModel(data: data) {
            model = m
            Log.write("USAGE đã nạp: \(m.wordCount) từ, \(m.pairTotal) cặp")
        }
    }

    /// Ghi ra đĩa nếu có thay đổi. `wait`: chờ ghi xong (lúc thoát app); bình thường ghi ở luồng nền.
    static func saveIfNeeded(wait: Bool = false) {
        guard model.dirty else { return }
        let data = model.data(), target = url
        model.markSaved()
        let write = {
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: target, options: .atomic)
        }
        if wait { queue.sync(execute: write) } else { queue.async(execute: write) }
    }

    /// Xoá mọi thứ đã học, cả trong bộ nhớ lẫn trên đĩa.
    static func clear() {
        model.clear()
        model.markSaved()
        let target = url
        queue.async { try? FileManager.default.removeItem(at: target) }
        Log.write("USAGE đã xoá dữ liệu đã học")
    }
}
