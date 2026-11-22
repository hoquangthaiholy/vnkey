import AppKit

/// Nhãn nhỏ "VN"/"EN" hiện thoáng qua cạnh con trỏ soạn thảo khi đổi chế độ.
final class HUD {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var generation = 0
    private let size = NSSize(width: 46, height: 28)

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 8
        bg.layer?.masksToBounds = true
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 5, width: size.width, height: 18)
        bg.addSubview(label)
        panel.contentView = bg
    }

    func show(_ text: String) {
        label.stringValue = text
        panel.setFrameOrigin(origin())
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        generation += 1
        let g = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, g == self.generation else { return }
            NSAnimationContext.runAnimationGroup(
                { ctx in
                    ctx.duration = 0.25
                    self.panel.animator().alphaValue = 0
                },
                completionHandler: { if g == self.generation { self.panel.orderOut(nil) } })
        }
    }

    /// Ngay dưới con trỏ soạn thảo nếu ứng dụng cho biết vị trí, không thì cạnh con trỏ chuột.
    private func origin() -> NSPoint {
        if let r = caretRect() { return NSPoint(x: r.minX, y: r.minY - size.height - 4) }
        let m = NSEvent.mouseLocation
        return NSPoint(x: m.x + 12, y: m.y - size.height - 12)
    }

    /// Vị trí con trỏ soạn thảo (toạ độ Cocoa) lấy qua Accessibility; nhiều app Electron không trả về.
    private func caretRect() -> NSRect? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
            let range
        else { return nil }
        var bounds: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
            let bounds, CFGetTypeID(bounds) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0,
            let primary = NSScreen.screens.first
        else { return nil }
        // AX dùng gốc trên-trái của màn hình chính; Cocoa dùng gốc dưới-trái.
        return NSRect(x: rect.minX, y: primary.frame.height - rect.maxY, width: rect.width, height: rect.height)
    }
}
