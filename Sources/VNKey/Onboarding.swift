import AppKit

/// Cửa sổ hướng dẫn khi VNKey chưa có quyền Trợ năng: nói vì sao cần quyền, mở đúng chỗ trong Cài đặt hệ
/// thống, và tự báo "đã sẵn sàng" khi quyền được cấp.
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
        window.title = L("Bắt đầu với VNKey", "Getting Started with VNKey")
        window.isReleasedWhenClosed = false
        window.delegate = self

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let heading = NSTextField(labelWithString: L("VNKey cần quyền Trợ năng", "VNKey needs Accessibility permission"))
        heading.font = .systemFont(ofSize: 17, weight: .semibold)

        let inner = OnboardingController.width - 48
        let why = NSTextField(
            wrappingLabelWithString:
                L("Để bỏ dấu tiếng Việt trong mọi ứng dụng, VNKey phải đọc phím bạn gõ và gửi lại chữ đã có dấu. macOS chỉ cho phép việc này khi bạn bật VNKey trong mục Trợ năng.", "To add Vietnamese marks in every app, VNKey has to read the keys you type and send back accented text. macOS only allows this once you turn VNKey on under Accessibility."))
        why.preferredMaxLayoutWidth = inner
        steps.preferredMaxLayoutWidth = inner
        steps.textColor = .secondaryLabelColor

        status.font = .systemFont(ofSize: 13, weight: .medium)

        primary.target = self
        primary.action = #selector(primaryAction)
        primary.bezelStyle = .rounded
        primary.keyEquivalent = "\r"

        let stack = NSStackView(views: [icon, heading, why, steps, status, primary])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: OnboardingController.width),
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
            status.stringValue = L("✓ Đã sẵn sàng", "✓ Ready")
            status.textColor = .systemGreen
            steps.stringValue =
                L("Biểu tượng V trên thanh menu cho biết đang gõ tiếng Việt, E là tiếng Anh. Nhấn ⌃⇧ (Control + Shift) rồi thả để đổi qua lại.", "The V icon in the menu bar means you are typing Vietnamese, E means English. Press and release ⌃⇧ (Control + Shift) to switch.")
            primary.title = L("Bắt đầu gõ", "Start Typing")
        } else {
            status.stringValue = L("Đang chờ bạn cấp quyền…", "Waiting for permission…")
            status.textColor = .secondaryLabelColor
            steps.stringValue =
                L("1. Bấm nút bên dưới để mở Cài đặt hệ thống.\n2. Trong danh sách Trợ năng, bật công tắc cạnh VNKey.\n3. Quay lại đây: cửa sổ này tự báo khi xong.", "1. Click the button below to open System Settings.\n2. In the Accessibility list, turn on the switch next to VNKey.\n3. Come back here: this window tells you when it is done.")
            primary.title = L("Mở Cài đặt hệ thống…", "Open System Settings…")
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
