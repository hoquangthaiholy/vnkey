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
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var settings: SettingsController?
    private var lastSecure = false
    private var ticks = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: Key.registered)
        // Chế độ chụp giao diện: vẽ các cửa sổ ra PNG rồi thoát, KHÔNG khởi động event tap
        // (một bản VNKey khác có thể đang chạy; hai tap cùng lúc sẽ xử lý phím hai lần).
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            status.isVisible = false
            Snapshot.run(into: URL(fileURLWithPath: CommandLine.arguments[i + 1]), dark: CommandLine.arguments.contains("--dark"))
            NSApp.terminate(nil)
            return
        }
        Log.enabled = defaults.bool(forKey: Key.debugLog)
        let info = Bundle.main.infoDictionary
        Log.write(
            "==== VNKey \(info?["CFBundleShortVersionString"] ?? "?") khởi động, macOS \(ProcessInfo.processInfo.operatingSystemVersionString), AX trusted=\(AXIsProcessTrusted())"
        )
        engine.lexicon = lexicon
        engine.onLearn = { [unowned self] in
            defaults.set(Array(engine.preferRaw), forKey: Key.preferRaw)
            defaults.set(Array(engine.preferVN), forKey: Key.preferVN)
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

        if !tap.start() {
            // Hiện hộp thoại hệ thống mời cấp quyền Trợ năng; thử lại định kỳ cho tới khi được cấp.
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [unowned self] _ in
            if !tap.isRunning, tap.start() { Log.write("TAP đã khởi động (có quyền Trợ năng)") }
            tap.ensureEnabled()
            ticks += 1
            if ticks % 15 == 0 { tap.flushPerf() }  // tổng kết hiệu năng mỗi 30 giây nếu có gõ
            let secure = IsSecureEventInputEnabled()
            if secure != lastSecure {
                lastSecure = secure
                Log.write("SECURE INPUT \(secure ? "bật: bộ gõ không nhận được phím" : "tắt")")
            }
            refreshTitle()
        }
        refreshTitle()
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tap.flushPerf()
        Log.write("==== VNKey thoát")
    }

    /// Mở lại app khi đang chạy (từ Finder/Spotlight) = mở cửa sổ cài đặt.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
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
        c.teenInitials = defaults.bool(forKey: Key.teen)
        c.autoRestore = defaults.bool(forKey: Key.autoRestore)
        c.expandTeen = defaults.bool(forKey: Key.expandTeen)
        c.codeAware = defaults.bool(forKey: Key.codeAware)
        c.fixTransposition = defaults.bool(forKey: Key.fixTransposition)
        c.contextAware = defaults.bool(forKey: Key.contextAware)
        c.autoCapitalize = defaults.bool(forKey: Key.autoCapitalize)
        c.tidyPunctuation = defaults.bool(forKey: Key.tidyPunctuation)
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
        if announce, defaults.bool(forKey: Key.showHUD) { hud.show(on ? "VN" : "EN") }
    }

    /// Thanh menu: biểu tượng V (đặc) / E (viền) theo chế độ, kèm ⚠︎ khi thiếu quyền, 🔒 khi ô bảo mật.
    private func refreshTitle() {
        guard let button = status.button else { return }
        let image = tap.enabled ? StatusIcon.vn : StatusIcon.en
        var title = "", tip = tap.enabled ? "VNKey: đang gõ tiếng Việt" : "VNKey: đang gõ tiếng Anh"
        if !tap.isRunning {
            title = " ⚠︎"; tip = "VNKey: chưa có quyền Trợ năng"
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
        tap.frontApp = app?.bundleIdentifier ?? ""
        tap.enabled = state(for: tap.frontApp)
        Log.write("APP \(tap.frontApp) -> \(tap.enabled ? "VN" : "EN")")
        refreshTitle()
    }

    // MARK: - Menu

    /// Menu gọn: trạng thái, bật/tắt, bảng gõ, Cài đặt, Thoát. Mọi tuỳ chọn khác nằm trong Cài đặt.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !tap.isRunning {
            menu.addItem(item("Cấp quyền Trợ năng để bắt đầu gõ…", #selector(openAccessibility), symbol: "exclamationmark.triangle"))
            menu.addItem(.separator())
        } else if IsSecureEventInputEnabled() {
            let i = item("Tạm ngưng: đang ở ô nhập bảo mật", nil, symbol: "lock")
            i.isEnabled = false
            menu.addItem(i)
            menu.addItem(.separator())
        }
        let toggle = item("Gõ tiếng Việt", #selector(toggleEnabled), on: tap.enabled)
        toggle.attributedTitle = titled("Gõ tiếng Việt", shortcut: tap.toggleHotkey.label)
        menu.addItem(toggle)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Bảng gõ", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let method = defaults.string(forKey: Key.method)
        for (title, tag) in [("Telex", "telex"), ("VNI", "vni")] {
            let i = item(title, #selector(pickMethod(_:)), on: method == tag, tag: tag)
            i.indentationLevel = 1
            menu.addItem(i)
        }
        menu.addItem(.separator())
        let settings = item("Cài đặt…", #selector(openSettings))
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

    @objc private func toggleEnabled() { setEnabled(!tap.enabled, announce: false) }

    @objc private func pickMethod(_ sender: NSMenuItem) {
        defaults.set(sender.representedObject as? String, forKey: Key.method)
    }

    @objc private func openSettings() {
        if settings == nil { settings = SettingsController() }
        NSApp.activate(ignoringOtherApps: true)
        settings?.window.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
