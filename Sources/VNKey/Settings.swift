import AppKit
import UniformTypeIdentifiers

// Cửa sổ cài đặt viết bằng AppKit thuần: Command Line Tools không kèm plugin macro của SwiftUI.

/// Ô soạn danh sách dạng văn bản (mỗi dòng một mục), lưu ngay khi sửa.
private final class ListEditor: NSObject, NSTextViewDelegate {
    let scroll = NSTextView.scrollableTextView()
    private var textView: NSTextView { scroll.documentView as! NSTextView }
    private let load: () -> String
    private let save: (String) -> Void

    init(load: @escaping () -> String, save: @escaping (String) -> Void) {
        self.load = load; self.save = save
        super.init()
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.delegate = self
    }

    /// Nạp lại từ UserDefaults, trừ khi người dùng đang gõ trong ô này.
    func reload() {
        if textView.window?.firstResponder !== textView { textView.string = load() }
    }

    func textDidChange(_ notification: Notification) { save(textView.string) }
}

/// Nút ghi phím tắt: bấm rồi nhấn tổ hợp mới.
private final class HotkeyButton: NSButton {
    private var key = ""
    private var monitor: Any?
    private var peak: UInt = 0

    convenience init(key: String) {
        self.init(title: "", target: nil, action: #selector(toggle))
        self.key = key
        target = self
        widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        refresh()
    }

    func refresh() {
        title = Hotkey(string: UserDefaults.standard.string(forKey: key) ?? "")?.label ?? "—"
    }

    func set(_ h: Hotkey) {
        UserDefaults.standard.set(h.string, forKey: key)
        stop()
    }

    @objc private func toggle() { monitor == nil ? start() : stop() }

    private func start() {
        title = "Nhấn tổ hợp phím… (Esc để huỷ)"
        hotkeyRecording = true; peak = 0
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [unowned self] e in
            let m = e.modifierFlags.rawValue & Hotkey.modMask
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

final class SettingsController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let defaults = UserDefaults.standard
    private var editors: [ListEditor] = []
    private var hotkeyButtons: [HotkeyButton] = []
    private var methodControl: NSSegmentedControl?
    private let pageWidth: CGFloat = 560

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460), styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        super.init()
        window.title = "Cài đặt VNKey"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let tabs = NSTabView()
        for (title, view) in [
            ("Chung", general()), ("Thông minh", smart()), ("Phím tắt", hotkeys()), ("Gõ tắt", macros()),
            ("Từ đã nhớ", learned()), ("Ứng dụng", apps()),
        ] {
            let item = NSTabViewItem()
            item.label = title
            item.view = view
            tabs.addTabViewItem(item)
        }
        window.contentView = tabs
        window.center()
    }

    func windowDidBecomeKey(_ notification: Notification) { reload() }
    func windowWillClose(_ notification: Notification) { hotkeyButtons.forEach { $0.stop() } }

    func reload() {
        editors.forEach { $0.reload() }
        hotkeyButtons.forEach { $0.refresh() }
        methodControl?.selectedSegment = defaults.string(forKey: Key.method) == "vni" ? 1 : 0
    }

    // MARK: - Thành phần

    private func page(_ views: [NSView], stretch: Bool = false) -> NSView {
        let stack = NSStackView(views: views + (stretch ? [] : [NSView()]))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        for v in views where v is NSScrollView || v is NSBox {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        }
        return stack
    }

    /// Ô đánh dấu gắn thẳng vào UserDefaults qua Cocoa Bindings.
    private func check(_ title: String, _ key: String) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values." + key)
        return b
    }

    private func hint(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = pageWidth - 60
        return l
    }

    private func heading(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return l
    }

    private func separator() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        return b
    }

    private func row(_ views: NSView...) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 8
        return s
    }

    private func editor(load: @escaping () -> String, save: @escaping (String) -> Void) -> NSView {
        let e = ListEditor(load: load, save: save)
        editors.append(e)
        return e.scroll
    }

    private func lines(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func listEditor(_ key: String, lowercase: Bool) -> NSView {
        editor(
            load: { [defaults] in (defaults.stringArray(forKey: key) ?? []).sorted().joined(separator: "\n") },
            save: { [defaults, unowned self] text in
                defaults.set(lines(lowercase ? text.lowercased() : text), forKey: key)
            })
    }

    // MARK: - Các trang

    private func general() -> NSView {
        let seg = NSSegmentedControl(
            labels: ["Telex", "VNI"], trackingMode: .selectOne, target: self, action: #selector(pickMethod(_:)))
        methodControl = seg
        return page([
            row(NSTextField(labelWithString: "Kiểu gõ"), seg),
            check("Bỏ dấu kiểu mới (hoà, thuỷ)", Key.modernTone),
            check("Telex: “w” đứng riêng thành “ư”", Key.standaloneW),
            separator(),
            check("Hiện nhãn VN/EN cạnh con trỏ khi đổi chế độ", Key.showHUD),
            check("Sửa lỗi lặp chữ ở ô có gợi ý (trình duyệt, Spotlight)", Key.fixBrowser),
            separator(),
            check("Tự viết hoa đầu câu", Key.autoCapitalize),
            hint("Sau . ! ? hoặc xuống dòng. Xoá lùi rồi gõ lại để giữ chữ thường."),
            check("Xoá khoảng trắng thừa trước , . ; ! ?", Key.tidyPunctuation),
        ])
    }

    @objc private func pickMethod(_ sender: NSSegmentedControl) {
        defaults.set(sender.selectedSegment == 1 ? "vni" : "telex", forKey: Key.method)
    }

    private func smart() -> NSView {
        page([
            check("Tự trả lại từ tiếng Anh / từ sai chính tả", Key.autoRestore),
            hint("Hai mục dưới đây chỉ có tác dụng khi mục trên đang bật."),
            check("Đoán theo ngữ cảnh", Key.contextAware),
            hint("Sau hai từ tiếng Anh liên tiếp, từ mơ hồ (this, test…) cũng giữ tiếng Anh."),
            check("Sửa lỗi gõ đảo hai phím liền nhau", Key.fixTransposition),
            hint("tieegns → tiếng. Chỉ sửa khi ra đúng một từ có trong từ điển."),
            separator(),
            check("Không bỏ dấu trong ngữ cảnh code", Key.codeAware),
            hint("Từ đứng liền sau @ # / \\ . _ : $ ~ = < & hoặc chữ số, và từ đứng liền trước _ hay @."),
            separator(),
            check("Cho phép chữ teen: f, j, w, z đứng đầu (zậy, jờ, dzô)", Key.teen),
            check("Bung viết tắt teen (ko → không, dc → được…)", Key.expandTeen),
        ])
    }

    private func hotkeys() -> NSView {
        func line(_ title: String, _ key: String, _ fallback: Hotkey) -> NSView {
            let b = HotkeyButton(key: key)
            hotkeyButtons.append(b)
            let reset = NSButton(title: "Mặc định", target: nil, action: nil)
            reset.target = self
            reset.action = #selector(resetHotkey(_:))
            reset.tag = hotkeyButtons.count - 1
            return row(b, reset, NSTextField(labelWithString: title))
        }
        return page([
            line("Bật/tắt tiếng Việt", Key.toggleHotkey, .defaultToggle),
            line("Đổi từ vừa gõ (phím gốc ↔ tiếng Việt)", Key.restoreHotkey, .defaultRestore),
            hint("Bấm vào nút rồi nhấn tổ hợp mới. Có thể dùng riêng phím bổ trợ (ví dụ ⌃⇧): nhấn giữ rồi thả."),
        ])
    }

    @objc private func resetHotkey(_ sender: NSButton) {
        hotkeyButtons[sender.tag].set(sender.tag == 0 ? .defaultToggle : .defaultRestore)
    }

    private func macros() -> NSView {
        page(
            [
                hint(
                    "Mỗi dòng một mục dạng:  vn = Việt Nam\nGõ từ tắt rồi nhấn dấu cách hoặc dấu câu để bung ra. Viết hoa chữ đầu thì kết quả cũng viết hoa."
                ),
                editor(
                    load: { [defaults] in
                        let d = defaults.dictionary(forKey: Key.macros) as? [String: String] ?? [:]
                        return d.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)" }.joined(separator: "\n")
                    },
                    save: { [defaults, unowned self] text in
                        var d: [String: String] = [:]
                        for l in lines(text) {
                            let p = l.split(separator: "=", maxSplits: 1).map {
                                $0.trimmingCharacters(in: .whitespaces)
                            }
                            if p.count == 2, !p[0].isEmpty, !p[1].isEmpty { d[p[0].lowercased()] = p[1] }
                        }
                        defaults.set(d, forKey: Key.macros)
                    }),
            ], stretch: true)
    }

    private func learned() -> NSView {
        page(
            [
                hint(
                    "Mỗi lần bạn dùng phím “Đổi từ vừa gõ”, VNKey nhớ lựa chọn đó. Mỗi dòng là một chuỗi phím đã gõ; xoá dòng để quên, thêm dòng để dạy trước."
                ),
                heading("Luôn giữ phím gốc"),
                listEditor(Key.preferRaw, lowercase: true),
                heading("Luôn bỏ dấu tiếng Việt"),
                listEditor(Key.preferVN, lowercase: true),
            ], stretch: true)
    }

    private func apps() -> NSView {
        let add = NSButton(title: "Thêm ứng dụng…", target: self, action: #selector(addApp))
        return page(
            [
                check("Nhớ chế độ Việt/Anh riêng cho từng ứng dụng", Key.perApp),
                separator(),
                heading("Ứng dụng bắt đầu ở chế độ Anh"),
                hint(
                    "Mỗi dòng một bundle ID. Mỗi lần chuyển sang các ứng dụng này VNKey tự tắt bỏ dấu; vẫn bật lại được bằng phím tắt."
                ),
                listEditor(Key.excludedApps, lowercase: false),
                add,
            ], stretch: true)
    }

    @objc private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var list = defaults.stringArray(forKey: Key.excludedApps) ?? []
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !list.contains(id) { list.append(id) }
        }
        defaults.set(list, forKey: Key.excludedApps)
        window.makeFirstResponder(nil)
        reload()
    }
}
