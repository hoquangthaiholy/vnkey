import AppKit
import Carbon.HIToolbox
import VNEngine
import VNKeyCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let engine = Engine()
    private let lexicon = SystemLexicon()
    private lazy var tap = KeyTap(engine: engine)
    private let hud = HUD()
    /// Tạo muộn: chế độ `--snapshot` không được đụng tới mục thanh menu. macOS lưu trạng thái ẩn/hiện của nó
    /// vào cài đặt của app, nên ẩn nó ở bản chụp thử sẽ làm biểu tượng của bản đang chạy biến mất.
    private lazy var status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var settings: SettingsController?
    private var onboarding: OnboardingController?
    private var lastSecure = false
    private var inputSource = InputSourceState()
    /// Tên bàn phím hệ thống đang chọn nếu vì nó mà VNKey tạm ngưng; nil = đang làm việc bình thường.
    private var foreignSource: String? { inputSource.foreign }
    private var ticks = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: Key.registered)
        // Tắt biểu tượng macOS tự gắn vào mục menu (bánh răng ở "Cài đặt…").
        defaults.register(defaults: ["NSMenuEnableActionImages": false])
        // Chế độ chụp giao diện: vẽ các cửa sổ ra PNG rồi thoát, KHÔNG khởi động event tap
        // (một bản VNKey khác có thể đang chạy; hai tap cùng lúc sẽ xử lý phím hai lần).
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.run(into: URL(fileURLWithPath: CommandLine.arguments[i + 1]), dark: CommandLine.arguments.contains("--dark"))
            NSApp.terminate(nil)
            return
        }
        installMainMenu()
        migrateSettings()
        Log.enabled = defaults.bool(forKey: Key.debugLog)
        let info = Bundle.main.infoDictionary
        Log.write(
            "==== VNKey \(info?["CFBundleShortVersionString"] ?? "?") khởi động, macOS \(ProcessInfo.processInfo.operatingSystemVersionString), AX trusted=\(AXIsProcessTrusted())"
        )
        engine.lexicon = lexicon
        UsageStore.load()
        engine.context = UsageStore.model
        engine.onLearn = { [unowned self] in
            // Được gọi từ trong callback của event tap: lưu ở vòng lặp sau, vì ghi UserDefaults kéo theo
            // `applySettings` chạy ngay tại chỗ.
            DispatchQueue.main.async {
                self.defaults.set(Array(self.engine.preferRaw), forKey: Key.preferRaw)
                self.defaults.set(Array(self.engine.preferVN), forKey: Key.preferVN)
            }
        }
        tap.onToggle = { [unowned self] in
            // Đang ở trong callback của event tap: làm việc nặng (AX, cửa sổ) ở vòng lặp sau.
            DispatchQueue.main.async { self.setEnabled(!self.tap.enabled, announce: true) }
        }
        applySettings()
        tap.frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        tap.enabled = state(for: tap.frontApp)

        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        inputSourceChanged()

        if !tap.start() {
            // Chưa có quyền Trợ năng: mở cửa sổ hướng dẫn (thay cho hộp thoại hệ thống cụt lủn) và thử lại
            // định kỳ cho tới khi được cấp.
            Log.write("TAP chưa khởi động được: thiếu quyền Trợ năng")
            onboarding = OnboardingController()
            onboarding?.show()
        }
        // Thêm vào `.common` để vẫn chạy khi menu đang mở (lúc đó vòng lặp ở chế độ theo dõi sự kiện).
        let watchdog = Timer(timeInterval: 2, repeats: true) { [unowned self] _ in
            if !tap.isRunning, tap.start() { Log.write("TAP đã khởi động (có quyền Trợ năng)") }
            tap.ensureEnabled()
            checkInputSource()  // lưới an toàn nếu lỡ một thông báo đổi bàn phím
            onboarding?.update(ready: tap.isRunning)
            ticks += 1
            if ticks % 15 == 0 { tap.flushPerf() }  // tổng kết hiệu năng mỗi 30 giây nếu có gõ
            if ticks % 60 == 0 { UsageStore.saveIfNeeded() }  // lưu thói quen gõ mỗi 2 phút nếu có thay đổi
            let secure = IsSecureEventInputEnabled()
            if secure != lastSecure {
                lastSecure = secure
                Log.write("SECURE INPUT \(secure ? "bật: bộ gõ không nhận được phím" : "tắt")")
            }
            refreshTitle()
        }
        RunLoop.main.add(watchdog, forMode: .common)
        timer = watchdog
        refreshTitle()
        if CommandLine.arguments.contains("--settings") { showVNKeySettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tap.flushPerf()
        UsageStore.saveIfNeeded(wait: true)
        Log.write("==== VNKey thoát")
        Log.flush()
    }

    /// Mở lại app khi đang chạy (từ Finder/Spotlight) = mở cửa sổ cài đặt.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showVNKeySettings()
        return false
    }

    /// macOS báo bàn phím hệ thống vừa đổi. Đọc ngay, rồi đọc lại sau một nhịp: thông báo đôi khi tới trước khi
    /// giá trị "bàn phím hiện tại" kịp đổi, và nếu chỉ đọc một lần thì trạng thái kẹt ở bàn phím cũ.
    @objc private func inputSourceChanged() {
        checkInputSource()
        for delay in [0.15, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.checkInputSource() }
        }
    }

    /// Tạm ngưng nếu bàn phím hệ thống không phải một bố cục chữ Latin. Gọi lại bao nhiêu lần cũng được: chỉ
    /// khi trạng thái thật sự đổi mới đụng tới engine và giao diện.
    private func checkInputSource() {
        var foreign: String?
        if defaults.bool(forKey: Key.followInputSource), let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            func value<T>(_ key: CFString) -> T? {
                guard let p = TISGetInputSourceProperty(src, key) else { return nil }
                return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() as? T
            }
            let type: String = value(kTISPropertyInputSourceType) ?? ""
            let ascii: Bool = value(kTISPropertyInputSourceIsASCIICapable) ?? false
            if !InputSourcePolicy.allowsTyping(
                isKeyboardLayout: type == (kTISTypeKeyboardLayout as String), isASCIICapable: ascii)
            {
                foreign = value(kTISPropertyLocalizedName) ?? "bộ gõ khác"
            }
        }
        let wasSuspended = inputSource.suspended
        guard inputSource.update(foreign: foreign) else { return }
        tap.suspended = foreign != nil
        if wasSuspended == inputSource.suspended {  // chỉ đổi tên bàn phím (Telex -> Zhuyin): cập nhật nhãn
            Log.write("INPUT SOURCE \(foreign ?? "?"): vẫn tạm ngưng")
            refreshTitle()
            return
        }
        engine.reset()
        tap.invalidateFocus()
        Log.write("INPUT SOURCE \(foreign.map { "\($0): tạm ngưng" } ?? "bố cục Latin: hoạt động")")
        refreshTitle()
        // Vừa hoạt động lại: nhắc chế độ và kiểu gõ đang dùng, sau một nhịp để việc đổi bàn phím kịp xong.
        if foreign == nil, tap.isRunning, defaults.bool(forKey: Key.showHUD) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.foreignSource == nil else { return }
                self.hud.show(self.modeLabel)
            }
        }
    }

    /// Nhãn hiện cạnh con trỏ mỗi khi chế độ đổi: "VN - Telex" / "VN - VNI"; ở chế độ Anh thì kiểu gõ không có
    /// nghĩa nên chỉ là "EN".
    private var modeLabel: String {
        guard tap.enabled else { return "EN" }
        return "VN - " + (defaults.string(forKey: Key.method) == "vni" ? "VNI" : "Telex")
    }

    /// Chuyển cài đặt của bản cũ sang dạng mới (chạy một lần, không làm gì nếu đã chuyển).
    private func migrateSettings() {
        // Hai kiểu "Telex đơn giản" (có trong một bản thử ngắn) nay là Telex với hai công tắc.
        switch defaults.string(forKey: Key.method) {
        case "simpleTelex1":
            defaults.set("telex", forKey: Key.method)
            defaults.set(false, forKey: Key.standaloneW)
            defaults.set(false, forKey: Key.bracketKeys)
        case "simpleTelex2":
            defaults.set("telex", forKey: Key.method)
            defaults.set(true, forKey: Key.standaloneW)
            defaults.set(false, forKey: Key.bracketKeys)
        default: break
        }
    }

    /// App thanh menu không hiện menu chính, nhưng vẫn cần nó để các ô nhập trong Cài đặt nhận ⌘C ⌘V ⌘X ⌘A
    /// ⌘Z, và ⌘W đóng cửa sổ.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Thoát VNKey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)

        let edit = NSMenu(title: "Sửa")
        edit.addItem(withTitle: "Hoàn tác", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Làm lại", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cắt", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Sao chép", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Dán", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Chọn tất cả", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        let window = NSMenu(title: "Cửa sổ")
        window.addItem(withTitle: "Đóng", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Thu nhỏ", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    // MARK: - Cài đặt

    @objc private func defaultsChanged() {
        if Thread.isMainThread { applySettings() } else { DispatchQueue.main.async { self.applySettings() } }
    }

    private func applySettings() {
        var c = Config()
        c.method = Method(rawValue: defaults.string(forKey: Key.method) ?? "") ?? .telex
        c.modernTone = defaults.bool(forKey: Key.modernTone)
        c.standaloneW = defaults.bool(forKey: Key.standaloneW)
        c.bracketKeys = defaults.bool(forKey: Key.bracketKeys)
        c.teenInitials = defaults.bool(forKey: Key.teen)
        c.autoRestore = defaults.bool(forKey: Key.autoRestore)
        c.expandTeen = defaults.bool(forKey: Key.expandTeen)
        c.codeAware = defaults.bool(forKey: Key.codeAware)
        c.fixTransposition = defaults.bool(forKey: Key.fixTransposition)
        c.contextAware = defaults.bool(forKey: Key.contextAware)
        c.autoCapitalize = defaults.bool(forKey: Key.autoCapitalize)
        c.tidyPunctuation = defaults.bool(forKey: Key.tidyPunctuation)
        c.learnFromRetype = defaults.bool(forKey: Key.learnFromRetype)
        c.predict = defaults.bool(forKey: Key.predict)
        c.predictUnmarked = defaults.bool(forKey: Key.predictUnmarked)
        UsageStore.model.recording = defaults.bool(forKey: Key.learnUsage)
        c.macros = (defaults.dictionary(forKey: Key.macros) as? [String: String]) ?? [:]
        // Gán config sẽ xoá trạng thái đang gõ: chỉ gán khi thật sự đổi.
        if engine.config != c {
            engine.config = c
            Log.write("CONFIG \(c)")
        }
        let logging = defaults.bool(forKey: Key.debugLog)
        if logging != Log.enabled {
            if !logging { Log.write("LOG tắt") }
            Log.enabled = logging
            Log.write("LOG bật")
        }

        let raw = Set(defaults.stringArray(forKey: Key.preferRaw) ?? [])
        let vn = Set(defaults.stringArray(forKey: Key.preferVN) ?? [])
        if engine.preferRaw != raw { engine.preferRaw = raw }
        if engine.preferVN != vn { engine.preferVN = vn }

        checkInputSource()  // công tắc "tạm ngưng theo bàn phím hệ thống" có thể vừa đổi
        tap.fixAutocomplete = defaults.bool(forKey: Key.fixBrowser)
        tap.toggleHotkey = Hotkey(string: defaults.string(forKey: Key.toggleHotkey) ?? "") ?? .defaultToggle
        tap.restoreHotkey = Hotkey(string: defaults.string(forKey: Key.restoreHotkey) ?? "") ?? .defaultRestore
    }

    private var excluded: Set<String> { Set(defaults.stringArray(forKey: Key.excludedApps) ?? []) }

    /// Chế độ khởi đầu khi chuyển sang một ứng dụng.
    private func state(for bundle: String) -> Bool {
        AppMode.initial(
            bundle: bundle, excluded: excluded, perApp: defaults.bool(forKey: Key.perApp),
            states: defaults.dictionary(forKey: Key.appStates) as? [String: Bool] ?? [:],
            global: defaults.bool(forKey: Key.enabled))
    }

    private func setEnabled(_ on: Bool, announce: Bool) {
        if foreignSource != nil {  // đang tạm ngưng: phím tắt bật/tắt không có tác dụng
            Log.write("MODE giữ nguyên: đang tạm ngưng vì bàn phím hệ thống")
            return
        }
        tap.enabled = on
        engine.reset()
        tap.invalidateFocus()
        Log.write("MODE \(on ? "VN" : "EN") app=\(tap.frontApp)")
        // Trong ứng dụng "bắt đầu ở chế độ Anh", bật/tắt chỉ có hiệu lực tạm thời.
        if !excluded.contains(tap.frontApp) {
            defaults.set(on, forKey: Key.enabled)
            if defaults.bool(forKey: Key.perApp), !tap.frontApp.isEmpty {
                var states = defaults.dictionary(forKey: Key.appStates) as? [String: Bool] ?? [:]
                states[tap.frontApp] = on
                defaults.set(states, forKey: Key.appStates)
            }
        }
        refreshTitle()
        if announce, defaults.bool(forKey: Key.showHUD) { hud.show(modeLabel) }
    }

    /// Thanh menu: biểu tượng V / E (đều là ô tô đặc) theo chế độ, kèm ⚠︎ khi thiếu quyền, 🔒 khi ô bảo mật.
    private func refreshTitle() {
        guard let button = status.button else { return }
        let image = foreignSource != nil ? StatusIcon.paused : tap.enabled ? StatusIcon.vn : StatusIcon.en
        var title = "", tip = tap.enabled ? "VNKey: đang gõ tiếng Việt" : "VNKey: đang gõ tiếng Anh"
        if !tap.isRunning {
            title = " ⚠︎"; tip = "VNKey: chưa có quyền Trợ năng"
        } else if let source = foreignSource {
            tip = "VNKey: tạm ngưng vì bàn phím hệ thống đang là “\(source)”"
        } else if IsSecureEventInputEnabled() {
            title = " 🔒"; tip = "VNKey: tạm ngưng vì đang ở ô nhập bảo mật"
        }
        if button.image !== image { button.image = image }

        if button.title != title {
            button.title = title
            button.imagePosition = title.isEmpty ? .imageOnly : .imageLeft
        }
        if button.toolTip != tip {
            button.toolTip = tip
            button.setAccessibilityLabel(tip)
        }
    }

    @objc private func appActivated(_ note: Notification) {
        engine.reset()
        tap.invalidateFocus()
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let before = tap.enabled
        tap.frontApp = app?.bundleIdentifier ?? ""
        tap.enabled = state(for: tap.frontApp)
        Log.write("APP \(tap.frontApp) -> \(tap.enabled ? "VN" : "EN")")
        inputSourceChanged()  // macOS có thể đổi bàn phím theo từng ứng dụng/tài liệu
        refreshTitle()
        // Chế độ tự đổi theo ứng dụng: báo bằng nhãn (không báo khi đang tạm ngưng), sau một nhịp để ô nhập của ứng dụng mới kịp nhận tiêu điểm.
        if tap.enabled != before, tap.isRunning, foreignSource == nil, defaults.bool(forKey: Key.showHUD), tap.frontApp != Bundle.main.bundleIdentifier {
            let app = tap.frontApp, on = tap.enabled
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.tap.frontApp == app, self.tap.enabled == on else { return }
                self.hud.show(modeLabel)
            }
        }
    }

    // MARK: - Menu

    /// Menu gọn: trạng thái, bật/tắt, kiểu gõ, Cài đặt, Thoát. Mọi tuỳ chọn khác nằm trong Cài đặt.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !tap.isRunning {
            menu.addItem(item("Cấp quyền Trợ năng để bắt đầu gõ…", #selector(showOnboarding), symbol: "exclamationmark.triangle"))
            menu.addItem(.separator())
        } else if let source = foreignSource {
            let i = item("Tạm ngưng: bàn phím hệ thống là “\(source)”", nil, symbol: "keyboard")
            i.isEnabled = false
            menu.addItem(i)
            menu.addItem(.separator())
        } else if IsSecureEventInputEnabled() {
            let i = item("Tạm ngưng: đang ở ô nhập bảo mật", nil, symbol: "lock")
            i.isEnabled = false
            menu.addItem(i)
            menu.addItem(.separator())
        }
        let toggle = item("Gõ tiếng Việt", foreignSource == nil ? #selector(toggleEnabled) : nil, on: tap.enabled)
        toggle.attributedTitle = titled("Gõ tiếng Việt", shortcut: tap.toggleHotkey.label)
        menu.addItem(toggle)
        // Chỉ để nhắc phím tắt: thao tác này cần con trỏ đang ở ngay sau từ, nên không bấm từ menu được.
        let restore = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        restore.attributedTitle = titled("Đổi từ vừa gõ", shortcut: tap.restoreHotkey.label)
        restore.isEnabled = false
        restore.toolTip = "Đổi từ vừa gõ giữa phím gốc và tiếng Việt, và nhớ cho lần sau. Dùng phím tắt ngay sau khi gõ từ."
        menu.addItem(restore)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Kiểu gõ", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let method = defaults.string(forKey: Key.method)
        for (title, tag) in [("Telex", "telex"), ("VNI", "vni")] {
            let i = item(title, #selector(pickMethod(_:)), on: method == tag, tag: tag)
            i.indentationLevel = 1
            menu.addItem(i)
        }
        menu.addItem(.separator())
        // macOS tự gắn biểu tượng (bánh răng) cho các mục menu quen thuộc; menu này chỉ dùng chữ.
        let settings = item("Cài đặt…", #selector(showVNKeySettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = item("Thoát VNKey", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    /// Tên mục kèm phím tắt in mờ (phím tắt chỉ gồm phím bổ trợ không gắn được vào keyEquivalent).
    private func titled(_ name: String, shortcut: String) -> NSAttributedString {
        let s = NSMutableAttributedString(string: name, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        s.append(
            NSAttributedString(
                string: "    " + shortcut,
                attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.tertiaryLabelColor]))
        return s
    }

    private func item(_ title: String, _ action: Selector?, on: Bool = false, tag: String? = nil, symbol: String? = nil)
        -> NSMenuItem
    {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        i.state = on ? .on : .off
        i.representedObject = tag
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return i
    }

    @objc private func toggleEnabled() { setEnabled(!tap.enabled, announce: true) }

    @objc private func showOnboarding() {
        if onboarding == nil { onboarding = OnboardingController() }
        onboarding?.update(ready: tap.isRunning)
        onboarding?.show()
    }

    @objc private func pickMethod(_ sender: NSMenuItem) {
        defaults.set(sender.representedObject as? String, forKey: Key.method)
    }

    @objc private func showVNKeySettings() {
        if settings == nil { settings = SettingsController() }
        NSApp.activate(ignoringOtherApps: true)
        settings?.window.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
