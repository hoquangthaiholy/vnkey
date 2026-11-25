import AppKit
import VNKeyCore

/// Vẽ giao diện ra tệp PNG mà không cần quyền chụp màn hình, để xem bố cục khi phát triển:
/// `VNKey --snapshot <thư mục>`.
///
/// Chỉ đáng tin ở chế độ sáng. Đã thử ép chế độ tối (`--dark`): chữ đổi màu nhưng nền và các nút vẫn
/// vẽ kiểu sáng, nên ảnh ra sai. Chế độ tối phải nhờ người dùng xem trên màn hình thật; cờ `--dark`
/// chỉ còn dùng để xem biểu tượng thanh menu trên nền tối.
enum Snapshot {
    static func run(into dir: URL, dark: Bool) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let suffix = dark ? "-dark" : ""

        let settings = SettingsController()
        let window = settings.window
        window.appearance = NSApp.appearance
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))  // ngoài màn hình
        window.orderFrontRegardless()
        settings.reload()
        for i in 0..<settings.tabCount {
            // Không dùng chuyển động: khi màn hình đang ngủ hoặc bị khoá, macOS không chạy chuyển động đổi
            // khung cửa sổ, và mọi thẻ sẽ bị chụp ở chiều cao của thẻ đầu.
            settings.selectTab(i, animated: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            window.layoutIfNeeded()
            window.displayIfNeeded()
            write(settings.contentView, dark: dark, to: dir.appendingPathComponent("settings-\(i + 1)\(suffix).png"))
        }
        // Cả khung cửa sổ (thanh tiêu đề + thanh thẻ) của thẻ đầu, để thấy tiêu đề và các thẻ có đủ chỗ không.
        settings.selectTab(0, animated: false)
        window.displayIfNeeded()
        if let frame = window.contentView?.superview {
            write(frame, dark: dark, to: dir.appendingPathComponent("settings-window\(suffix).png"))
        }
        window.orderOut(nil)

        // Bảng "đã nhớ" mở từ thẻ Chính tả.
        for name in ["settings-memory"] {
            let view = settings.memoryView()
            guard let sheet = view.window else { continue }
            sheet.appearance = NSApp.appearance
            sheet.setFrameOrigin(NSPoint(x: -4000, y: -4000))
            sheet.orderFrontRegardless()
            view.layoutSubtreeIfNeeded()
            sheet.displayIfNeeded()
            write(view, dark: dark, to: dir.appendingPathComponent("\(name)\(suffix).png"))
            sheet.orderOut(nil)
        }

        // Đổi thẻ có chuyển động (như khi người dùng bấm) không được làm mất tiêu đề cửa sổ: NSTabViewController
        // tự đặt lại tiêu đề theo thẻ sau khi chọn. Ảnh không thấy được việc này nên kiểm bằng giá trị.
        window.orderFrontRegardless()
        settings.selectTab(1, animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        if window.title != SettingsController.windowTitle { print("CẢNH BÁO: tiêu đề cửa sổ Cài đặt bị mất sau khi đổi thẻ: [\(window.title)]") }
        window.orderOut(nil)

        // Cửa sổ hướng dẫn cấp quyền, ở cả hai trạng thái.
        let onboarding = OnboardingController()
        onboarding.window.appearance = NSApp.appearance
        onboarding.window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        onboarding.window.orderFrontRegardless()
        for (ready, name) in [(false, "onboarding-wait"), (true, "onboarding-ready")] {
            onboarding.update(ready: ready)
            onboarding.window.layoutIfNeeded()
            onboarding.window.displayIfNeeded()
            write(onboarding.contentView, dark: dark, to: dir.appendingPathComponent("\(name)\(suffix).png"))
        }
        onboarding.window.orderOut(nil)

        // Nhãn cạnh con trỏ, phóng to 6 lần cho dễ nhìn.
        for (text, name) in [("VN", "vn"), ("EN", "en"), ("VN - Telex", "vn-telex")] {
            let pill = HUDPill(text: text)
            let pillSize = pill.fittingPillSize
            pill.setFrameSize(pillSize)
            let holder = NSWindow(
                contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: pillSize), styleMask: .borderless,
                backing: .buffered, defer: false)
            holder.contentView = pill
            holder.orderFrontRegardless()
            pill.layoutSubtreeIfNeeded()
            pill.displayIfNeeded()
            if let rep = pill.bitmapImageRepForCachingDisplay(in: pill.bounds) {
                pill.cacheDisplay(in: pill.bounds, to: rep)
                let big = NSImage(size: NSSize(width: pillSize.width * 6 + 48, height: pillSize.height * 6 + 48), flipped: false) { r in
                    (dark ? NSColor(white: 0.15, alpha: 1) : NSColor.white).setFill()
                    r.fill()
                    NSGraphicsContext.current?.imageInterpolation = .none
                    rep.draw(in: r.insetBy(dx: 24, dy: 24))
                    return true
                }
                if let tiff = big.tiffRepresentation, let out = NSBitmapImageRep(data: tiff) {
                    try? out.representation(using: .png, properties: [:])?.write(
                        to: dir.appendingPathComponent("hud-\(name)\(suffix).png"))
                }
            }
            holder.orderOut(nil)
        }

        // Bảng clipboard với dữ liệu mẫu (không đọc lịch sử thật), ở trạng thái đang bật và đang tắt.
        let now = Date()
        var samples = [
            ClipItem(kind: .text, text: "Ti\u{D5}ng Vi\u{D6}t c\u{E3} d\u{CA}u, ch\u{D0}p t\u{F5} v\u{A8}n b\u{B6}n c\u{F2}", date: now, app: "com.apple.TextEdit"),
            ClipItem(kind: .link, text: "https://hoquangthaiholy.github.io/vnkey/", date: now.addingTimeInterval(-1)),
            ClipItem(kind: .text, text: "Họp nhóm lúc 3 giờ chiều thứ Sáu, phòng 204", date: now.addingTimeInterval(-2), app: "com.apple.Notes"),
            ClipItem(kind: .file, text: "/Applications/Safari.app\n/Applications/Notes.app", date: now.addingTimeInterval(-3)),
            ClipItem(kind: .text, text: "func hello() { print(\"xin chào\") }", date: now.addingTimeInterval(-4), app: "com.apple.Terminal"),
        ]
        samples[2].pinned = true
        samples[4].device = "MacBook Air"
        for (enabled, name) in [(true, "clipboard"), (false, "clipboard-off")] {
            let panel = ClipboardPanel()
            panel.isEnabled = { enabled }
            panel.formats = { $0.text.hasPrefix("Họp") ? ["rtf", "html"] : $0.kind == .text && $0.app == "com.apple.Terminal" ? ["html"] : [] }
            panel.items = { _ in samples.filter(\.pinned) + samples.filter { !$0.pinned } }
            panel.window.appearance = NSApp.appearance
            panel.reload()
            panel.contentView.layoutSubtreeIfNeeded()
            let size = panel.contentView.fittingSize
            panel.window.setFrame(NSRect(origin: NSPoint(x: -4000, y: -4000), size: size), display: true)
            panel.window.orderFrontRegardless()
            panel.contentView.layoutSubtreeIfNeeded()
            panel.window.displayIfNeeded()
            write(panel.contentView, dark: dark, to: dir.appendingPathComponent("\(name)\(suffix).png"))
            panel.window.orderOut(nil)
        }

        // Bảng đề nghị của bộ soát lỗi, với dữ liệu mẫu.
        let suggest = Proofing.samplePanel()
        suggest.appearance = NSApp.appearance
        if let view = suggest.contentView {
            view.layoutSubtreeIfNeeded()
            suggest.displayIfNeeded()
            write(view, dark: dark, to: dir.appendingPathComponent("suggestion\(suffix).png"))
        }
        suggest.orderOut(nil)
        let whole = Proofing.sampleSentencePanel()
        whole.appearance = NSApp.appearance
        if let view = whole.contentView {
            view.layoutSubtreeIfNeeded()
            whole.displayIfNeeded()
            write(view, dark: dark, to: dir.appendingPathComponent("suggestion-sentence\(suffix).png"))
        }
        whole.orderOut(nil)

        for (name, image) in StatusIcon.all {
            write(image, scale: 8, dark: dark, to: dir.appendingPathComponent("status-\(name)\(suffix).png"))
        }
    }

    /// Vẽ view lên nền cửa sổ (thẻ của NSTabView trong suốt một phần, nhất là ở chế độ tối).
    private static func write(_ view: NSView, dark: Bool, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        (NSApp.appearance ?? view.effectiveAppearance).performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        // Màu nền cửa sổ chuẩn của macOS ở hai chế độ (ghi cứng: màu động không phân giải đúng ở đây).
        let background = dark ? NSColor(white: 0.196, alpha: 1) : NSColor(white: 0.925, alpha: 1)
        let out = NSImage(size: view.bounds.size, flipped: false) { rect in
            background.setFill()
            rect.fill()
            rep.draw(in: rect)
            return true
        }
        guard let tiff = out.tiffRepresentation, let flat = NSBitmapImageRep(data: tiff) else { return }
        try? flat.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Phóng to ảnh template trên nền thanh menu sáng/tối để nhìn rõ.
    private static func write(_ image: NSImage, scale: CGFloat, dark: Bool, to url: URL) {
        let size = NSSize(width: (image.size.width + 8) * scale, height: (image.size.height + 8) * scale)
        let out = NSImage(size: size, flipped: false) { rect in
            (dark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            rect.fill()
            let tinted = NSImage(size: image.size, flipped: false) { r in
                image.draw(in: r)
                (dark ? NSColor.white : NSColor.black).set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: rect.insetBy(dx: 4 * scale, dy: 4 * scale))
            return true
        }
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
