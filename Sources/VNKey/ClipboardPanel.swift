import AppKit
import QuickLookThumbnailing
import VNEngine
import VNKeyCore

/// Bảng nổi nhận được phím mà không kéo VNKey ra trước: ứng dụng đang gõ vẫn là ứng dụng ở trước,
/// nên đóng bảng xong là dán được ngay vào đúng chỗ.
private final class ClipPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Dòng đang chọn luôn tô màu nhấn dù tiêu điểm nằm ở ô tìm kiếm.
private final class ClipRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

/// Thẻ nhỏ bo góc trong một dòng: "HTML", "RTF", "TCVN3"…
private final class ClipTag: NSView {
    private let label = NSTextField(labelWithString: "")
    override var wantsUpdateLayer: Bool { true }

    init(_ text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        label.stringValue = text
        label.font = .systemFont(ofSize: 9.5, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5), label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1.5), label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1.5),
        ])
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
        setAccessibilityLabel(text)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
    }
}

/// Ảnh thu nhỏ cho ảnh đã sao chép, tệp và biểu tượng ứng dụng nguồn.
private enum ClipIcons {
    private static let cache = NSCache<NSString, NSImage>()

    static func symbol(_ name: String) -> NSImage? { NSImage(systemSymbolName: name, accessibilityDescription: nil) }

    static func app(_ bundle: String?) -> NSImage? {
        guard let bundle else { return nil }
        if let hit = cache.object(forKey: bundle as NSString) { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: bundle as NSString)
        return icon
    }

    static func image(_ id: String) -> NSImage? {
        if let hit = cache.object(forKey: id as NSString) { return hit }
        guard let image = NSImage(contentsOf: ClipboardStore.imageURL(id)) else { return nil }
        cache.setObject(image, forKey: id as NSString)
        return image
    }

    /// Biểu tượng tệp có ngay; ảnh xem trước (ảnh, video, PDF…) tới sau qua `done`.
    static func file(_ path: String, done: @escaping (NSImage) -> Void) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path), size: CGSize(width: 88, height: 88),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let rep else { return }
            DispatchQueue.main.async {
                cache.setObject(rep.nsImage, forKey: path as NSString)
                done(rep.nsImage)
            }
        }
        return NSWorkspace.shared.icon(forFile: path)
    }
}

/// Bảng lịch sử clipboard: ô tìm kiếm ở trên, danh sách ở dưới, điều khiển hoàn toàn bằng bàn phím.
final class ClipboardPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSWindowDelegate {
    static let width: CGFloat = 420
    private static let rowHeight: CGFloat = 32, imageRowHeight: CGFloat = 56, maxListHeight: CGFloat = 320
    private static let digitCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]  // phím 1…9

    let window: NSPanel
    private let search = NSTextField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let enableButton = NSButton(title: "", target: nil, action: nil)
    private let hint = NSTextField(labelWithString: "")
    private var listHeight: NSLayoutConstraint!
    private var rows: [ClipItem] = []
    private var monitor: Any?
    private var topLeft = NSPoint.zero

    /// Các dạng có định dạng lưu kèm một mục (bản chụp giao diện thay bằng dữ liệu mẫu).
    var formats: (ClipItem) -> [String] = { ClipText.formats($0) }
    /// Lịch sử có đang bật không, và danh sách mục để hiện (bản chụp giao diện thay bằng dữ liệu mẫu).
    var isEnabled: () -> Bool = { UserDefaults.standard.bool(forKey: Key.clipboardEnabled) }
    var items: (String) -> [ClipItem] = { ClipboardStore.history.visible($0) }
    var onPaste: ((ClipItem, PasteMode) -> Void)?
    var onClose: (() -> Void)?

    var isVisible: Bool { window.isVisible }
    var contentView: NSView { window.contentView! }

    override init() {
        window = ClipPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: ClipboardPanel.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        window.level = .popUpMenu
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.delegate = self
        window.setAccessibilityLabel(L("Bảng tạm VNKey", "VNKey Clipboard"))

        let back = NSVisualEffectView()
        back.material = .popover
        back.state = .active
        back.blendingMode = .behindWindow
        // Bo góc bằng ảnh mặt nạ chứ không bằng `layer.cornerRadius`: chỉ cách này làm hình dạng CỬA SỔ bo theo,
        // nên bóng đổ ôm đúng góc tròn (bo bằng layer thì bóng vẫn vuông và lộ bốn góc).
        let radius: CGFloat = 12
        let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        back.maskImage = mask
        window.contentView = back

        search.isBordered = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.font = .systemFont(ofSize: 15)
        search.placeholderString = L("Tìm trong những gì đã sao chép", "Search what you copied")
        search.delegate = self
        search.setAccessibilityLabel(L("Tìm trong bảng tạm", "Search the clipboard"))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.style = .inset
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.refusesFirstResponder = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.setAccessibilityLabel(L("Đã sao chép", "Copied items"))
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        message.alignment = .center
        message.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: 12)
        enableButton.title = L("Bật lịch sử bảng tạm", "Turn On Clipboard History")
        enableButton.target = self
        enableButton.action = #selector(enable)
        enableButton.bezelStyle = .rounded
        enableButton.keyEquivalent = "\r"
        let placeholder = NSStackView(views: [message, enableButton])
        placeholder.orientation = .vertical
        placeholder.spacing = 10

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.stringValue = L("↩ dán    ⇥ dán dạng khác (Markdown, bảng mã)    ⌘P ghim    ⌘⌫ xoá", "↩ paste    ⇥ paste as (Markdown, encodings)    ⌘P pin    ⌘⌫ delete")
        hint.lineBreakMode = .byTruncatingTail

        func line() -> NSBox {
            let b = NSBox()
            b.boxType = .separator
            return b
        }
        let top = line(), bottom = line()
        for v in [search, top, scroll, placeholder, bottom, hint] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            back.addSubview(v)
        }
        listHeight = scroll.heightAnchor.constraint(equalToConstant: 120)
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: back.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: back.leadingAnchor, constant: 16),
            search.trailingAnchor.constraint(equalTo: back.trailingAnchor, constant: -16),
            top.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            top.leadingAnchor.constraint(equalTo: back.leadingAnchor), top.trailingAnchor.constraint(equalTo: back.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: back.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: back.trailingAnchor),
            listHeight,
            placeholder.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), placeholder.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualToConstant: ClipboardPanel.width - 64),
            bottom.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            bottom.leadingAnchor.constraint(equalTo: back.leadingAnchor), bottom.trailingAnchor.constraint(equalTo: back.trailingAnchor),
            hint.topAnchor.constraint(equalTo: bottom.bottomAnchor, constant: 7),
            hint.leadingAnchor.constraint(equalTo: back.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: back.trailingAnchor, constant: -16),
            hint.bottomAnchor.constraint(equalTo: back.bottomAnchor, constant: -8),
            back.widthAnchor.constraint(equalToConstant: ClipboardPanel.width),
        ])
    }

    // MARK: - Hiện / ẩn

    /// `anchor`: chỗ đang gõ (toạ độ Cocoa); nil thì hiện giữa màn hình.
    func show(near anchor: NSRect?) {
        search.stringValue = ""
        reload()
        let size = contentView.fittingSize
        let screen = anchor.flatMap { a in NSScreen.screens.first { $0.frame.intersects(a) } } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Chiều cao lớn nhất bảng có thể đạt khi danh sách đầy: chừa đủ chỗ để nó không tràn màn hình khi gõ tìm.
        let fullHeight = size.height - listHeight.constant + ClipboardPanel.maxListHeight
        if let a = anchor {
            // Ngay dưới con trỏ; không đủ chỗ thì lật lên trên.
            var top = a.minY - 6
            if top - fullHeight < visible.minY { top = min(visible.maxY, a.maxY + 6 + fullHeight) }
            topLeft = NSPoint(x: min(max(a.minX, visible.minX + 8), visible.maxX - size.width - 8), y: top)
        } else {
            topLeft = NSPoint(x: visible.midX - size.width / 2, y: visible.midY + fullHeight / 2 + 60)
        }
        place()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(search)
        Motion.present(window)  // mờ dần kèm phóng nhẹ từ góc gần con trỏ
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, e.window === self.window else { return e }
                return self.handleKey(e) ? nil : e
            }
        }
    }

    func close() {
        guard window.isVisible else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window.orderOut(nil)
        onClose?()
    }

    func windowDidResignKey(_ notification: Notification) { close() }  // bấm ra ngoài

    /// Giữ mép trên-trái đứng yên khi chiều cao đổi theo số dòng.
    private func place() {
        contentView.layoutSubtreeIfNeeded()
        let size = contentView.fittingSize
        window.setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), display: true)
        window.invalidateShadow()
    }

    func reload() {
        let enabled = isEnabled()
        let query = search.stringValue
        let keep = selected?.id
        rows = enabled ? items(query) : []
        table.reloadData()
        table.isHidden = rows.isEmpty
        enableButton.isHidden = enabled
        message.isHidden = !rows.isEmpty
        search.isEnabled = enabled
        hint.isHidden = rows.isEmpty
        if !enabled {
            message.stringValue = L(
                "Lịch sử bảng tạm đang tắt. Khi bật, VNKey lưu văn bản, đường dẫn, ảnh và tệp bạn sao chép trên máy này để dán lại.",
                "Clipboard history is off. When on, VNKey keeps the text, links, images and files you copy on this Mac so you can paste them again.")
        } else if rows.isEmpty {
            message.stringValue = query.isEmpty
                ? L("Chưa có gì. Sao chép thứ gì đó rồi mở lại bảng này.", "Nothing yet. Copy something, then open this panel again.")
                : L("Không tìm thấy “\(query)”.", "No matches for “\(query)”.")
        }
        // Chiều cao thật của danh sách (kiểu `.inset` tự thêm lề) cộng lề trên dưới của vùng cuộn.
        // Lề trên của dòng đầu cũng là lề dưới của dòng cuối; thiếu nó thì danh sách một dòng vẫn hiện thanh cuộn.
        let height = rows.isEmpty ? 0 : table.rect(ofRow: rows.count - 1).maxY + table.rect(ofRow: 0).minY + 10
        listHeight.constant = rows.isEmpty ? (enabled ? 72 : 132) : min(height, ClipboardPanel.maxListHeight)
        if !rows.isEmpty {
            let row = keep.flatMap { id in rows.firstIndex { $0.id == id } } ?? 0
            table.selectRowIndexes([query.isEmpty ? row : 0], byExtendingSelection: false)
            table.scrollRowToVisible(table.selectedRow)
        }
        if window.isVisible { place() }
    }

    // MARK: - Phím

    private var selected: ClipItem? { rows.indices.contains(table.selectedRow) ? rows[table.selectedRow] : nil }

    private func handleKey(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .option, .shift, .control])
        switch e.keyCode {
        case 53:  // Esc
            close()
        case 125: move(1)
        case 126: move(-1)
        case 36, 76:  // Return, Enter
            if !isEnabled() { enable(); return true }
            pasteSelected(mods.contains(.option) ? .original : mods.contains(.shift) ? .plain : .smart)
        case 48: showPasteAs()  // Tab
        default:
            guard mods == .command else { return false }
            switch e.keyCode {
            case 35: if let item = selected { ClipboardStore.change { $0.togglePin(item.id) } }  // ⌘P
            case 51: if let item = selected { ClipboardStore.change { $0.remove(item.id) } }  // ⌘⌫
            case 31:  // ⌘O
                guard let item = selected, item.kind == .link, let url = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return true }
                close()
                NSWorkspace.shared.open(url)
            default:
                guard let n = ClipboardPanel.digitCodes.firstIndex(of: e.keyCode) else { return false }
                if rows.indices.contains(n) { onPaste?(rows[n], .smart) }
            }
        }
        return true
    }

    private func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        let row = min(max(table.selectedRow + delta, 0), rows.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    private func pasteSelected(_ mode: PasteMode) {
        if let item = selected { onPaste?(item, mode) }
    }

    @objc private func clicked() {
        if rows.indices.contains(table.clickedRow) { onPaste?(rows[table.clickedRow], .smart) }
    }

    @objc private func enable() {
        UserDefaults.standard.set(true, forKey: Key.clipboardEnabled)
        reload()
        window.makeFirstResponder(search)
    }

    func controlTextDidChange(_ obj: Notification) { reload() }

    /// "Dán dạng": các bảng mã và bản không dấu, chỉ cho văn bản.
    private func showPasteAs() {
        guard let item = selected, item.kind == .text || item.kind == .link else { NSSound.beep(); return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let legacy = ClipText.legacy(item)
        let header = NSMenuItem(
            title: legacy.map { L("Đang là \(ClipText.name($0)). Dán dạng:", "This is \(ClipText.name($0)). Paste as:") } ?? L("Dán dạng:", "Paste as:"),
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for cs in Charset.allCases {
            let i = NSMenuItem(title: ClipText.name(cs), action: #selector(pasteAs(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = cs.rawValue
            menu.addItem(i)
        }
        menu.addItem(.separator())
        let strip = NSMenuItem(title: L("Không dấu", "Without diacritics"), action: #selector(pasteAs(_:)), keyEquivalent: "")
        strip.target = self
        strip.representedObject = "strip"
        menu.addItem(strip)
        // Chỉ mục có lưu định dạng (HTML, RTF) mới dịch được sang Markdown.
        let markdown = NSMenuItem(title: "Markdown", action: #selector(pasteAs(_:)), keyEquivalent: "")
        markdown.target = self
        markdown.representedObject = "markdown"
        markdown.isEnabled = !ClipText.formats(item).isEmpty
        menu.addItem(markdown)
        let rect = table.rect(ofRow: table.selectedRow)
        menu.popUp(positioning: menu.item(at: 1), at: NSPoint(x: rect.minX + 44, y: rect.maxY), in: table)
    }

    @objc private func pasteAs(_ sender: NSMenuItem) {
        guard let item = selected else { return }
        let raw = sender.representedObject as? String ?? ""
        if let cs = Charset(rawValue: raw) {
            onPaste?(item, .charset(cs))
        } else {
            onPaste?(item, raw == "markdown" ? .markdown : .stripped)
        }
    }

    // MARK: - Danh sách

    private func rowHeight(_ item: ClipItem) -> CGFloat {
        item.kind == .image ? ClipboardPanel.imageRowHeight : ClipboardPanel.rowHeight
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rowHeight(rows[row]) }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ClipRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = rows[row]
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        let side: CGFloat = item.kind == .image ? 44 : 20
        var titleText = item.title
        var badgeText = item.device ?? ""
        /// Nhãn nhỏ dạng thẻ: định dạng đang lưu kèm (RTF, HTML…) hoặc bảng mã cũ của văn bản.
        var tags = formats(item).map { $0.uppercased() }

        switch item.kind {
        case .image:
            icon.image = ClipIcons.image(item.id) ?? ClipIcons.symbol("photo")
            icon.wantsLayer = true
            icon.layer?.cornerRadius = 4
            icon.layer?.masksToBounds = true
            titleText = L("Ảnh", "Image") + (item.width.flatMap { w in item.height.map { " \(w) × \($0)" } } ?? "")
        case .file:
            let paths = item.paths
            if let first = paths.first {
                icon.image = ClipIcons.file(first) { [weak icon] image in icon?.image = image }
            }
            if paths.count > 1 { badgeText = L("\(paths.count) tệp", "\(paths.count) files") }
        case .link:
            icon.image = ClipIcons.symbol("link")
            icon.contentTintColor = .secondaryLabelColor
        case .text:
            icon.image = ClipIcons.app(item.app) ?? ClipIcons.symbol("text.alignleft")
            if let legacy = ClipText.legacy(item) {
                // Văn bản bảng mã cũ: hiện luôn bản đã giải mã, kèm tên bảng mã gốc.
                titleText = String(ClipText.unicode(item).prefix(400)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
                tags.insert(legacy == .tcvn3 ? "TCVN3" : legacy == .vniWindows ? "VNI" : "VIQR", at: 0)
            }
        }

        let title = NSTextField(labelWithString: titleText)
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        cell.textField = title

        var views: [NSView] = [icon, title]
        for tag in tags { views.append(ClipTag(tag)) }
        if !badgeText.isEmpty {
            let badge = NSTextField(labelWithString: badgeText)
            badge.font = .systemFont(ofSize: 11)
            badge.textColor = .secondaryLabelColor
            badge.lineBreakMode = .byTruncatingTail
            badge.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            badge.widthAnchor.constraint(lessThanOrEqualToConstant: 120).isActive = true
            views.append(badge)
        }
        if item.pinned, let pinImage = ClipIcons.symbol("pin.fill") {
            let pin = NSImageView(image: pinImage)
            pin.contentTintColor = .secondaryLabelColor
            pin.setAccessibilityLabel(L("Đã ghim", "Pinned"))
            views.append(pin)
        }
        if row < 9 {
            let key = NSTextField(labelWithString: "⌘\(row + 1)")
            key.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            key.textColor = .tertiaryLabelColor
            key.setContentCompressionResistancePriority(.required, for: .horizontal)
            views.append(key)
        }
        let line = NSStackView(views: views)
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 8
        line.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(line)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: side), icon.heightAnchor.constraint(equalToConstant: side),
            line.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            line.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            line.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// Nối các phần của tính năng clipboard: theo dõi, bảng chọn, dán, đồng bộ.
final class ClipboardController {
    private let panel = ClipboardPanel()
    private let watcher = ClipboardWatcher()
    private let sync = ClipboardSync()
    /// Chỗ đang gõ, hỏi TRƯỚC khi bảng nhận tiêu điểm.
    var anchor: () -> NSRect? = { nil }
    /// Phát ⌘V vào ứng dụng đang ở trước.
    var postPaste: () -> Void = {}
    /// Bảng mở/đóng làm đổi ô đang nhận phím: engine phải bỏ từ đang gõ dở.
    var resetTyping: () -> Void = {}

    init() {
        ClipboardStore.load()
        ClipboardStore.onChange = { [weak self] in
            guard let self else { return }
            if self.panel.isVisible { self.panel.reload() }
            self.sync.schedule()
        }
        panel.onPaste = { [weak self] item, mode in self?.paste(item, mode) }
        panel.onClose = { [weak self] in self?.resetTyping() }
    }

    /// Đọc lại cài đặt. Trả về true nếu đồng bộ vừa bị người dùng tắt (để hỏi có xoá bản trên iCloud không).
    @discardableResult
    func applySettings() -> Bool {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: Key.clipboardEnabled)
        if enabled { watcher.start() } else { watcher.stop() }
        let wantSync = enabled && defaults.bool(forKey: Key.clipboardSync)
        let wasOn = sync.isOn
        if wantSync { sync.start() } else { sync.stop() }
        return wasOn && !sync.isOn && enabled
    }

    func toggle() {
        if panel.isVisible {
            panel.close()
            return
        }
        let near = anchor()
        resetTyping()
        panel.show(near: near)
        Log.write("CLIP mở bảng (\(near == nil ? "giữa màn hình" : "cạnh con trỏ"))")
    }

    /// Gọi mỗi 2 giây từ đồng hồ chung của app.
    func tick(_ n: Int) {
        ClipboardStore.saveIfNeeded()
        if n % 15 == 0 { sync.run() }  // 30 giây đối chiếu lại một lần, phòng khi lỡ thông báo của thư mục
    }

    func flush() { ClipboardStore.saveIfNeeded(wait: true) }

    func clearHistory() { ClipboardStore.change { $0.clear() } }

    func removeRemoteCopies() { sync.removeRemoteCopies() }
    func keepRemoteCopies() { sync.forgetKnown() }

    private func paste(_ item: ClipItem, _ mode: PasteMode) {
        guard ClipPasteboard.write(item, mode) else {
            NSSound.beep()
            Log.write("CLIP không dán được: dữ liệu của mục \(item.kind.rawValue) không còn")
            return
        }
        watcher.skipCurrent()
        panel.close()
        // Mục vừa dùng lên đầu danh sách.
        var used = item
        used.date = Date()
        used.modified = used.date
        ClipboardStore.change { $0.add(used) }
        Log.write("CLIP dán loại=\(item.kind.rawValue) dài=\(item.text.count)")
        // Đợi một nhịp cho cửa sổ của ứng dụng đích nhận lại phím.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.postPaste() }
    }
}
