import AppKit
import QuartzCore
import VNKeyCore

/// Viên nhãn "VN - Telex" / "EN", cùng kiểu với nhãn báo bộ gõ mà macOS hiện cạnh con trỏ soạn thảo: viên
/// thuốc bo tròn hai đầu, nền là màu nhấn của hệ thống, chữ trắng đậm, không viền.
final class HUDPill: NSView {
    static let size = NSSize(width: 30, height: 20)
    private let label = NSTextField(labelWithString: "")

    override var wantsUpdateLayer: Bool { true }

    init(text: String) {
        super.init(frame: NSRect(origin: .zero, size: HUDPill.size))
        wantsLayer = true
        layer?.cornerRadius = HUDPill.size.height / 2
        label.font = .systemFont(ofSize: 11, weight: .bold)
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

    /// Kích thước vừa với chữ đang hiện: "EN" giữ cỡ gọn, nhãn dài hơn ("VN - Telex") thì giãn ngang.
    var fittingPillSize: NSSize {
        NSSize(width: max(HUDPill.size.width, ceil(label.intrinsicContentSize.width) + 16), height: HUDPill.size.height)
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
    private var size = HUDPill.size

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Không đổ bóng: nhãn của hệ thống phẳng, và bóng của cửa sổ trong suốt vẽ thành một viền khác màu.
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = pill
    }

    /// Hiện nhãn cạnh chỗ đang gõ. Chỉ hiện khi người dùng đang ở trong một ô nhập văn bản; đang ở chỗ khác
    /// (màn hình nền, danh sách tệp, nút bấm…) thì không hiện gì.
    func show(_ text: String) {
        pill.text = text
        pill.needsDisplay = true
        size = pill.fittingPillSize
        panel.setContentSize(size)
        generation += 1
        let g = generation
        if let p = origin() {
            present(at: p, g)
        } else {
            panel.orderOut(nil)
            // Ứng dụng Electron/Chromium chỉ dựng cây trợ năng sau khi được yêu cầu: thử lại một lần sau một nhịp.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, g == self.generation, let p = self.origin() else { return }
                self.present(at: p, g)
            }
        }
    }

    private func present(at point: NSPoint, _ g: Int) {
        panel.setFrameOrigin(point)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, g == self.generation else { return }
            NSAnimationContext.runAnimationGroup(
                { ctx in
                    ctx.duration = 0.25
                    self.panel.animator().alphaValue = 0
                },
                completionHandler: { if g == self.generation { self.panel.orderOut(nil) } })
        }
    }

    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// Nhãn lệch sang trái con trỏ chừng này, như nhãn báo bộ gõ của macOS (nó nằm gần chính giữa con trỏ).
    private static let leftShift: CGFloat = 14

    /// Vị trí của nhãn: ngay trên con trỏ soạn thảo, lệch trái một chút (nhãn của macOS hiện phía dưới, đặt ở
    /// trên để hai nhãn không chồng nhau); nếu ứng dụng chỉ cho biết khung của ô nhập thì ngay trên ô đó.
    /// nil = không ở trong ô nhập nào, không hiện nhãn. Ghi vào nhật ký cách đã dùng.
    private func origin() -> NSPoint? {
        let found = locate()
        Log.write("HUD vị trí=\(found.kind) \(found.note)")
        var p: NSPoint
        switch found.kind {
        case .caret:
            p = NSPoint(x: found.rect.minX - HUD.leftShift, y: found.rect.maxY + 4)
        case .field where found.isText:
            // Ô thấp (một dòng): ngay trên ô. Ô cao (khung soạn thảo): bên trong, góc dưới-trái.
            p = found.rect.height <= 60
                ? NSPoint(x: found.rect.minX + 4, y: found.rect.maxY + 4)
                : NSPoint(x: found.rect.minX + 12, y: found.rect.minY + 12)
        default:
            return nil
        }
        // Giữ nhãn nằm trọn trong màn hình chứa nó (con trỏ sát mép thì nhãn không bị cắt).
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(p) } ?? NSScreen.main
        if let v = screen?.visibleFrame {
            p.x = min(max(p.x, v.minX + 2), v.maxX - size.width - 2)
            p.y = min(max(p.y, v.minY + 2), v.maxY - size.height - 2)
        }
        return p
    }

    /// Chỗ đang gõ (toạ độ Cocoa) để đặt bảng clipboard ngay cạnh: con trỏ soạn thảo, hoặc ô nhập một dòng.
    /// nil = ứng dụng không cho biết. Phải hỏi TRƯỚC khi bảng nhận tiêu điểm.
    func typingAnchor() -> NSRect? {
        let found = locate()
        Log.write("CLIP vị trí=\(found.kind) \(found.note)")
        switch found.kind {
        case .caret: return found.rect
        case .field where found.isText && found.rect.height <= 60: return found.rect
        default: return nil
        }
    }

    private enum Kind { case caret, field, window, mouse }
    /// Các ứng dụng đã được yêu cầu bật cây trợ năng (mỗi tiến trình chỉ yêu cầu một lần).
    private var askedAccessibility: Set<pid_t> = []

    static func frame(of element: AXUIElement) -> NSRect? {
        var pos: CFTypeRef?, extent: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &extent) == .success,
            let pos, let extent, CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(extent) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &origin), AXValueGetValue(extent as! AXValue, .cgSize, &sz) else {
            return nil
        }
        return cocoa(CGRect(origin: origin, size: sz))
    }

    /// Ô đang nhận phím. Hỏi cả hệ thống trước; ứng dụng Electron/Chromium (Claude, Zalo, VS Code, Chrome…)
    /// thường không trả lời vì chúng chỉ dựng cây trợ năng khi có công cụ yêu cầu — khi đó hỏi thẳng ứng dụng
    /// đang ở trước và đặt cờ `AXManualAccessibility` để nó bắt đầu dựng (có hiệu lực cho lần hỏi sau).
    func focusedElement() -> (element: AXUIElement?, app: AXUIElement?, note: String) {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        {
            return (focused as! AXUIElement, nil, "")
        }
        guard let front = NSWorkspace.shared.frontmostApplication else { return (nil, nil, "không có ứng dụng ở trước") }
        let pid = front.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        {
            return (focused as! AXUIElement, app, "qua ứng dụng ")
        }
        var note = "ứng dụng không báo ô đang nhập"
        if askedAccessibility.insert(pid).inserted {
            let err = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            note += err == .success ? ", đã yêu cầu bật cây trợ năng" : ", không bật được cây trợ năng (\(err.rawValue))"
        }
        return (nil, app, note)
    }

    /// AX dùng gốc trên-trái của màn hình chính; Cocoa dùng gốc dưới-trái. Bỏ khung rỗng hoặc nằm ngoài mọi
    /// màn hình (vài ứng dụng trả về toàn số 0 hoặc toạ độ rác).
    static func cocoa(_ rect: CGRect) -> NSRect? {
        guard rect.height > 0, let primary = NSScreen.screens.first else { return nil }
        let r = NSRect(x: rect.minX, y: primary.frame.height - rect.maxY, width: rect.width, height: rect.height)
        return NSScreen.screens.contains { $0.frame.insetBy(dx: -2, dy: -2).intersects(r) } ? r : nil
    }

    static func rect(_ value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &r) ? r : nil
    }

    /// Tìm chỗ đang nhập qua Accessibility. Nhiều ứng dụng không trả lời được câu hỏi đầu, nên hỏi dần:
    /// 1. khung của vùng chọn (ứng dụng AppKit);
    /// 2. khung của ký tự đứng ngay trước con trỏ (khi vùng chọn rỗng trả về khung rỗng);
    /// 3. khung theo "text marker" (trang web trong Safari, Chrome và ứng dụng Electron);
    /// 4. khung của chính ô đang nhập.
    private func locate() -> (kind: Kind, rect: NSRect, note: String, isText: Bool) {
        let found = focusedElement()
        guard let element = found.element else {
            // Không có ô nào: ít nhất đặt nhãn trong cửa sổ đang gõ thay vì chạy theo chuột.
            var window: CFTypeRef?
            if let app = found.app,
                AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
                let window, CFGetTypeID(window) == AXUIElementGetTypeID(), let r = HUD.frame(of: window as! AXUIElement)
            {
                return (.window, r, "khung cửa sổ; \(found.note)", false)
            }
            return (.mouse, .zero, found.note, false)
        }
        AXUIElementSetMessagingTimeout(element, 0.15)
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? "?"

        // Có phải chỗ gõ được chữ không: ô nhập chuẩn, hoặc vùng soạn thảo của trang web (contenteditable thường
        // có vai trò AXGroup nhưng có "tổ tiên soạn thảo được" hoặc giá trị sửa được).
        var editable = HUD.textRoles.contains(role)
        if !editable {
            var ancestor: CFTypeRef?
            var settable: DarwinBoolean = false
            editable =
                (AXUIElementCopyAttributeValue(element, "AXEditableAncestor" as CFString, &ancestor) == .success && ancestor != nil)
                || (AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue)
        }
        guard editable else { return (.mouse, .zero, "không phải ô nhập role=\(role)", false) }

        func bounds(_ attribute: String, _ parameter: CFTypeRef) -> NSRect? {
            var out: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &out) == .success
            else { return nil }
            return HUD.rect(out).flatMap(HUD.cocoa)
        }

        var range: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
            let range, CFGetTypeID(range) == AXValueGetTypeID()
        {
            if let r = bounds(kAXBoundsForRangeParameterizedAttribute, range) {
                return (.caret, r, "\(found.note)vùng chọn role=\(role)", true)
            }
            var cf = CFRange(location: 0, length: 0)
            if AXValueGetValue(range as! AXValue, .cfRange, &cf), cf.location > 0 {
                var before = CFRange(location: cf.location - 1, length: 1)
                if let v = AXValueCreate(.cfRange, &before), let r = bounds(kAXBoundsForRangeParameterizedAttribute, v) {
                    // Con trỏ nằm ở mép phải của ký tự đứng trước nó.
                    return (.caret, NSRect(x: r.maxX, y: r.minY, width: 1, height: r.height), "ký tự trước role=\(role)", true)
                }
            }
        }
        var marker: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &marker) == .success, let marker,
            let r = bounds("AXBoundsForTextMarkerRange", marker)
        {
            return (.caret, r, "text marker role=\(role)", true)
        }
        if let r = HUD.frame(of: element) {
            return (.field, r, "\(found.note)khung ô role=\(role) \(Int(r.width))x\(Int(r.height))", true)
        }
        return (.mouse, .zero, "ứng dụng không cho biết vị trí role=\(role)", false)
    }
}
