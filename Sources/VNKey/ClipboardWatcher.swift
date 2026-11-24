import AppKit
import Carbon.HIToolbox
import VNKeyCore

/// Theo dõi clipboard hệ thống. macOS không báo khi clipboard đổi nên phải hỏi `changeCount` định kỳ;
/// việc này chạy bằng Timer riêng, không nằm trong callback của event tap.
final class ClipboardWatcher {
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private let queue = DispatchQueue(label: "local.vnkey.clipboard.read", qos: .utility)
    /// Giới hạn để một lần sao chép khổng lồ không làm phình lịch sử.
    private static let maxText = 1_000_000, maxImage = 20_000_000

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        lastChange = NSPasteboard.general.changeCount  // không nhặt thứ đã nằm sẵn trước khi bật
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Log.write("CLIP bắt đầu theo dõi")
    }

    func stop() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        Log.write("CLIP ngừng theo dõi")
    }

    /// VNKey vừa tự ghi lên clipboard: coi như đã đọc.
    func skipCurrent() { lastChange = NSPasteboard.general.changeCount }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        let types = (pb.types ?? []).map(\.rawValue)
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let excluded = Set(UserDefaults.standard.stringArray(forKey: Key.clipboardExcludedApps) ?? [])
        guard ClipPolicy.shouldCapture(types: types, app: app, excluded: excluded, secureInput: IsSecureEventInputEnabled()) else {
            Log.write("CLIP bỏ qua một lần sao chép (riêng tư hoặc ứng dụng loại trừ) app=\(app ?? "?")")
            return
        }
        let now = Date()

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let item = ClipItem(kind: .file, text: urls.map(\.path).joined(separator: "\n"), date: now, app: app)
            ClipboardStore.add(item)
            Log.write("CLIP +tệp số=\(urls.count)")
            return
        }
        if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard s.utf8.count <= ClipboardWatcher.maxText else {
                Log.write("CLIP bỏ qua văn bản quá dài (\(s.utf8.count) byte)")
                return
            }
            var item = ClipItem(kind: ClipKind.classify(s), text: s, date: now, app: app)
            var files: [String: Data] = [:]
            if item.kind == .text {
                for t in ClipboardStore.richTypes {
                    if let data = pb.data(forType: t.type), data.count <= t.limit { files[t.ext] = data }
                }
                item.rich = !files.isEmpty
            }
            ClipboardStore.add(item, files: files)
            Log.write("CLIP +\(item.kind.rawValue) dài=\(s.count) định dạng=\(files.keys.sorted().joined(separator: ","))")
            return
        }
        // Ảnh: đổi sang PNG ở luồng nền (ảnh chụp màn hình lớn mất vài chục ms).
        guard let raw = pb.data(forType: .png) ?? pb.data(forType: .tiff), raw.count <= ClipboardWatcher.maxImage else { return }
        queue.async {
            guard let rep = NSBitmapImageRep(data: raw), let png = rep.representation(using: .png, properties: [:]) else { return }
            var item = ClipItem(kind: .image, text: "", date: now, app: app, imageData: png)
            item.width = rep.pixelsWide
            item.height = rep.pixelsHigh
            DispatchQueue.main.async {
                ClipboardStore.add(item, files: ["png": png])
                Log.write("CLIP +ảnh \(rep.pixelsWide)x\(rep.pixelsHigh)")
            }
        }
    }
}
