import AppKit

/// Viên nhãn "VN"/"EN": nền là màu nhấn mà người dùng chọn cho macOS, chữ trắng.
final class HUDPill: NSView {
    static let size = NSSize(width: 32, height: 20)
    private let label = NSTextField(labelWithString: "")

    override var wantsUpdateLayer: Bool { true }

    init(text: String) {
        super.init(frame: NSRect(origin: .zero, size: HUDPill.size))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor), label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        self.text = text
    }

    required init?(coder: NSCoder) { fatalError() }

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    /// Gọi lại mỗi khi giao diện đổi, nên nhãn theo ngay khi người dùng đổi màu nhấn trong Cài đặt hệ thống.
    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlAccentColor.cgColor
    }
}

/// Nhãn nhỏ "VN"/"EN" hiện thoáng qua cạnh con trỏ soạn thảo khi đổi chế độ.
final class HUD {
    private let panel: NSPanel
    private let pill = HUDPill(text: "")
    private var generation = 0
    private let size = HUDPill.size

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Không đổ bóng: bóng của cửa sổ trong suốt vẽ thành một viền khác màu quanh nhãn.
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = pill
    }

    func show(_ text: String) {
        pill.text = text
        pill.needsDisplay = true
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
        var p: NSPoint
        if let r = caretRect() {
            p = NSPoint(x: r.minX, y: r.minY - size.height - 3)
        } else {
            let m = NSEvent.mouseLocation
            p = NSPoint(x: m.x + 10, y: m.y - size.height - 10)
        }
        // Giữ nhãn nằm trọn trong màn hình chứa nó (con trỏ sát mép dưới/phải thì nhãn không bị cắt).
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(p) } ?? NSScreen.main
        if let v = screen?.visibleFrame {
            p.x = min(max(p.x, v.minX + 2), v.maxX - size.width - 2)
            p.y = min(max(p.y, v.minY + 2), v.maxY - size.height - 2)
        }
        return p
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
