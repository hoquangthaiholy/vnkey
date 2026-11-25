import AppKit
import QuartzCore
import ServiceManagement
import VNEngine
import VNKeyCore
import UniformTypeIdentifiers

// Cửa sổ cài đặt viết bằng AppKit thuần: Command Line Tools không kèm plugin macro của SwiftUI.

/// Nút ghi phím tắt: bấm rồi nhấn tổ hợp mới.
private final class HotkeyButton: NSButton {
    private var key = ""
    /// Khoá của các phím tắt còn lại, để không nhận hai phím tắt trùng nhau.
    private var otherKeys: [String] = []
    /// Giá trị khi bấm "Về mặc định".
    private(set) var fallback = Hotkey.defaultToggle
    private var monitor: Any?
    private var peak: UInt = 0

    convenience init(key: String, otherKeys: [String], fallback: Hotkey, label: String) {
        self.init(title: "", target: nil, action: #selector(toggle))
        self.key = key
        self.otherKeys = otherKeys
        self.fallback = fallback
        setAccessibilityLabel(L("Phím tắt: ", "Shortcut: ") + label)
        target = self
        widthAnchor.constraint(equalToConstant: 150).isActive = true
        refresh()
    }

    func refresh() {
        title = Hotkey(string: UserDefaults.standard.string(forKey: key) ?? "")?.label ?? "—"
    }

    func set(_ h: Hotkey) {
        let others = otherKeys.map { Hotkey(string: UserDefaults.standard.string(forKey: $0) ?? "") }
        if let problem = h.problem(other: nil) ?? others.compactMap({ h.problem(other: $0) }).first {
            // Không nhận: báo lý do ngay trên nút rồi trở về phím tắt cũ.
            stop()
            NSSound.beep()
            title = problem == .duplicate ? L("Trùng phím tắt khác", "Same as another shortcut") : L("Cần thêm ⌃, ⌥ hoặc ⌘", "Add ⌃, ⌥ or ⌘")
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
        title = L("Nhấn tổ hợp phím…", "Press a key combination…")
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

    init(key: String, height: CGFloat = 186, label: String = L("Ứng dụng bắt đầu ở chế độ Anh", "Apps that start in English mode")) {
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
        table.setAccessibilityLabel(label)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
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
                string: item.name == nil ? L("   chưa cài trên máy này", "   not installed on this Mac") : "   \(item.id)",
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
    static var windowTitle: String { L("Cài đặt VNKey", "VNKey Settings") }
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

/// Cửa sổ Cài đặt luôn mang một tiêu đề. `NSTabViewController` kiểu thanh công cụ tự đặt lại tiêu đề cửa sổ theo
/// thẻ vừa chọn (các thẻ ở đây không có tiêu đề riêng nên nó thành trống), kể cả sau khi `fitWindow` đã đặt lại;
/// chặn ngay ở chỗ gán thì không phụ thuộc thứ tự các lần gọi đó.
private final class SettingsWindow: NSWindow {
    override var title: String {
        get { super.title }
        set { super.title = SettingsTabs.windowTitle }
    }
}

final class SettingsController: NSObject, NSWindowDelegate {
    static var windowTitle: String { SettingsTabs.windowTitle }
    static let width: CGFloat = 580
    /// Đánh dấu một view cần giãn hết chiều ngang của thẻ.
    fileprivate static let wide = NSUserInterfaceItemIdentifier("wide")
    fileprivate static let titleID = NSUserInterfaceItemIdentifier("title")
    fileprivate static let noteID = NSUserInterfaceItemIdentifier("note")
    let window: NSWindow
    private let tabs = SettingsTabs()
    private let defaults = UserDefaults.standard
    private var tables: [EntryTable] = []
    private var appList: AppList?
    private var clipAppList: AppList?
    private var hotkeyButtons: [HotkeyButton] = []
    private var methodControl: NSSegmentedControl?
    /// Các công tắc chỉ có nghĩa với Telex: mờ đi khi chọn VNI.
    private var telexSwitches: [NSSwitch] = []
    private var toneControl: NSSegmentedControl?
    private var loginSwitch: NSSwitch?
    private var removeButton: NSButton?
    private var runningAppsMenu: NSPopUpButton?
    private var updateTitle: NSTextField?
    private var updateDetail: NSTextField?
    private var updateButton: NSButton?

    override init() {
        window = SettingsWindow(contentViewController: tabs)
        super.init()
        tabs.tabStyle = .toolbar
        for (title, symbol, view) in [
            (L("Chung", "General"), "gearshape", general()), (L("Gõ", "Typing"), "keyboard", typing()), (L("Ngôn ngữ", "Languages"), "globe", mixed()),
            (L("Chính tả", "Spelling"), "textformat.abc.dottedunderline", corrections()), (L("Gõ tắt", "Shortcuts"), "bolt", shortcuts()),
            (L("Ứng dụng", "Apps"), "macwindow.on.rectangle", apps()), (L("Bảng tạm", "Clipboard"), "doc.on.clipboard", clipboard()),
            (L("Giới thiệu", "About"), "info.circle", about()),  // luôn ở cuối: `openUpdatePage` chọn thẻ cuối
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
        Updater.shared.onChange = { [weak self] in self?.showUpdateState() }
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
        showUpdateState()
        appList?.reload()
        clipAppList?.reload()
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

    /// Dòng ghi phím tắt kèm nút về mặc định. Các phím tắt của VNKey không được trùng nhau.
    private func hotkey(_ name: String, _ detail: String?, _ key: String) -> NSView {
        let all: [(String, Hotkey)] = [
            (Key.toggleHotkey, .defaultToggle), (Key.restoreHotkey, .defaultRestore), (Key.clipboardHotkey, .defaultClipboard),
        ]
        let b = HotkeyButton(
            key: key, otherKeys: all.map(\.0).filter { $0 != key }, fallback: all.first { $0.0 == key }?.1 ?? .defaultToggle, label: name)
        hotkeyButtons.append(b)
        let reset = NSButton(
            image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: L("Về mặc định", "Reset to default"))!,
            target: self, action: #selector(resetHotkey(_:)))
        reset.bezelStyle = .circular
        reset.toolTip = L("Về mặc định", "Reset to default")
        reset.tag = hotkeyButtons.count - 1
        return row(name, detail, b, reset)
    }

    private func general() -> NSView {
        let login = NSSwitch()
        login.controlSize = .small
        login.target = self
        login.action = #selector(toggleLogin(_:))
        login.setAccessibilityLabel(L("Mở cùng lúc đăng nhập", "Open at login"))
        loginSwitch = login
        let openLog = NSButton(title: L("Mở tệp", "Show file"), target: self, action: #selector(openLog))
        openLog.controlSize = .small
        let logSwitch = NSSwitch()
        logSwitch.controlSize = .small
        logSwitch.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values." + Key.debugLog)
        logSwitch.setAccessibilityLabel(L("Ghi nhật ký gỡ lỗi", "Write a debug log"))

        var system: [NSView] = []
        if #available(macOS 13.0, *) { system.append(row(L("Mở cùng lúc đăng nhập", "Open at login"), nil, login)) }
        system.append(
            toggle(
                L("Tạm ngưng khi đang dùng bộ gõ khác của macOS", "Pause while another macOS input method is active"),
                L("Telex của Apple, tiếng Trung, Nhật… hoặc bàn phím không phải chữ Latin: VNKey đứng ngoài, biểu tượng mờ đi.", "Apple’s Telex, Chinese, Japanese… or a non-Latin keyboard: VNKey steps aside and its icon dims."),
                key: Key.followInputSource))
        system.append(
            row(L("Ghi nhật ký gỡ lỗi", "Write a debug log"), L("Lưu cả nội dung bạn gõ (trừ ô mật khẩu) vào máy này để tìm lỗi.", "Saves everything you type (except password fields) on this Mac for troubleshooting."), openLog, logSwitch))
        return page([
            title(L("Phím tắt", "Shortcut keys")),
            Card(rows: [
                hotkey(L("Bật/tắt tiếng Việt", "Toggle Vietnamese"), nil, Key.toggleHotkey),
                hotkey(L("Đổi từ vừa gõ", "Flip the last word"), L("Phím gốc ↔ tiếng Việt, và nhớ cho lần sau.", "Raw keys ↔ Vietnamese, remembered for next time."), Key.restoreHotkey),
            ]),
            note(L("Bấm vào ô phím tắt rồi nhấn tổ hợp mới; Esc để huỷ. Có thể dùng riêng phím bổ trợ như ⌃⇧: nhấn giữ rồi thả.", "Click a shortcut field and press the new combination; Esc cancels. Modifier-only shortcuts such as ⌃⇧ work too: hold, then release.")),
            title(L("Ngôn ngữ", "Language")),
            Card(rows: [row(L("Ngôn ngữ giao diện", "Interface language"), L("Đổi xong cửa sổ này tự mở lại.", "This window reopens after you change it."), languagePicker())]),
            title(L("Hiển thị", "Display")),
            Card(rows: [toggle(L("Hiện nhãn VN/EN cạnh con trỏ khi đổi chế độ", "Show a VN/EN label next to the caret when the mode changes"), key: Key.showHUD)]),
            title(L("Hệ thống", "System")),
            Card(rows: system),
        ])
    }

    private func languagePicker() -> NSPopUpButton {
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        pop.addItems(withTitles: [L("Theo hệ thống", "System"), "Tiếng Việt", "English"])
        pop.selectItem(at: ["auto", "vi", "en"].firstIndex(of: AppLanguage.setting) ?? 0)
        pop.target = self
        pop.action = #selector(pickLanguage(_:))
        pop.setAccessibilityLabel(L("Ngôn ngữ giao diện", "Interface language"))
        return pop
    }

    @objc private func pickLanguage(_ sender: NSPopUpButton) {
        let value = ["auto", "vi", "en"][max(0, sender.indexOfSelectedItem)]
        guard value != AppLanguage.setting else { return }
        defaults.set(value, forKey: Key.language)
        onLanguageChange?()
    }

    /// Gọi khi người dùng đổi ngôn ngữ: AppDelegate dựng lại cửa sổ này bằng ngôn ngữ mới.
    var onLanguageChange: (() -> Void)?

    /// Thẻ "Giới thiệu": ứng dụng, cập nhật, nhà phát triển.
    private func about() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let name = NSTextField(labelWithString: "VNKey")
        name.font = .systemFont(ofSize: 20, weight: .semibold)
        let version = NSTextField(labelWithString: L("Phiên bản", "Version") + " \(AppInfo.version)\(AppInfo.build.isEmpty ? "" : " (\(AppInfo.build))")")
        version.textColor = .secondaryLabelColor
        version.isSelectable = true
        let tagline = NSTextField(labelWithString: L("Bộ gõ tiếng Việt cho macOS: gõ xen kẽ Việt – Anh, soát lỗi gõ.", "A Vietnamese input method for macOS: mix Vietnamese and English, with typo checking."))
        tagline.font = .systemFont(ofSize: 11)
        tagline.textColor = .secondaryLabelColor
        let text = NSStackView(views: [name, version, tagline])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let header = NSStackView(views: [icon, text])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14

        let check = NSButton(title: "", target: self, action: #selector(updateAction))
        updateButton = check
        let statusRow = row(L("Cập nhật", "Updates"), " ", check)
        let fields = SettingsController.labels(in: statusRow)
        updateTitle = fields.first
        updateDetail = fields.dropFirst().first

        let notes = NSButton(title: L("Có gì mới…", "What’s New…"), target: self, action: #selector(showChangelog))
        let site = NSButton(title: L("Trang web", "Website"), target: self, action: #selector(openWebsite))
        let source = NSButton(title: L("Mã nguồn", "Source Code"), target: self, action: #selector(openSource))

        return page([
            header,
            title(L("Cập nhật", "Updates")),
            Card(rows: [
                statusRow,
                toggle(
                    L("Tự kiểm tra bản mới mỗi ngày", "Check for new versions every day"),
                    L(
                        "Chỉ hỏi GitHub số phiên bản mới nhất; không gửi gì về bạn hay về việc bạn gõ. Có bản mới thì VNKey báo; bạn bấm mới cài.",
                        "Only asks GitHub for the latest version number; nothing about you or your typing is sent. VNKey tells you when there is one and installs only when you click."),
                    key: Key.autoUpdateCheck),
                row(L("Nhật ký thay đổi", "Release notes"), L("Những gì đã đổi qua từng phiên bản.", "What changed in each version."), notes),
            ]),
            title(L("Nhà phát triển", "Developer")),
            Card(rows: [
                row(AppInfo.developer, L("Tác giả", "Author")),
                row("VNKey", AppInfo.website.host ?? "", site, source),
            ]),
            note("© 2026 \(AppInfo.developer) · GPL-3.0"),
        ])
    }

    /// Các nhãn chữ bên trong một dòng cài đặt, theo thứ tự (tên, rồi mô tả).
    private static func labels(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { v -> [NSTextField] in
            if let f = v as? NSTextField { return [f] }
            return v is NSButton ? [] : labels(in: v)
        }
    }

    /// Dòng trạng thái cập nhật theo kết quả lần kiểm tra gần nhất và tiến độ tự cập nhật.
    private func showUpdateState() {
        guard let name = updateTitle, let detail = updateDetail, let button = updateButton else { return }
        let when: String = {
            guard let d = Updater.shared.lastChecked else { return L("Chưa kiểm tra lần nào.", "Never checked.") }
            let f = DateFormatter()
            f.locale = Locale(identifier: AppLanguage.isVietnamese ? "vi_VN" : "en_US")
            f.dateStyle = .medium
            f.timeStyle = .short
            return L("Kiểm tra lần cuối: \(f.string(from: d)).", "Last checked: \(f.string(from: d)).")
        }()
        button.isEnabled = true
        button.title = L("Kiểm tra bản mới", "Check Now")
        let updater = Updater.shared
        switch updater.state {
        case .idle:
            name.stringValue = L("Cập nhật", "Updates"); detail.stringValue = when
        case .checking:
            name.stringValue = L("Đang kiểm tra…", "Checking…")
            detail.stringValue = L("Hỏi GitHub về bản phát hành mới nhất.", "Asking GitHub for the latest release.")
            button.isEnabled = false
        case .done(.upToDate):
            name.stringValue = L("Bạn đang dùng bản mới nhất", "You are up to date"); detail.stringValue = when
        case .done(.available(let r)):
            name.stringValue = L("Có bản mới \(r.version)", "Version \(r.version) is available")
            if updater.canInstall {
                detail.stringValue = L(
                    "Bạn đang dùng bản \(AppInfo.version). VNKey sẽ tải, kiểm tra chữ ký, tự thay rồi mở lại.",
                    "You have \(AppInfo.version). VNKey will download it, check its signature, replace itself, and reopen.")
                button.title = L("Cập nhật ngay", "Update Now")
            } else {
                detail.stringValue = L(
                    "Bạn đang dùng bản \(AppInfo.version). Bản này không tự cập nhật được; bấm để mở trang tải.",
                    "You have \(AppInfo.version). This build cannot update itself; click to open the download page.")
                button.title = L("Mở trang tải…", "Open Download Page…")
            }
        case .downloading(let r):
            name.stringValue = L("Đang tải bản \(r.version)…", "Downloading \(r.version)…")
            detail.stringValue = r.downloadSize > 0
                ? String(format: "%.1f MB", Double(r.downloadSize) / 1_000_000) : ""
            button.isEnabled = false
        case .installing(let r):
            name.stringValue = L("Đang cài bản \(r.version)…", "Installing \(r.version)…")
            detail.stringValue = L("VNKey sẽ tự mở lại sau giây lát.", "VNKey will reopen in a moment.")
            button.isEnabled = false
        case .installFailed(let r, let why):
            name.stringValue = L("Chưa cài được bản \(r.version)", "Could not install \(r.version)")
            detail.stringValue = why
            button.title = L("Mở trang tải…", "Open Download Page…")
        case .done(.noRelease):
            name.stringValue = L("Chưa có bản phát hành nào", "No releases yet")
            detail.stringValue = L(
                "Kho \(AppInfo.repository) chưa đăng bản nào trên GitHub Releases.",
                "The repository \(AppInfo.repository) has not published a release on GitHub.")
        case .done(.failed(let why)):
            name.stringValue = L("Không kiểm tra được", "Could not check"); detail.stringValue = why
        }
    }

    @objc private func updateAction() {
        let updater = Updater.shared
        switch updater.state {
        case .done(.available(let r)):
            if updater.canInstall { updater.installUpdate() } else { NSWorkspace.shared.open(r.page) }
        case .installFailed(let r, _): NSWorkspace.shared.open(r.page)
        default: updater.check()
        }
    }

    @objc private func openWebsite() { NSWorkspace.shared.open(AppInfo.website) }

    @objc private func openSource() {
        if let url = URL(string: "https://github.com/\(AppInfo.repository)") { NSWorkspace.shared.open(url) }
    }

    @objc private func showChangelog() { ChangelogWindow.shared.show() }

    private func typing() -> NSView {
        let method = NSSegmentedControl(
            labels: ["Telex", "VNI"], trackingMode: .selectOne, target: self, action: #selector(pickMethod(_:)))
        methodControl = method
        method.setAccessibilityLabel(L("Kiểu gõ", "Input method"))
        func telexSwitch(_ name: String, _ detail: String, _ key: String) -> NSView {
            let s = NSSwitch()
            s.controlSize = .small
            s.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values." + key)
            s.setAccessibilityLabel(name)
            telexSwitches.append(s)
            return row(name, detail, s)
        }
        let tone = NSSegmentedControl(
            // Hai nhãn là ví dụ chính tả, không dịch.
            labels: ["hòa, thủy", "hoà, thuỷ"], trackingMode: .selectOne, target: self, action: #selector(pickTone(_:)))
        toneControl = tone
        tone.setAccessibilityLabel(L("Vị trí dấu thanh", "Tone mark placement"))
        return page([
            title(L("Cơ bản", "Basics")),
            Card(rows: [
                row(L("Kiểu gõ", "Input method"), nil, method),
                telexSwitch(L("Phím “w” đứng riêng thành “ư”", "A lone “w” becomes “ư”"), L("Chỉ với Telex. Gõ “ww” để ra chữ w.", "Telex only. Type “ww” for a plain w."), Key.standaloneW),
                telexSwitch(L("Phím [ ] thành “ơ” “ư”", "[ ] keys become “ơ” “ư”"), L("Chỉ với Telex. Gõ lặp “[[” để ra dấu ngoặc.", "Telex only. Type “[[” for a plain bracket."), Key.bracketKeys),
                row(L("Vị trí dấu thanh", "Tone mark placement"), L("Ở nguyên âm đầu (cũ) hay nguyên âm sau (mới).", "On the first vowel (old style) or the second (new style)."), tone),
            ]),
            title(L("Tự động", "Automatic")),
            Card(rows: [
                toggle(L("Viết hoa đầu câu", "Capitalize the start of sentences"), L("Sau . ! ? hoặc xuống dòng. Xoá lùi rồi gõ lại để giữ chữ thường.", "After . ! ? or a new line. Backspace and retype to keep it lowercase."), key: Key.autoCapitalize),
                toggle(L("Xoá khoảng trắng thừa trước dấu câu", "Remove the stray space before punctuation"), L("Áp dụng cho , . ; ! ?", "Applies to , . ; ! ?"), key: Key.tidyPunctuation),
            ]),
        ])
    }

    /// Dòng bật/tắt việc học thói quen gõ, kèm nút xoá những gì đã học.
    private func learnRow() -> NSView {
        let s = NSSwitch()
        s.controlSize = .small
        s.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values." + Key.learnUsage)
        s.setAccessibilityLabel(L("Ghi lại thói quen gõ", "Record my typing habits"))
        let clear = NSButton(title: L("Xoá đã học", "Clear learned data"), target: self, action: #selector(clearUsage))
        clear.controlSize = .small
        clear.toolTip = L("Xoá bảng đếm từ, cặp từ và lỗi gõ VNKey đã ghi trên máy này", "Delete the word, word-pair and typo counts VNKey has recorded on this Mac")
        return row(
            L("Ghi lại thói quen gõ", "Record my typing habits"),
            L("Đếm từ, cặp từ và lỗi gõ bạn đã sửa để đề nghị sát hơn; nhớ từ bạn xoá rồi gõ lại y nguyên. Chỉ trên máy này. Tắt thì ngừng ghi; thứ đã học vẫn được dùng.", "Counts words, word pairs and typos you corrected, and remembers words you delete and retype. On this Mac only. Turning it off keeps what was learned."),
            clear, s)
    }

    /// Thẻ "Ngôn ngữ": những thứ không phải tiếng Việt chuẩn mà VNKey nhận ra khi đang ở chế độ tiếng Việt. Mỗi nhóm
    /// có một công tắc chính; tắt nó thì các tuỳ chọn bên dưới mờ đi và không còn tác dụng (`applySettings`).
    private func mixed() -> NSView {
        return page([
            title(L("Tiếng Anh", "English")),
            Card(rows: [
                toggle(L("Gõ xen kẽ tiếng Anh", "Mix in English"), L("user, string, data… hiện đúng như bạn đã gõ, không bị bỏ dấu.", "user, string, data… appear exactly as you typed them, with no marks added."), key: Key.autoRestore),
                toggle(
                    L("Đoán theo ngữ cảnh", "Use context"), L("Sau hai từ tiếng Anh liên tiếp, từ mơ hồ như this, test cũng giữ tiếng Anh.", "After two English words in a row, ambiguous words (this, test) stay English."),
                    key: Key.contextAware, dependsOn: Key.autoRestore),
                toggle(
                    L("Giữ nguyên trong ngữ cảnh code", "Leave code alone"), L("Ngay sau @ # / \\ . _ : $ ~ = hoặc chữ số: email, đường dẫn, tên biến.", "Right after @ # / \\ . _ : $ ~ = or a digit: emails, paths, identifiers."),
                    key: Key.codeAware, dependsOn: Key.autoRestore),
                toggle(
                    L("Kiểm tra chính tả tiếng Anh", "Check English spelling"), L("Dùng từ điển tiếng Anh của macOS. Cần bật kiểm tra chính tả ở thẻ Chính tả.", "Uses the macOS English dictionary. Needs spell checking turned on in the Spelling tab."),
                    key: Key.proofreadEnglish, dependsOn: Key.autoRestore),
            ]),
            title(L("Ngôn ngữ GenZ", "Gen Z slang")),
            Card(rows: [
                toggle(L("Nhận chữ teen", "Recognize chat spelling"), L("Kiểu viết khi nhắn tin: zậy, jờ, ko, dc…", "The way people write in chats: zậy, jờ, ko, dc…"), key: Key.genZ),
                toggle(L("Cho phép f, j, w, z đứng đầu từ", "Allow f, j, w, z at the start of a word"), "zậy, jờ, dzô, fải…", key: Key.teen, dependsOn: Key.genZ),
                toggle(L("Bung viết tắt teen", "Expand chat abbreviations"), "ko → không, dc → được, j → gì, ntn → như thế nào…", key: Key.expandTeen, dependsOn: Key.genZ),
            ]),
        ])
    }

    /// Lỗi gõ đã học, kèm chữ sẽ hiện ra theo kiểu gõ đang chọn.
    private func typoRows() -> [(wrong: String, right: String, shown: String, count: Int)] {
        var config = Config()
        config.method = VNEngine.Method(rawValue: defaults.string(forKey: Key.method) ?? "") ?? .telex
        return UsageStore.model.learnedTypos().map { ($0.wrong, $0.right, Engine.shown(forKeys: $0.right, config: config), $0.count) }
    }

    /// Thẻ "Chính tả": VNKey không tự thay chữ (trừ việc trả lại từ tiếng Anh ở thẻ Ngôn ngữ). Nó gạch chân từ nghi
    /// gõ sai trong ô đang nhập và đề nghị chữ thay; bên dưới là việc học từ cách bạn gõ. Mọi thứ đã nhớ nằm trong MỘT
    /// bảng (`showMemory`): từ điển của bạn, từ giữ một dạng, lỗi gõ và cặp từ đã học.
    private func corrections() -> NSView {
        let open = NSButton(title: L("Xem và xoá…", "View and Remove…"), target: self, action: #selector(showMemory))
        open.controlSize = .small
        return page([
            title(L("Kiểm tra chính tả", "Check spelling")),
            Card(rows: [
                toggle(
                    L("Gạch chân từ nghi gõ sai", "Underline words that look mistyped"),
                    L("Đỏ: gõ nhầm (thiếu dấu, trật phím). Cam: sai chính tả. Rê chuột lên nét gạch, hoặc dùng ← → đưa con trỏ vào từ, để xem đề nghị. VNKey không tự thay chữ.", "Red: mistyped (missing marks, a slipped key). Orange: misspelled. Point at an underline, or arrow into the word, for suggestions. Nothing is changed for you."),
                    key: Key.proofread),
                toggle(
                    L("Trợ lý cho câu và đoạn văn (✦)", "Sentence and paragraph assistant (✦)"),
                    SentenceFix.available
                        ? L("Rê chuột lên một câu rồi vào nút ✦: sửa chính tả, cải tiến, viết lại, rút gọn, mở rộng, dịch, hoặc viết thành câu từ vài ý. Dùng mô hình chạy trên máy của macOS: không có gì rời khỏi máy. Bạn chọn thì mới thay.", "Rest the pointer on a sentence and move to ✦: fix spelling, improve, rewrite, shorten, expand, translate, or write sentences from notes. Uses the macOS on-device model: nothing leaves this Mac. Nothing changes until you choose.")
                        : L("Rê chuột lên một câu rồi vào nút ✦ để thêm dấu và sửa chính tả cả câu, bằng dữ liệu trên máy. Các việc khác (viết lại, dịch…) cần macOS 26 trở lên và Apple Intelligence.", "Rest the pointer on a sentence and move to ✦ to add marks and fix spelling for the whole sentence, using data on this Mac. The other tasks (rewrite, translate…) need macOS 26 or later with Apple Intelligence."),
                    key: Key.proofreadSentence, dependsOn: Key.proofread),
            ]),
            note(L("Để kiểm tra, VNKey đọc nội dung ô đang nhập, chỉ trên máy này và không lưu lại. Hiện chạy với ứng dụng macOS chuẩn (TextEdit, Ghi chú, Mail), chưa chạy trên trang web.", "To check, VNKey reads the text of the field you are typing in, only on this Mac, and stores none of it. It works in standard macOS apps (TextEdit, Notes, Mail) for now, not on web pages.")),
            title(L("Học từ cách bạn gõ", "Learning from your typing")),
            Card(rows: [
                learnRow(),
                row(L("Những gì VNKey đã nhớ", "What VNKey remembers"), L("Từ điển của bạn, từ luôn giữ một dạng, lỗi gõ và cặp từ đã học.", "Your dictionary, words kept in one form, learned typos and word pairs."), open),
            ]),
        ])
    }

    /// Mọi thứ VNKey đã nhớ, trong MỘT bảng chỉ xem và xoá (người dùng chọn 2026-11-25: đã có bảng đề nghị nên không cần
    /// hai bảng và không cần sửa tay). Mỗi dòng: chữ bạn gõ, VNKey làm gì với nó, và loại. Xoá dòng là quên mục đó.
    private func rememberedRows() -> [(row: [String], forget: () -> Void)] {
        var config = Config()
        config.method = VNEngine.Method(rawValue: defaults.string(forKey: Key.method) ?? "") ?? .telex
        var out: [(row: [String], forget: () -> Void)] = []
        func drop(_ word: String, from key: String) {
            defaults.set((defaults.stringArray(forKey: key) ?? []).filter { $0 != word }, forKey: key)
        }
        for w in (defaults.stringArray(forKey: Key.proofreadIgnored) ?? []).sorted() {
            out.append(([w, L("không gạch chân", "never underlined"), L("Từ điển", "Dictionary")], { [unowned self] in _ = self; drop(w, from: Key.proofreadIgnored) }))
        }
        for w in (defaults.stringArray(forKey: Key.preferRaw) ?? []).sorted() {
            out.append(([w, L("giữ nguyên phím đã gõ", "kept as typed"), L("Giữ một dạng", "Kept form")], { drop(w, from: Key.preferRaw) }))
        }
        for w in (defaults.stringArray(forKey: Key.preferVN) ?? []).sorted() {
            out.append(([w, L("luôn là “\(Engine.shown(forKeys: w, config: config))”", "always “\(Engine.shown(forKeys: w, config: config))”"), L("Giữ một dạng", "Kept form")], { drop(w, from: Key.preferVN) }))
        }
        for t in typoRows() {
            out.append(([t.wrong, L("đề nghị “\(t.shown)” (đã sửa \(t.count) lần)", "suggests “\(t.shown)” (fixed \(t.count)×)"), L("Lỗi gõ", "Typo")], {
                UsageStore.model.forgetTypo(t.wrong, fixed: t.right)
                Log.write("USAGE quên một lỗi gõ theo yêu cầu người dùng")
            }))
        }
        for p in UsageStore.model.learnedPairs() {
            out.append((["\(p.prev) \(p.plain)", L("đề nghị “\(p.prev) \(p.word)” (đã gõ \(p.count) lần)", "suggests “\(p.prev) \(p.word)” (typed \(p.count)×)"), L("Cặp từ", "Word pair")], {
                UsageStore.model.forget(prev: p.prev, word: p.word)
                Log.write("USAGE quên một cặp từ theo yêu cầu người dùng")
            }))
        }
        return out
    }

    private func remembered() -> NSView {
        let table = EntryTable(
            columns: [
                .text(title: L("Bạn gõ", "You type"), placeholder: "", width: 130),
                .text(title: L("VNKey", "VNKey"), placeholder: "", width: nil),
                .text(title: L("Loại", "Kind"), placeholder: "", width: 90),
            ],
            height: 280, label: L("Những gì VNKey đã nhớ", "What VNKey remembers"), searchable: true, readOnly: true,
            load: { [unowned self] in rememberedRows().map(\.row) },
            save: { [unowned self] rows in
                // Dòng nào không còn trong bảng là dòng người dùng vừa xoá: quên mục đó. Khoá là (chữ gõ, loại).
                let kept = Set(rows.map { $0[0] + "\u{1}" + $0[2] })
                for item in rememberedRows() where !kept.contains(item.row[0] + "\u{1}" + item.row[2]) { item.forget() }
                UsageStore.saveIfNeeded()
                return (rows.isEmpty ? L("Chưa nhớ gì", "Nothing remembered yet") : L("\(rows.count) mục", "\(rows.count) items"), false)
            })
        tables.append(table)
        table.view.identifier = SettingsController.wide
        return table.view
    }

    // MARK: - Bảng "đã nhớ" (mở từ thẻ Chính tả)

    private lazy var memoryWindow: NSWindow = {
        let width: CGFloat = 560, inner = width - 2 * Metrics.pageMargin
        let list = remembered()
        let text = note(L("“Từ điển”: từ bạn đã thêm từ bảng đề nghị. “Giữ một dạng”: từ bạn đã đổi bằng phím “Đổi từ vừa gõ” hoặc xoá rồi gõ lại. “Lỗi gõ”: bạn đã tự sửa hai lần. “Cặp từ”: bạn hay gõ có dấu. Xoá dòng để VNKey quên.", "“Dictionary”: words you added from a suggestion. “Kept form”: words you flipped with “Flip the last word” or deleted and retyped. “Typo”: you corrected it twice. “Word pair”: you usually type it with marks. Delete a row to make VNKey forget it."))
        text.preferredMaxLayoutWidth = inner
        let done = NSButton(title: L("Xong", "Done"), target: self, action: #selector(closeMemory))
        done.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, done])
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [list, text, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Metrics.controlGap + 4
        stack.edgeInsets = NSEdgeInsets(top: Metrics.pageTop, left: Metrics.pageMargin, bottom: Metrics.pageTop, right: Metrics.pageMargin)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        var constraints = [
            content.widthAnchor.constraint(equalToConstant: width),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ]
        for v in [list, text, buttons] as [NSView] { constraints.append(v.widthAnchor.constraint(equalToConstant: inner)) }
        NSLayoutConstraint.activate(constraints)
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.contentView = content
        sheet.setContentSize(content.fittingSize)
        return sheet
    }()

    /// Nội dung của bảng "đã nhớ", cho chế độ chụp giao diện.
    func memoryView() -> NSView {
        let sheet = memoryWindow
        tables.forEach { $0.reload() }
        return sheet.contentView!
    }

    @objc private func showMemory() {
        let sheet = memoryWindow
        tables.forEach { $0.reload() }
        window.beginSheet(sheet)
    }

    @objc private func closeMemory() {
        window.makeFirstResponder(nil)  // kết thúc ô đang sửa dở để nó được lưu
        window.endSheet(memoryWindow)
    }

    private func shortcuts() -> NSView {
        let macros = EntryTable(
            columns: [
                .text(title: L("Từ tắt", "Shortcut"), placeholder: L("vd: vn", "e.g. vn"), width: 110),
                .text(title: L("Nội dung", "Expands to"), placeholder: L("vd: Việt Nam", "e.g. Việt Nam"), width: nil),
            ],
            height: 196, label: L("Danh sách gõ tắt", "Shortcut list"), searchable: true,
            load: { [defaults] in ListFormat.rows(from: defaults.dictionary(forKey: Key.macros) as? [String: String] ?? [:]) },
            save: { [defaults] rows in
                let r = ListFormat.macros(fromRows: rows)
                if r.macros != (defaults.dictionary(forKey: Key.macros) as? [String: String] ?? [:]) {
                    defaults.set(r.macros, forKey: Key.macros)
                }
                return r.skipped == 0
                    ? (L("\(r.macros.count) mục", "\(r.macros.count) shortcuts"), false)
                    : (
                        L(
                            "\(r.macros.count) mục · \(r.skipped) dòng chưa dùng được: cần đủ hai ô, từ tắt chỉ gồm chữ cái",
                            "\(r.macros.count) shortcuts · \(r.skipped) rows unusable: fill both cells, letters only in the shortcut"),
                        true
                    )
            })
        tables.append(macros)
        macros.view.identifier = SettingsController.wide
        // Gõ tắt thông minh: cùng kiểu bảng, nhưng bung khi gõ `\tên`.
        let smart = EntryTable(
            columns: [
                .text(title: L("Tên (gõ \\tên)", "Name (type \\name)"), placeholder: L("vd: homnay", "e.g. homnay"), width: 130),
                .text(title: L("Nội dung", "Expands to"), placeholder: L("vd: Hà Nội, [ngaydai]", "e.g. Hà Nội, [ngaydai]"), width: nil),
            ],
            height: 150, label: L("Gõ tắt thông minh", "Smart shortcuts"), searchable: false,
            load: { [defaults] in ListFormat.rows(from: defaults.dictionary(forKey: Key.smartMacroTable) as? [String: String] ?? [:]) },
            save: { [defaults] rows in
                let r = ListFormat.macros(fromRows: rows)
                if r.macros != (defaults.dictionary(forKey: Key.smartMacroTable) as? [String: String] ?? [:]) {
                    defaults.set(r.macros, forKey: Key.smartMacroTable)
                }
                return r.skipped == 0
                    ? (L("\(r.macros.count) mục", "\(r.macros.count) shortcuts"), false)
                    : (
                        L(
                            "\(r.macros.count) mục · \(r.skipped) dòng chưa dùng được: cần đủ hai ô, tên chỉ gồm chữ cái",
                            "\(r.macros.count) shortcuts · \(r.skipped) rows unusable: fill both cells, letters only in the name"),
                        true
                    )
            })
        tables.append(smart)
        smart.view.identifier = SettingsController.wide
        let now = Date()
        let examples = SmartMacro.variables.map { name -> String in
            let value: String
            switch name {
            case "hoten": value = NSFullUserName()
            case "clipboard": value = L("(thứ vừa sao chép)", "(what you last copied)")
            default: value = SmartMacro.resolve("[\(name)]", at: now)
            }
            return "[\(name)] \(value)"
        }.joined(separator: "   ·   ")
        return page([
            title(L("Gõ tắt của bạn", "Your shortcuts")),
            macros.view,
            note(L("Gõ từ tắt rồi nhấn dấu cách hoặc dấu câu để bung ra; viết hoa chữ đầu thì kết quả cũng viết hoa. Bấm đúp vào ô để sửa.", "Type a shortcut, then space or punctuation, to expand it; capitalize the shortcut and the result is capitalized too. Double-click a cell to edit.")),
            title(L("Gõ tắt thông minh", "Smart shortcuts")),
            Card(rows: [
                toggle(
                    L("Bung khi gõ \\tên", "Expand when I type \\name"),
                    L("Gõ dấu \\ rồi tên, rồi dấu cách hoặc dấu câu: \\homnay ra ngày hôm nay. Dấu \\ để không lẫn với chữ gõ thường.", "Type \\, the name, then space or punctuation: \\homnay gives today's date. The \\ keeps it apart from ordinary typing."),
                    key: Key.smartMacros)
            ]),
            smart.view,
            note(L("Nội dung của cả hai bảng dùng được các biến sau, thay bằng giá trị lúc bung ra:", "Expansions in both tables can use these variables, filled in when the shortcut expands:") + "\n" + examples),
        ])
    }

    private func apps() -> NSView {
        let list = AppList(key: Key.excludedApps)
        appList = list
        let add = NSButton(title: L("Thêm ứng dụng…", "Add App…"), target: self, action: #selector(addApp))
        // Nút dạng menu kéo xuống: liệt kê ứng dụng đang mở, dựng lại mỗi lần bấm.
        let running = NSPopUpButton(frame: .zero, pullsDown: true)
        running.addItem(withTitle: L("Thêm ứng dụng đang mở", "Add a Running App"))
        NotificationCenter.default.addObserver(
            self, selector: #selector(fillRunningApps(_:)), name: NSPopUpButton.willPopUpNotification, object: running)
        runningAppsMenu = running
        let remove = NSButton(title: L("Xoá", "Delete"), target: self, action: #selector(removeApps))
        remove.isEnabled = false
        remove.toolTip = L("Xoá các ứng dụng đang chọn (phím Delete)", "Remove the selected apps (Delete key)")
        removeButton = remove
        list.onSelection = { [weak remove] n in remove?.isEnabled = n > 0 }
        let restore = NSButton(title: L("Về mặc định", "Reset to default"), target: self, action: #selector(restoreApps))
        restore.toolTip = L("Trở lại danh sách ứng dụng terminal ban đầu", "Go back to the original list of terminal apps")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [add, running, remove, spacer, restore])
        buttons.orientation = .horizontal
        buttons.spacing = Metrics.controlGap
        buttons.identifier = SettingsController.wide
        return page([
            title(L("Theo từng ứng dụng", "Per app")),
            Card(rows: [
                toggle(
                    L("Nhớ chế độ Việt/Anh riêng cho từng ứng dụng", "Remember Vietnamese/English mode for each app"), L("Mỗi ứng dụng trở lại chế độ bạn chọn lần cuối ở đó.", "Each app returns to the mode you last used there."),
                    key: Key.perApp),
                toggle(L("Sửa lặp chữ ở ô có gợi ý", "Fix doubled letters in fields with suggestions"), L("Thanh địa chỉ trình duyệt, Spotlight.", "Browser address bars, Spotlight."), key: Key.fixBrowser),
            ]),
            title(L("Bắt đầu ở chế độ Anh", "Start in English mode")),
            list.scroll,
            buttons,
            note(L("Mỗi lần chuyển sang các ứng dụng này VNKey tự về chế độ Anh; vẫn bật lại được bằng phím tắt.", "VNKey switches to English mode whenever you move to these apps; the shortcut still turns Vietnamese back on.")),
        ])
    }

    // MARK: - Hành động

    @objc private func pickMethod(_ sender: NSSegmentedControl) {
        defaults.set(sender.selectedSegment == 1 ? "vni" : "telex", forKey: Key.method)
        showMethod()
    }

    @objc private func clearUsage() {
        let alert = NSAlert()
        alert.messageText = L("Xoá mọi thứ VNKey đã học về cách bạn gõ?", "Delete everything VNKey has learned about how you type?")
        alert.informativeText =
            L(
                "Hiện có \(UsageStore.model.wordCount) từ và \(UsageStore.model.pairTotal) cặp từ. Việc đoán từ sẽ chỉ còn dựa vào danh sách từ thông dụng có sẵn cho tới khi học lại.",
                "There are \(UsageStore.model.wordCount) words and \(UsageStore.model.pairTotal) word pairs. Prediction will rely only on the built-in list of common words until it learns again.")
        alert.addButton(withTitle: L("Xoá", "Delete"))
        alert.addButton(withTitle: L("Huỷ", "Cancel"))
        alert.beginSheetModal(for: window) { r in if r == .alertFirstButtonReturn { UsageStore.clear() } }
    }

    @objc private func pickTone(_ sender: NSSegmentedControl) {
        defaults.set(sender.selectedSegment == 1, forKey: Key.modernTone)
    }

    @objc private func resetHotkey(_ sender: NSButton) {
        hotkeyButtons[sender.tag].set(hotkeyButtons[sender.tag].fallback)
    }

    @objc private func toggleLogin(_ sender: NSSwitch) {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do { if sender.state == .on { try service.register() } else { try service.unregister() } } catch {
            Log.write("LOGIN ITEM lỗi: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = L("Không đổi được thiết lập mở cùng lúc đăng nhập", "Could not change the open-at-login setting")
            alert.informativeText =
                error.localizedDescription + "\n\n"
                + L(
                    "Bạn có thể tự bật trong Cài đặt hệ thống › Cài đặt chung › Mục đăng nhập.",
                    "You can turn it on yourself in System Settings › General › Login Items.")
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
            let none = NSMenuItem(title: L("Không còn ứng dụng nào để thêm", "No more apps to add"), action: nil, keyEquivalent: "")
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

    // MARK: - Bảng tạm

    private func clipboard() -> NSView {
        let clear = NSButton(title: L("Xoá lịch sử…", "Clear History…"), target: self, action: #selector(clearClipboard))
        clear.controlSize = .small

        let syncName = L("Đồng bộ qua iCloud Drive", "Sync through iCloud Drive")
        let syncDetail = L(
            "Văn bản và đường dẫn bạn sao chép được lưu dạng đọc được trong thư mục VNKey của iCloud Drive, để các máy Mac khác của bạn cùng thấy. Ảnh và tệp không đồng bộ.",
            "Text and links you copy are stored in readable form in the VNKey folder of iCloud Drive so your other Macs see them too. Images and files are not synced.")
        let syncRow: NSView
        if ClipboardSync.isAvailable {
            syncRow = toggle(syncName, syncDetail, key: Key.clipboardSync, dependsOn: Key.clipboardEnabled)
        } else {
            let off = NSSwitch()
            off.controlSize = .small
            off.isEnabled = false
            off.setAccessibilityLabel(syncName)
            syncRow = row(syncName, L("Máy này chưa bật iCloud Drive.", "iCloud Drive is not turned on for this Mac."), off)
        }

        let list = AppList(key: Key.clipboardExcludedApps, height: 96, label: L("Ứng dụng không lưu vào bảng tạm", "Apps left out of clipboard history"))
        clipAppList = list
        let add = NSButton(title: L("Thêm ứng dụng…", "Add App…"), target: self, action: #selector(addClipApp))
        let remove = NSButton(title: L("Xoá", "Delete"), target: self, action: #selector(removeClipApps))
        remove.isEnabled = false
        list.onSelection = { [weak remove] n in remove?.isEnabled = n > 0 }
        let buttons = NSStackView(views: [add, remove])
        buttons.orientation = .horizontal
        buttons.spacing = Metrics.controlGap

        return page([
            title(L("Lịch sử", "History")),
            Card(rows: [
                toggle(
                    L("Lưu lại những gì đã sao chép", "Keep what you copy"),
                    L("200 mục gần nhất (văn bản, đường dẫn, ảnh, tệp), lưu trên máy này. Mật khẩu từ trình quản lý mật khẩu không được lưu.", "The last 200 items (text, links, images, files), stored on this Mac. Passwords from password managers are not kept."),
                    key: Key.clipboardEnabled),
                hotkey(
                    L("Mở bảng tạm", "Open the clipboard"),
                    L("Hiện cạnh chỗ đang gõ: gõ để tìm, ↩ để dán. Văn bản TCVN3, VNI tự dán thành Unicode.", "Appears where you type: type to search, ↩ to paste. TCVN3 and VNI text is pasted as Unicode."),
                    Key.clipboardHotkey),
                row(L("Xoá mọi thứ đã lưu", "Delete everything stored"), nil, clear),
            ]),
            title(L("Đồng bộ", "Sync")),
            Card(rows: [syncRow]),
            title(L("Không lưu khi sao chép từ", "Do not keep copies from")),
            list.scroll,
            buttons,
        ])
    }

    @objc private func clearClipboard() {
        let alert = NSAlert()
        alert.messageText = L("Xoá toàn bộ lịch sử bảng tạm?", "Clear the whole clipboard history?")
        alert.informativeText = L(
            "Xoá cả các mục đã ghim. Nếu đang bật đồng bộ, các mục này cũng bị xoá trên iCloud Drive và trên các máy Mac khác của bạn.",
            "Pinned items are deleted too. If sync is on, these items are also removed from iCloud Drive and from your other Macs.")
        alert.addButton(withTitle: L("Xoá", "Delete"))
        alert.addButton(withTitle: L("Huỷ", "Cancel"))
        alert.beginSheetModal(for: window) { r in
            if r == .alertFirstButtonReturn { (NSApp.delegate as? AppDelegate)?.clearClipboardHistory() }
        }
    }

    @objc private func addClipApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        clipAppList?.add(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }

    @objc private func removeClipApps() { clipAppList?.removeSelected() }

    @objc private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        appList?.add(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }
}
