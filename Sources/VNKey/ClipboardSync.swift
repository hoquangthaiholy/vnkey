import Foundation
import VNKeyCore

/// Đồng bộ lịch sử clipboard qua một thư mục trong iCloud Drive: mỗi mục một tệp `<id>.json`.
/// Luật hoà trộn nằm ở `ClipSync` (VNKeyCore, có test); lớp này chỉ đọc/ghi tệp ở luồng nền.
/// CHƯA kiểm chứng trên iCloud thật (cần hai máy cùng tài khoản); đã thử qua thư mục thường.
final class ClipboardSync {
    private let queue = DispatchQueue(label: "local.vnkey.clipboard.sync", qos: .utility)
    private let device = Host.current().localizedName ?? "Mac"
    private var watch: DispatchSourceFileSystemObject?
    private var pending = false
    private var running = false
    private(set) var isOn = false

    private static let cloudDocs = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    private static let knownURL = ClipboardStore.dir.appendingPathComponent("sync-known.json")

    /// Thư mục đồng bộ; khoá ẩn `clipboardSyncFolder` trỏ nó sang chỗ khác khi thử nghiệm.
    static var folder: URL? {
        if let custom = UserDefaults.standard.string(forKey: Key.clipboardSyncFolder), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        guard FileManager.default.fileExists(atPath: cloudDocs.path) else { return nil }
        return cloudDocs.appendingPathComponent("VNKey/items", isDirectory: true)
    }

    static var isAvailable: Bool { folder != nil }

    func start() {
        guard !isOn, let folder = ClipboardSync.folder else { return }
        isOn = true
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fd = open(folder.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in self?.schedule() }
            source.setCancelHandler { close(fd) }
            source.resume()
            watch = source
        }
        Log.write("CLIP SYNC bật")
        run()
    }

    func stop() {
        guard isOn else { return }
        isOn = false
        watch?.cancel()
        watch = nil
        Log.write("CLIP SYNC tắt")
    }

    /// Gộp nhiều thay đổi liền nhau thành một lần đối chiếu.
    func schedule() {
        guard isOn, !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.pending = false
            self?.run()
        }
    }

    /// Một lần đối chiếu. Gọi từ luồng chính.
    func run() {
        guard isOn, !running, let folder = ClipboardSync.folder else { return }
        running = true
        let local = ClipboardStore.history.items, device = device
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var remote: [ClipItem] = []
            var files: [String: [URL]] = [:]
            for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                let name = url.lastPathComponent
                if name.hasPrefix("."), name.hasSuffix(".icloud") {  // tệp iCloud chưa tải về máy
                    try? fm.startDownloadingUbiquitousItem(at: url)
                    continue
                }
                guard url.pathExtension == "json", let data = try? Data(contentsOf: url),
                    let item = ClipSync.decode(data, device: device)
                else { continue }
                remote.append(item)
                files[item.id, default: []].append(url)
            }
            let known = (try? Data(contentsOf: ClipboardSync.knownURL)).flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
            let plan = ClipSync.reconcile(local: local, remote: remote, known: known)
            for item in plan.upload {
                try? ClipSync.encode(item, device: device).write(to: folder.appendingPathComponent(item.id + ".json"), options: .atomic)
            }
            for id in plan.deleteRemote { files[id]?.forEach { try? fm.removeItem(at: $0) } }
            if plan.known != known, let data = try? JSONEncoder().encode(plan.known) {
                try? fm.createDirectory(at: ClipboardStore.dir, withIntermediateDirectories: true)
                try? data.write(to: ClipboardSync.knownURL, options: .atomic)
            }
            DispatchQueue.main.async {
                self.running = false
                guard self.isOn, !plan.isEmpty else { return }
                if !plan.adopt.isEmpty || !plan.deleteLocal.isEmpty {
                    ClipboardStore.change { h in
                        plan.adopt.forEach { h.adopt($0) }
                        plan.deleteLocal.forEach { h.remove($0) }
                    }
                }
                Log.write("CLIP SYNC lên=\(plan.upload.count) về=\(plan.adopt.count) xoá ở máy=\(plan.deleteLocal.count) xoá trên iCloud=\(plan.deleteRemote.count)")
            }
        }
    }

    /// Người dùng tắt đồng bộ và chọn xoá bản trên iCloud.
    func removeRemoteCopies() {
        guard let folder = ClipboardSync.folder else { return }
        queue.async {
            let fm = FileManager.default
            for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "json" {
                try? fm.removeItem(at: url)
            }
            try? fm.removeItem(at: ClipboardSync.knownURL)
            Log.write("CLIP SYNC đã xoá bản trên iCloud")
        }
    }

    /// Tắt đồng bộ mà giữ bản trên iCloud: quên danh sách "đã biết" để lần bật lại không coi là mục đã xoá.
    func forgetKnown() {
        queue.async { try? FileManager.default.removeItem(at: ClipboardSync.knownURL) }
    }
}
