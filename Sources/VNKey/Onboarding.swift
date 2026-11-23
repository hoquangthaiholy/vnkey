import AppKit

/// Cửa sổ hướng dẫn khi VNKey chưa có quyền Trợ năng: nói vì sao cần quyền, mở đúng chỗ trong Cài đặt hệ
/// thống, và tự báo "đã sẵn sàng" khi quyền được cấp. Cũng là nơi nói rõ nhật ký gỡ lỗi đang lưu gì.
final class OnboardingController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let status = NSTextField(labelWithString: "")
    private let primary = NSButton(title: "", target: nil, action: nil)
    private let steps = NSTextField(wrappingLabelWithString: "")
    private var ready = false

    static let width: CGFloat = 440

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: OnboardingController.width, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Bắt đầu với VNKey"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let heading = NSTextField(labelWithString: "VNKey cần quyền Trợ năng")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)

        let inner = OnboardingController.width - 48
        let why = NSTextField(
            wrappingLabelWithString:
                "Để bỏ dấu tiếng Việt trong mọi ứng dụng, VNKey phải đọc phím bạn gõ và gửi lại chữ đã có dấu. macOS chỉ cho phép việc này khi bạn bật VNKey trong mục Trợ năng.")
        why.preferredMaxLayoutWidth = inner
        steps.preferredMaxLayoutWidth = inner
        steps.textColor = .secondaryLabelColor

        status.font = .systemFont(ofSize: 13, weight: .medium)

        primary.target = self
        primary.action = #selector(primaryAction)
        primary.bezelStyle = .rounded
        primary.keyEquivalent = "\r"

        let logSwitch = NSSwitch()
        logSwitch.controlSize = .small
        logSwitch.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values." + Key.debugLog)
        logSwitch.setAccessibilityLabel("Ghi nhật ký gỡ lỗi")
        let logTitle = NSTextField(labelWithString: "Ghi nhật ký gỡ lỗi")
        let logDetail = NSTextField(
            wrappingLabelWithString:
                "Khi bật, VNKey lưu cả nội dung bạn gõ (trừ ô mật khẩu) vào một tệp trên máy để tìm lỗi. Không có gì được gửi đi. Bật tắt ở đây hoặc trong Cài đặt bất cứ lúc nào.")
        logDetail.font = .systemFont(ofSize: 11)
        logDetail.textColor = .secondaryLabelColor
        logDetail.preferredMaxLayoutWidth = inner - 60
        let logText = NSStackView(views: [logTitle, logDetail])
        logText.orientation = .vertical
        logText.alignment = .leading
        logText.spacing = 2
        let logRow = NSStackView(views: [logText, logSwitch])
        logRow.orientation = .horizontal
        logRow.alignment = .top
        logRow.spacing = 12

        let line = NSBox()
        line.boxType = .separator

        let stack = NSStackView(views: [icon, heading, why, steps, status, primary, line, logRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(16, after: primary)
        stack.setCustomSpacing(16, after: line)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: OnboardingController.width),
            line.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            logRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
        ])
        window.contentView = content
        update(ready: false)
        window.setContentSize(content.fittingSize)
        window.center()
    }

    var contentView: NSView { window.contentView! }

    /// Gọi định kỳ từ AppDelegate: đổi nội dung khi event tap đã chạy được.
    func update(ready now: Bool) {
        guard now != ready || status.stringValue.isEmpty else { return }
        ready = now
        if ready {
            status.stringValue = "✓ Đã sẵn sàng"
            status.textColor = .systemGreen
            steps.stringValue =
                "Biểu tượng V trên thanh menu cho biết đang gõ tiếng Việt, E là tiếng Anh. Nhấn ⌃⇧ (Control + Shift) rồi thả để đổi qua lại."
            primary.title = "Bắt đầu gõ"
        } else {
            status.stringValue = "Đang chờ bạn cấp quyền…"
            status.textColor = .secondaryLabelColor
            steps.stringValue =
                "1. Bấm nút bên dưới để mở Cài đặt hệ thống.\n2. Trong danh sách Trợ năng, bật công tắc cạnh VNKey.\n3. Quay lại đây: cửa sổ này tự báo khi xong."
            primary.title = "Mở Cài đặt hệ thống…"
        }
        if window.isVisible, let c = window.contentView {
            c.layoutSubtreeIfNeeded()
            window.setContentSize(c.fittingSize)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func primaryAction() {
        if ready {
            window.close()
        } else {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
