import AppKit
import VNEngine
import VNKeyCore

/// Nơi giữ và lưu lịch sử clipboard (`ClipHistory`). Chỉ gọi từ luồng chính.
/// Tệp nằm trên máy: ~/Library/Application Support/VNKey/clipboard/ (history.json, ảnh `<id>.png`, và bản có
/// định dạng của văn bản: `<id>.rtfd`, `<id>.rtf`, `<id>.html`).
/// Nội dung ở đây riêng tư như nhật ký: không ghi nó vào log.
enum ClipboardStore {
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VNKey/clipboard", isDirectory: true)
    private static let url = dir.appendingPathComponent("history.json")
    private(set) static var history = ClipHistory()
    /// Lịch sử vừa đổi (để bảng đang mở vẽ lại và bộ đồng bộ chạy).
    static var onChange: (() -> Void)?
    private static let queue = DispatchQueue(label: "local.vnkey.clipboard", qos: .utility)

    /// Các dạng có định dạng của văn bản, giàu nhất trước (thứ tự này cũng là thứ tự khai báo khi dán):
    /// RTFD (RTF kèm ảnh nhúng: TextEdit, Pages), RTF (Word, Mail), HTML (trình duyệt, Google Docs, Notion).
    static let richTypes: [(ext: String, type: NSPasteboard.PasteboardType, limit: Int)] = [
        ("rtfd", .rtfd, 10_000_000), ("rtf", .rtf, 2_000_000), ("html", .html, 2_000_000),
    ]
    private static let sideExtensions = ["png"] + richTypes.map(\.ext)

    static func sideURL(_ id: String, _ ext: String) -> URL { dir.appendingPathComponent(id + "." + ext) }
    static func imageURL(_ id: String) -> URL { sideURL(id, "png") }

    static func load() {
        if let data = try? Data(contentsOf: url), let h = ClipHistory(data: data) {
            history = h
            Log.write("CLIP đã nạp \(h.items.count) mục")
        }
    }

    /// Ghi một lần sao chép mới. `files`: dữ liệu đi kèm theo đuôi tệp (ảnh "png", bản có định dạng "rtf"…).
    static func add(_ item: ClipItem, files: [String: Data] = [:]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Sao chép lại cùng nội dung từ ứng dụng khác: bỏ các dạng cũ để không dán nhầm định dạng của lần trước.
        for ext in sideExtensions where files[ext] == nil { try? FileManager.default.removeItem(at: sideURL(item.id, ext)) }
        for (ext, data) in files { try? data.write(to: sideURL(item.id, ext), options: .atomic) }
        change { $0.add(item) }
    }

    /// Mọi thay đổi đi qua đây: dọn tệp đi kèm của mục vừa rời lịch sử rồi báo cho giao diện.
    static func change(_ body: (inout ClipHistory) -> Void) {
        body(&history)
        let gone = history.takeRemoved()
        if !gone.isEmpty {
            // Mục vừa được thêm lại ngay trong lần đổi này thì giữ tệp.
            let files = gone.filter { history.item($0) == nil }.flatMap { id in sideExtensions.map { sideURL(id, $0) } }
            queue.async { files.forEach { try? FileManager.default.removeItem(at: $0) } }
        }
        onChange?()
    }

    /// Ghi ra đĩa nếu có thay đổi. `wait`: chờ ghi xong (lúc thoát app).
    static func saveIfNeeded(wait: Bool = false) {
        guard history.dirty else { return }
        let data = history.data(), target = url
        history.markSaved()
        let write = {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: target, options: .atomic)
        }
        if wait { queue.sync(execute: write) } else { queue.async(execute: write) }
    }
}

/// Cách dán một mục từ lịch sử.
enum PasteMode {
    /// Mặc định: văn bản bảng mã cũ thì dán Unicode; còn lại dán nguyên dạng (giữ định dạng nếu có).
    case smart
    /// Đúng như lúc sao chép.
    case original
    /// Chỉ chữ: bỏ định dạng; với tệp là đường dẫn.
    case plain
    case charset(Charset)
    /// Bỏ dấu tiếng Việt.
    case stripped
    /// Dịch định dạng đã lưu (HTML, RTF) thành cú pháp Markdown: **đậm**, [liên kết](…), danh sách, bảng.
    case markdown
}

enum ClipText {
    private static var cache: [String: Charset?] = [:]

    /// Bảng mã cũ của một mục văn bản (nil = Unicode bình thường). Nhớ theo `id` vì `id` là mã băm nội dung.
    static func legacy(_ item: ClipItem) -> Charset? {
        guard item.kind == .text else { return nil }
        if let hit = cache[item.id] { return hit }
        if cache.count > 2000 { cache.removeAll() }
        let found = Charset.detect(String(item.text.prefix(4000)))
        cache[item.id] = found
        return found
    }

    static func unicode(_ item: ClipItem) -> String {
        legacy(item).map { Charset.convert(item.text, from: $0, to: .unicode) } ?? item.text
    }

    /// Các dạng có định dạng đang lưu kèm mục này, giàu nhất trước ("rtfd", "rtf", "html").
    static func formats(_ item: ClipItem) -> [String] {
        guard item.rich else { return [] }
        return ClipboardStore.richTypes.map(\.ext).filter { FileManager.default.fileExists(atPath: ClipboardStore.sideURL(item.id, $0).path) }
    }

    /// Bản Markdown của một mục có định dạng; nil nếu không có gì để dịch. HTML dùng thẳng; chỉ có RTF/RTFD thì
    /// nhờ AppKit đổi sang HTML trước.
    static func markdown(_ item: ClipItem) -> String? {
        var html: String?
        if let data = try? Data(contentsOf: ClipboardStore.sideURL(item.id, "html")) {
            html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
        } else {
            var styled: NSAttributedString?
            if let data = try? Data(contentsOf: ClipboardStore.sideURL(item.id, "rtfd")) { styled = NSAttributedString(rtfd: data, documentAttributes: nil) }
            if styled == nil, let data = try? Data(contentsOf: ClipboardStore.sideURL(item.id, "rtf")) { styled = NSAttributedString(rtf: data, documentAttributes: nil) }
            if let styled,
                let data = try? styled.data(
                    from: NSRange(location: 0, length: styled.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue])
            {
                html = String(data: data, encoding: .utf8)
            }
        }
        guard let html else { return nil }
        let out = HTMLMarkdown.convert(html)
        return out.isEmpty ? nil : out
    }

    static func name(_ cs: Charset) -> String {
        switch cs {
        case .unicode: return L("Unicode dựng sẵn", "Unicode (precomposed)")
        case .decomposed: return L("Unicode tổ hợp", "Unicode (combining)")
        case .tcvn3: return "TCVN3 (ABC)"
        case .vniWindows: return "VNI Windows"
        case .viqr: return "VIQR"
        }
    }
}

enum ClipPasteboard {
    static let own = NSPasteboard.PasteboardType(ClipPolicy.ownType)

    /// Đặt một mục lên clipboard hệ thống để dán. false = không còn dữ liệu (ảnh đã mất, tệp đã xoá).
    static func write(_ item: ClipItem, _ mode: PasteMode) -> Bool {
        let pb = NSPasteboard.general
        switch item.kind {
        case .text, .link:
            var text = item.text
            var keepRich = false
            switch mode {
            case .original: keepRich = true
            case .smart:
                text = ClipText.unicode(item)
                keepRich = text == item.text
            case .plain: text = ClipText.unicode(item)
            case .charset(let cs): text = Charset.convert(ClipText.unicode(item), from: .unicode, to: cs)
            case .stripped: text = Charset.stripMarks(ClipText.unicode(item))
            case .markdown: text = ClipText.markdown(item) ?? ClipText.unicode(item)
            }
            // Khai báo dạng giàu nhất trước: ứng dụng đích chọn dạng đầu tiên nó hiểu.
            var rich: [(NSPasteboard.PasteboardType, Data)] = []
            if keepRich, item.rich {
                for t in ClipboardStore.richTypes {
                    if let data = try? Data(contentsOf: ClipboardStore.sideURL(item.id, t.ext)) { rich.append((t.type, data)) }
                }
            }
            pb.clearContents()
            pb.declareTypes(rich.map(\.0) + [.string], owner: nil)
            for (type, data) in rich { pb.setData(data, forType: type) }
            pb.setString(text, forType: .string)
        case .image:
            guard let data = try? Data(contentsOf: ClipboardStore.imageURL(item.id)), let image = NSImage(data: data) else { return false }
            pb.clearContents()
            pb.writeObjects([image])
            pb.setData(data, forType: .png)
        case .file:
            if case .plain = mode {
                pb.clearContents()
                pb.setString(item.text, forType: .string)
            } else {
                let urls = item.paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) as NSURL }
                guard !urls.isEmpty else { return false }
                pb.clearContents()
                pb.writeObjects(urls)
            }
        }
        // Đánh dấu là của VNKey để bộ theo dõi không ghi lại chính lần dán này.
        pb.setData(Data(), forType: own)
        return true
    }
}
