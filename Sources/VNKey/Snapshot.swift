import AppKit

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
            settings.selectTab(i, animated: true)
            // Đợi chuyển động đổi thẻ chạy xong: ảnh phản ánh đúng trạng thái cuối mà người dùng thấy.
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            window.layoutIfNeeded()
            window.displayIfNeeded()
            write(settings.contentView, dark: dark, to: dir.appendingPathComponent("settings-\(i + 1)\(suffix).png"))
        }
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
        for text in ["VN", "EN"] {
            let pill = HUDPill(text: text)
            let holder = NSWindow(
                contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: HUDPill.size), styleMask: .borderless,
                backing: .buffered, defer: false)
            holder.contentView = pill
            holder.orderFrontRegardless()
            pill.layoutSubtreeIfNeeded()
            pill.displayIfNeeded()
            if let rep = pill.bitmapImageRepForCachingDisplay(in: pill.bounds) {
                pill.cacheDisplay(in: pill.bounds, to: rep)
                let big = NSImage(size: NSSize(width: HUDPill.size.width * 6 + 48, height: HUDPill.size.height * 6 + 48), flipped: false) { r in
                    (dark ? NSColor(white: 0.15, alpha: 1) : NSColor.white).setFill()
                    r.fill()
                    NSGraphicsContext.current?.imageInterpolation = .none
                    rep.draw(in: r.insetBy(dx: 24, dy: 24))
                    return true
                }
                if let tiff = big.tiffRepresentation, let out = NSBitmapImageRep(data: tiff) {
                    try? out.representation(using: .png, properties: [:])?.write(
                        to: dir.appendingPathComponent("hud-\(text.lowercased())\(suffix).png"))
                }
            }
            holder.orderOut(nil)
        }

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
