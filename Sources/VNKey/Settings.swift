import AppKit
import QuartzCore
import ServiceManagement
import VNKeyCore
import UniformTypeIdentifiers

// Cửa sổ cài đặt viết bằng AppKit thuần: Command Line Tools không kèm plugin macro của SwiftUI.

/// Nút ghi phím tắt: bấm rồi nhấn tổ hợp mới.
private final class HotkeyButton: NSButton {
    private var key = ""
    /// Khoá của phím tắt còn lại, để không nhận hai phím tắt trùng nhau.
    private var otherKey = ""
    private var monitor: Any?
    private var peak: UInt = 0

    convenience init(key: String, otherKey: String, label: String) {
        self.init(title: "", target: nil, action: #selector(toggle))
        self.key = key
        self.otherKey = otherKey
        setAccessibilityLabel("Phím tắt: " + label)
        target = self
        widthAnchor.constraint(equalToConstant: 150).isActive = true
        refresh()
    }

    func refresh() {
        title = Hotkey(string: UserDefaults.standard.string(forKey: key) ?? "")?.label ?? "—"
    }

    func set(_ h: Hotkey) {
        let other = Hotkey(string: UserDefaults.standard.string(forKey: otherKey) ?? "")
        if let problem = h.problem(other: other) {
            // Không nhận: báo lý do ngay trên nút rồi trở về phím tắt cũ.
            stop()
            NSSound.beep()
            title = problem == .duplicate ? "Trùng phím tắt kia" : "Cần thêm ⌃, ⌥ hoặc ⌘"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                if self?.monitor == nil { self?.refresh() }
            }
            return
        }
        UserDefaults.standard.set(h.string, forKey: key)
        stop()
    }

    @objc private func toggle() { monitor == nil ? start() : stop() }

    private func start() {
        title = "Nhấn tổ hợp phím…"
        hotkeyRecording = true; peak = 0
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [unowned self] e in
            let m = UInt(e.modifierFlags.rawValue) & Hotkey.modMask
            if e.type == .keyDown {
                if e.keyCode == 53 { stop(); return nil }
                guard m != 0 else { return nil }  // phải có ít nhất một phím bổ trợ
                var name = (e.charactersIgnoringModifiers ?? "").uppercased()
                if e.keyCode == 49 { name = "Space" }
                set(Hotkey(code: Int(e.keyCode), mods: m, keyLabel: name))
                return nil
            }
            if m != 0 {
                if m & peak == peak { peak = m }
            } else if peak.nonzeroBitCount >= 2 {  // chỉ phím bổ trợ: cần ít nhất hai phím
                set(Hotkey(code: -1, mods: peak, keyLabel: ""))
            } else {
                peak = 0
            }
            return e
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; hotkeyRecording = false
        refresh()
    }
}

/// Danh sách ứng dụng (lưu bằng bundle ID) hiện kèm biểu tượng và tên.
private final class AppTable: NSTableView {
    var onDelete: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { onDelete?() } else { super.keyDown(with: event) }
    }
}

private final class AppList: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let scroll = NSScrollView()
    private let table = AppTable()
    private let key: String
    /// Gọi khi số dòng đang chọn đổi (để bật/tắt nút Xoá).
    var onSelection: ((Int) -> Void)?
    private var items: [(id: String, name: String?, icon: NSImage)] = []

    init(key: String) {
        self.key = key
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 30
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.onDelete = { [unowned self] in removeSelected() }
        table.setAccessibilityLabel("Ứng dụng bắt đầu ở chế độ Anh")
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.heightAnchor.constraint(equalToConstant: 186).isActive = true
        reload()
    }

    func reload() {
        let ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        let generic = NSWorkspace.shared.icon(for: .applicationBundle)
        items = ids.map { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                return (id, nil, generic)
            }
            return (id, FileManager.default.displayName(atPath: url.path), NSWorkspace.shared.icon(forFile: url.path))
        }
        // Ứng dụng đã cài lên trước, theo tên; chưa cài xuống dưới.
        .sorted { a, b in
            switch (a.name, b.name) {
            case let (x?, y?): return x.localizedCaseInsensitiveCompare(y) == .orderedAscending
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.id < b.id
            }
        }
        table.reloadData()
        onSelection?(table.selectedRowIndexes.count)
    }

    func tableViewSelectionDidChange(_ notification: Notification) { onSelection?(table.selectedRowIndexes.count) }

    func add(_ ids: [String]) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        for id in ids where !list.contains(id) { list.append(id) }
        UserDefaults.standard.set(list, forKey: key)
        reload()
    }

    /// Bỏ danh sách đã sửa: giá trị mặc định đã đăng ký (các ứng dụng terminal) có hiệu lực trở lại.
    func restoreDefaults() {
        UserDefaults.standard.removeObject(forKey: key)
        reload()
    }

    func removeSelected() {
        let gone = Set(table.selectedRowIndexes.map { items[$0].id })
        guard !gone.isEmpty else { return }
        let rest = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { !gone.contains($0) }
        UserDefaults.standard.set(rest, forKey: key)
        reload()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let icon = NSImageView(image: item.icon)
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
        let text = NSMutableAttributedString(
            string: item.name ?? item.id,
            attributes: [.foregroundColor: item.name == nil ? NSColor.secondaryLabelColor : NSColor.labelColor])
        text.append(
            NSAttributedString(
                string: item.name == nil ? "   chưa cài trên máy này" : "   \(item.id)",
                attributes: [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                ]))
        let label = NSTextField(labelWithAttributedString: text)
        label.lineBreakMode = .byTruncatingTail
        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        return row
    }
}

/// Mọi khoảng cách của cửa sổ Cài đặt, theo lưới 4pt. Đổi ở đây, đừng rải số lẻ trong mã.
private enum Metrics {
    static let pageMargin: CGFloat = 20  // lề trái/phải/dưới của thẻ
    static let pageTop: CGFloat = 16
    static let sectionGap: CGFloat = 20  // giữa hai nhóm
    static let titleGap: CGFloat = 8  // tiêu đề nhóm -> khung
    static let noteGap: CGFloat = 6  // khung -> chú thích
    static let rowInset: CGFloat = 14  // lề trái/phải trong khung
    static let rowPadding: CGFloat = 10  // lề trên/dưới của một dòng
    static let rowMinHeight: CGFloat = 40
    static let labelGap: CGFloat = 2  // tên -> mô tả
    static let controlGap: CGFloat = 8
}

/// Nhãn nhiều dòng tự tính lại chiều cao theo bề rộng thật sau khi dàn trang. Nhãn chuẩn của AppKit tính
/// chiều cao trước khi biết bề rộng, nên dòng mô tả dài bị dồn sát mép khung.
private final class WrappingLabel: NSTextField {
    override func layout() {
        super.layout()
        if abs(preferredMaxLayoutWidth - bounds.width) > 0.5 {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}

/// Khung bo góc chứa một nhóm dòng cài đặt, kiểu System Settings.
private final class Card: NSView {
    override var wantsUpdateLayer: Bool { true }

    init(rows: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        var constraints = [
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        for (i, row) in rows.enumerated() {
            if i > 0 {  // đường kẻ mảnh giữa các dòng, thụt vào cho thẳng với chữ
                let line = NSBox()
                line.boxType = .custom
                line.borderWidth = 0
                line.fillColor = .separatorColor
                let holder = NSView()
                line.translatesAutoresizingMaskIntoConstraints = false
                holder.addSubview(line)
                constraints += [
                    line.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: Metrics.rowInset),
                    line.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                    line.topAnchor.constraint(equalTo: holder.topAnchor), line.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
                    holder.heightAnchor.constraint(equalToConstant: 1),
                ]
                stack.addArrangedSubview(holder)
                constraints.append(holder.widthAnchor.constraint(equalTo: stack.widthAnchor))
            }
            stack.addArrangedSubview(row)
            constraints.append(row.widthAnchor.constraint(equalTo: stack.widthAnchor))
        }
        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

/// Thanh thẻ kiểu Cài đặt của macOS. Khi chuyển thẻ: nội dung đổi ngay (không mờ chuyển), cửa sổ trượt tới
/// chiều cao mới (mép trên đứng yên).
private final class SettingsTabs: NSTabViewController {
    static let duration: TimeInterval = 0.22
    static let windowTitle = "Cài đặt VNKey"
    /// Tắt khi chọn thẻ bằng mã mà cần kích thước cuối ngay (chụp giao diện): một chuyển động đang dở sẽ
    /// tranh chấp với lần đặt khung trực tiếp, nhất là khi màn hình đang ngủ và chuyển động không chạy.
    var animatesResize = true

    override func viewDidLoad() {
        super.viewDidLoad()
        transitionOptions = []  // không mờ chuyển giữa hai thẻ: người dùng thấy rối
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animated: animatesResize)
    }

    func fitWindow(animated: Bool) {
        guard let window = view.window, let page = tabView.selectedTabViewItem?.view else { return }
        page.layoutSubtreeIfNeeded()
        page.layoutSubtreeIfNeeded()  // lượt hai: nhãn nhiều dòng vừa biết bề rộng thật ở lượt một
        // Chiều cao tính từ chính nội dung của thẻ (khối xếp dọc bên trong), không hỏi thẻ: thẻ không được
        // giữ chiều cao tối thiểu, nếu không thẻ cũ (còn nằm đó suốt lúc mờ chuyển) sẽ chặn cửa sổ co lại.
        let inner = page.subviews.first?.fittingSize.height ?? page.fittingSize.height
        let height = inner + Metrics.pageTop + Metrics.pageMargin
        let content = NSRect(origin: .zero, size: NSSize(width: SettingsController.width, height: height))
        var frame = window.frameRect(forContentRect: content)
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)  // giữ mép trên
        window.title = SettingsTabs.windowTitle  // thẻ đang chọn đã hiện trên thanh công cụ
        // Tôn trọng "Giảm chuyển động" của hệ thống.
        guard animated, window.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SettingsTabs.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }
}

final class SettingsController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 540
    /// Đánh dấu một view cần giãn hết chiều ngang của thẻ.
    fileprivate static let wide = NSUserInterfaceItemIdentifier("wide")
    fileprivate static let titleID = NSUserInterfaceItemIdentifier("title")
    fileprivate static let noteID = NSUserInterfaceItemIdentifier("note")
    let window: NSWindow
    private let tabs = SettingsTabs()
    private let defaults = UserDefaults.standard
    private var tables: [EntryTable] = []
    private var appList: AppList?
    private var hotkeyButtons: [HotkeyButton] = []
    private var methodControl: NSSegmentedControl?
    /// Các công tắc chỉ có nghĩa với Telex: mờ đi khi chọn VNI.
    private var telexSwitches: [NSSwitch] = []
    private var toneControl: NSSegmentedControl?
    private var loginSwitch: NSSwitch?
    private var removeButton: NSButton?
    private var runningAppsMenu: NSPopUpButton?

    override init() {
        window = NSWindow(contentViewController: tabs)
        super.init()
        tabs.tabStyle = .toolbar
        for (title, symbol, view) in [
            ("Chung", "gearshape", general()), ("Gõ", "keyboard", typing()), ("Việt & Anh", "character.bubble", mixed()),
            ("Gõ tắt", "text.badge.plus", shortcuts()), ("Đã nhớ", "bookmark", remembered()),
            ("Ứng dụng", "macwindow.on.rectangle", apps()),
        ] {
            let controller = NSViewController()
            controller.view = view
            let item = NSTabViewItem(viewController: controller)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.titleVisibility = .visible
        window.title = SettingsTabs.windowTitle
        window.isReleasedWhenClosed = false
        window.delegate = self
        tabs.fitWindow(animated: false)
        window.center()
    }

    /// Số thẻ và cách chọn thẻ, dùng cho chế độ chụp giao diện.
    var tabCount: Int { tabs.tabViewItems.count }
    func selectTab(_ index: Int, animated: Bool = false) {
        tabs.animatesResize = animated
        tabs.selectedTabViewItemIndex = index  // tự gọi fitWindow qua didSelect
        tabs.animatesResize = true
        if !animated { tabs.fitWindow(animated: false) }
    }
    var contentView: NSView { tabs.view }

    func windowDidBecomeKey(_ notification: Notification) { reload() }
    func windowWillClose(_ notification: Notification) { hotkeyButtons.forEach { $0.stop() } }

    func reload() {
        tables.forEach { $0.reload() }
        appList?.reload()
        hotkeyButtons.forEach { $0.refresh() }
        showMethod()
        toneControl?.selectedSegment = defaults.bool(forKey: Key.modernTone) ? 1 : 0
        if #available(macOS 13.0, *) { loginSwitch?.state = SMAppService.mainApp.status == .enabled ? .on : .off }
    }

    // MARK: - Thành phần

    /// Một thẻ: các nhóm xếp dọc, cao vừa đủ nội dung. Khoảng cách tính theo loại phần tử đứng cạnh nhau
    /// (xem `Metrics`), nên thêm/bớt phần tử không làm lệch nhịp.
    private func page(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Metrics.titleGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        // Mép dưới để mức ưu tiên thấp: nội dung dồn lên trên, và thẻ KHÔNG đòi chiều cao tối thiểu — trong
        // lúc cửa sổ trượt giữa hai chiều cao, thẻ được phép tràn tạm thời thay vì chặn cửa sổ co lại.
        let bottom = stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -Metrics.pageMargin)
        bottom.priority = .defaultLow
        var constraints = [
            container.widthAnchor.constraint(equalToConstant: SettingsController.width),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.pageMargin),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.pageMargin),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.pageTop),
            bottom,
        ]
        for v in views where v is Card || v is NSScrollView || v.identifier == SettingsController.wide {
            constraints.append(v.widthAnchor.constraint(equalTo: stack.widthAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        for (i, v) in views.enumerated() where i > 0 {
            let before = views[i - 1]
            if v.identifier == SettingsController.titleID {
                stack.setCustomSpacing(Metrics.sectionGap, after: before)
            } else if v.identifier == SettingsController.noteID {
                stack.setCustomSpacing(Metrics.noteGap, after: before)
            }
        }
        return container
    }

    /// Tiêu đề của một nhóm.
    private func title(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.identifier = SettingsController.titleID
        return l
    }

    /// Chú thích nhỏ dưới một nhóm.
    private func note(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = SettingsController.width - 2 * Metrics.pageMargin
        l.identifier = SettingsController.noteID
        return l
    }

    /// Một dòng trong nhóm: tên (và mô tả) bên trái, điều khiển bên phải. Phần chữ chiếm hết chỗ trống còn
    /// lại và mô tả tự xuống dòng theo bề rộng đó (không đặt bề rộng cố định: điều khiển rộng hẹp khác nhau).
    private func row(_ name: String, _ detail: String? = nil, _ controls: NSView...) -> NSView {
        let label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        let text = NSStackView(views: [label])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = Metrics.labelGap
        if let detail {
            let d = WrappingLabel(wrappingLabelWithString: detail)
            d.font = .systemFont(ofSize: 11)
            d.textColor = .secondaryLabelColor
            d.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            d.setContentHuggingPriority(.defaultLow, for: .horizontal)
            text.addArrangedSubview(d)
            d.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
        }
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for c in controls {
            c.setContentHuggingPriority(.required, for: .horizontal)
            c.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let line = NSStackView(views: [text] + controls)
        line.orientation = .horizontal
        line.alignment = .centerY
        line.distribution = .fill
        line.spacing = Metrics.controlGap
        line.setCustomSpacing(Metrics.rowInset, after: text)  // chữ không dính sát điều khiển
        line.edgeInsets = NSEdgeInsets(
            top: Metrics.rowPadding, left: Metrics.rowInset, bottom: Metrics.rowPadding, right: Metrics.rowInset)
        // Dòng xếp theo tâm dọc nên lề trên/dưới của stack không tự giữ: ép phần chữ cách mép đúng một nhịp.
        NSLayoutConstraint.activate([
            line.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.rowMinHeight),
            text.topAnchor.constraint(greaterThanOrEqualTo: line.topAnchor, constant: Metrics.rowPadding),
            text.bottomAnchor.constraint(lessThanOrEqualTo: line.bottomAnchor, constant: -Metrics.rowPadding),
        ])
        return line
    }

    /// Công tắc gắn thẳng vào UserDefaults; `dependsOn`: mờ đi khi tuỳ chọn cha đang tắt.
    private func toggle(_ name: String, _ detail: String? = nil, key: String, dependsOn parent: String? = nil) -> NSView {
        let s = NSSwitch()
        s.controlSize = .small
        s.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values." + key)
        if let parent { s.bind(.enabled, to: NSUserDefaultsController.shared, withKeyPath: "values." + parent) }
        s.setAccessibilityLabel(name)
        return row(name, detail, s)
    }

    private func showMethod() {
        let vni = defaults.string(forKey: Key.method) == "vni"
        methodControl?.selectedSegment = vni ? 1 : 0
        telexSwitches.forEach { $0.isEnabled = !vni }
    }

    // MARK: - Các thẻ

    private func general() -> NSView {
        func hotkey(_ name: String, _ detail: String?, _ key: String) -> NSView {
            let b = HotkeyButton(
                key: key, otherKey: key == Key.toggleHotkey ? Key.restoreHotkey : Key.toggleHotkey, label: name)
            hotkeyButtons.append(b)
            let reset = NSButton(
                image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Về mặc định")!,
                target: self, action: #selector(resetHotkey(_:)))
            reset.bezelStyle = .circular
            reset.toolTip = "Về mặc định"
            reset.tag = hotkeyButtons.count - 1
            return row(name, detail, b, reset)
        }
        let login = NSSwitch()
        login.controlSize = .small
        login.target = self
        login.action = #selector(toggleLogin(_:))
        login.setAccessibilityLabel("Mở cùng lúc đăng nhập")
        loginSwitch = login
        let openLog = NSButton(title: "Mở tệp", target: self, action: #selector(openLog))
        openLog.controlSize = .small
        let logSwitch = NSSwitch()
        logSwitch.controlSize = .small
        logSwitch.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values." + Key.debugLog)
        logSwitch.setAccessibilityLabel("Ghi nhật ký gỡ lỗi")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "bản phát triển"

        var system: [NSView] = []
        if #available(macOS 13.0, *) { system.append(row("Mở cùng lúc đăng nhập", nil, login)) }
        system.append(
            row("Ghi nhật ký gỡ lỗi", "Lưu cả nội dung bạn gõ (trừ ô mật khẩu) vào máy này để tìm lỗi.", openLog, logSwitch))
        return page([
            title("Phím tắt"),
            Card(rows: [
                hotkey("Bật/tắt tiếng Việt", nil, Key.toggleHotkey),
                hotkey("Đổi từ vừa gõ", "Phím gốc ↔ tiếng Việt, và nhớ cho lần sau.", Key.restoreHotkey),
            ]),
            note("Bấm vào ô phím tắt rồi nhấn tổ hợp mới; Esc để huỷ. Có thể dùng riêng phím bổ trợ như ⌃⇧: nhấn giữ rồi thả."),
            title("Hiển thị"),
            Card(rows: [toggle("Hiện nhãn VN/EN cạnh con trỏ khi đổi chế độ", key: Key.showHUD)]),
            title("Hệ thống"),
            Card(rows: system),
            note("VNKey \(version)"),
        ])
    }

    private func typing() -> NSView {
        let method = NSSegmentedControl(
            labels: ["Telex", "VNI"], trackingMode: .selectOne, target: self, action: #selector(pickMethod(_:)))
        methodControl = method
        method.setAccessibilityLabel("Kiểu gõ")
        func telexSwitch(_ name: String, _ detail: String, _ key: String) -> NSView {
            let s = NSSwitch()
            s.controlSize = .small
            s.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values." + key)
            s.setAccessibilityLabel(name)
            telexSwitches.append(s)
            return row(name, detail, s)
        }
        let tone = NSSegmentedControl(
            labels: ["hòa, thủy", "hoà, thuỷ"], trackingMode: .selectOne, target: self, action: #selector(pickTone(_:)))
        toneControl = tone
        tone.setAccessibilityLabel("Vị trí dấu thanh")
        return page([
            title("Cơ bản"),
            Card(rows: [
                row("Kiểu gõ", nil, method),
                telexSwitch("Phím “w” đứng riêng thành “ư”", "Chỉ với Telex. Gõ “ww” để ra chữ w.", Key.standaloneW),
                telexSwitch("Phím [ ] thành “ơ” “ư”", "Chỉ với Telex. Gõ lặp “[[” để ra dấu ngoặc.", Key.bracketKeys),
                row("Vị trí dấu thanh", "Ở nguyên âm đầu (cũ) hay nguyên âm sau (mới).", tone),
            ]),
            title("Tự động"),
            Card(rows: [
                toggle("Viết hoa đầu câu", "Sau . ! ? hoặc xuống dòng. Xoá lùi rồi gõ lại để giữ chữ thường.", key: Key.autoCapitalize),
                toggle("Xoá khoảng trắng thừa trước dấu câu", "Áp dụng cho , . ; ! ?", key: Key.tidyPunctuation),
            ]),
        ])
    }

    private func remembered() -> NSView {
        let learned = EntryTable(
            columns: [
                .text(title: "Chuỗi phím", placeholder: "vd: this", width: nil),
                .choice(title: "Luôn hiện", options: ["Phím gốc", "Tiếng Việt"], width: 120),
            ],
            height: 240, label: "Từ đã nhớ", searchable: true,
            load: { [defaults] in
                ListFormat.learnedRows(
                    raw: defaults.stringArray(forKey: Key.preferRaw) ?? [], vn: defaults.stringArray(forKey: Key.preferVN) ?? [])
            },
            save: { [defaults] rows in
                let r = ListFormat.learned(fromRows: rows)
                if r.raw != (defaults.stringArray(forKey: Key.preferRaw) ?? []).sorted() { defaults.set(r.raw.sorted(), forKey: Key.preferRaw) }
                if r.vn != (defaults.stringArray(forKey: Key.preferVN) ?? []).sorted() { defaults.set(r.vn.sorted(), forKey: Key.preferVN) }
                return ("\(r.raw.count + r.vn.count) từ", false)
            })
        tables.append(learned)
        learned.view.identifier = SettingsController.wide
        return page([
            title("Từ đã nhớ"),
            learned.view,
            note("VNKey thêm vào đây mỗi lần bạn dùng phím “Đổi từ vừa gõ” hoặc gõ lại một từ vừa xoá. “Phím gốc”: từ luôn hiện đúng như đã gõ; “Tiếng Việt”: luôn bỏ dấu. Bấm đúp để sửa; xoá dòng để quên."),
        ])
    }

    private func mixed() -> NSView {
        return page([
            title("Xen kẽ tiếng Anh"),
            Card(rows: [
                toggle("Tự trả lại từ không phải tiếng Việt", "user, string, data… hiện đúng như bạn đã gõ.", key: Key.autoRestore),
                toggle(
                    "Đoán theo ngữ cảnh", "Sau hai từ tiếng Anh liên tiếp, từ mơ hồ như this, test cũng giữ tiếng Anh.",
                    key: Key.contextAware, dependsOn: Key.autoRestore),
                toggle(
                    "Sửa gõ đảo hai phím liền nhau", "tieegns → tiếng. Chỉ sửa khi ra đúng một từ có trong từ điển.",
                    key: Key.fixTransposition, dependsOn: Key.autoRestore),
                toggle(
                    "Tự nhớ khi bạn gõ lại", "Xoá ngay từ vừa gõ rồi gõ lại y nguyên: VNKey đổi sang dạng còn lại và nhớ cho lần sau.",
                    key: Key.learnFromRetype, dependsOn: Key.autoRestore),
                toggle("Giữ nguyên trong ngữ cảnh code", "Ngay sau @ # / \\ . _ : $ ~ = hoặc chữ số: email, đường dẫn, tên biến.", key: Key.codeAware),
            ]),
            title("Chữ teen"),
            Card(rows: [toggle("Cho phép f, j, w, z đứng đầu từ", "zậy, jờ, dzô, fải…", key: Key.teen)]),
        ])
    }

    private func shortcuts() -> NSView {
        let macros = EntryTable(
            columns: [
                .text(title: "Từ tắt", placeholder: "vd: vn", width: 110),
                .text(title: "Nội dung", placeholder: "vd: Việt Nam", width: nil),
            ],
            height: 196, label: "Danh sách gõ tắt", searchable: true,
            load: { [defaults] in ListFormat.rows(from: defaults.dictionary(forKey: Key.macros) as? [String: String] ?? [:]) },
            save: { [defaults] rows in
                let r = ListFormat.macros(fromRows: rows)
                if r.macros != (defaults.dictionary(forKey: Key.macros) as? [String: String] ?? [:]) {
                    defaults.set(r.macros, forKey: Key.macros)
                }
                return r.skipped == 0
                    ? ("\(r.macros.count) mục", false)
                    : ("\(r.macros.count) mục · \(r.skipped) dòng chưa dùng được: cần đủ hai ô, từ tắt chỉ gồm chữ cái", true)
            })
        tables.append(macros)
        macros.view.identifier = SettingsController.wide
        return page([
            title("Gõ tắt của bạn"),
            macros.view,
            note("Gõ từ tắt rồi nhấn dấu cách hoặc dấu câu để bung ra; viết hoa chữ đầu thì kết quả cũng viết hoa. Bấm đúp vào ô để sửa."),
            title("Có sẵn"),
            Card(rows: [toggle("Bung viết tắt teen", "ko → không, dc → được, j → gì, ntn → như thế nào…", key: Key.expandTeen)]),
        ])
    }

    private func apps() -> NSView {
        let list = AppList(key: Key.excludedApps)
        appList = list
        let add = NSButton(title: "Thêm ứng dụng…", target: self, action: #selector(addApp))
        // Nút dạng menu kéo xuống: liệt kê ứng dụng đang mở, dựng lại mỗi lần bấm.
        let running = NSPopUpButton(frame: .zero, pullsDown: true)
        running.addItem(withTitle: "Thêm ứng dụng đang mở")
        NotificationCenter.default.addObserver(
            self, selector: #selector(fillRunningApps(_:)), name: NSPopUpButton.willPopUpNotification, object: running)
        runningAppsMenu = running
        let remove = NSButton(title: "Xoá", target: self, action: #selector(removeApps))
        remove.isEnabled = false
        remove.toolTip = "Xoá các ứng dụng đang chọn (phím Delete)"
        removeButton = remove
        list.onSelection = { [weak remove] n in remove?.isEnabled = n > 0 }
        let restore = NSButton(title: "Về mặc định", target: self, action: #selector(restoreApps))
        restore.toolTip = "Trở lại danh sách ứng dụng terminal ban đầu"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [add, running, remove, spacer, restore])
        buttons.orientation = .horizontal
        buttons.spacing = Metrics.controlGap
        buttons.identifier = SettingsController.wide
        return page([
            title("Theo từng ứng dụng"),
            Card(rows: [
                toggle(
                    "Nhớ chế độ Việt/Anh riêng cho từng ứng dụng", "Mỗi ứng dụng trở lại chế độ bạn chọn lần cuối ở đó.",
                    key: Key.perApp),
                toggle("Sửa lặp chữ ở ô có gợi ý", "Thanh địa chỉ trình duyệt, Spotlight.", key: Key.fixBrowser),
            ]),
            title("Bắt đầu ở chế độ Anh"),
            list.scroll,
            buttons,
            note("Mỗi lần chuyển sang các ứng dụng này VNKey tự về chế độ Anh; vẫn bật lại được bằng phím tắt."),
        ])
    }

    // MARK: - Hành động

    @objc private func pickMethod(_ sender: NSSegmentedControl) {
        defaults.set(sender.selectedSegment == 1 ? "vni" : "telex", forKey: Key.method)
        showMethod()
    }

    @objc private func pickTone(_ sender: NSSegmentedControl) {
        defaults.set(sender.selectedSegment == 1, forKey: Key.modernTone)
    }

    @objc private func resetHotkey(_ sender: NSButton) {
        hotkeyButtons[sender.tag].set(sender.tag == 0 ? .defaultToggle : .defaultRestore)
    }

    @objc private func toggleLogin(_ sender: NSSwitch) {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do { if sender.state == .on { try service.register() } else { try service.unregister() } } catch {
            Log.write("LOGIN ITEM lỗi: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Không đổi được thiết lập mở cùng lúc đăng nhập"
            alert.informativeText =
                "\(error.localizedDescription)\n\nBạn có thể tự bật trong Cài đặt hệ thống › Cài đặt chung › Mục đăng nhập."
            alert.beginSheetModal(for: window)
        }
        sender.state = service.status == .enabled ? .on : .off
    }

    @objc private func openLog() { NSWorkspace.shared.activateFileViewerSelecting([Log.url]) }

    @objc private func removeApps() { appList?.removeSelected() }

    @objc private func restoreApps() { appList?.restoreDefaults() }

    @objc private func fillRunningApps(_ note: Notification) {
        guard let button = runningAppsMenu, let menu = button.menu else { return }
        while menu.items.count > 1 { menu.removeItem(at: 1) }
        let have = Set(defaults.stringArray(forKey: Key.excludedApps) ?? [])
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !have.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
        if apps.isEmpty {
            let none = NSMenuItem(title: "Không còn ứng dụng nào để thêm", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for app in apps {
            let item = NSMenuItem(title: app.localizedName ?? app.bundleIdentifier!, action: #selector(addRunningApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.bundleIdentifier
            if let icon = app.icon?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }
    }

    @objc private func addRunningApp(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { appList?.add([id]) }
    }

    @objc private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        appList?.add(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }
}
