import AppKit
import Carbon.HIToolbox
import ServiceManagement
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

    private func refreshTitle() {
        var title = tap.enabled ? "VN" : "EN"
        if !tap.isRunning { title += " ⚠︎" } else if IsSecureEventInputEnabled() { title += " 🔒" }
        if status.button?.title != title { status.button?.title = title }
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !tap.isRunning {
            menu.addItem(item("⚠︎ Chưa có quyền Trợ năng — bấm để mở cài đặt", #selector(openAccessibility)))
            menu.addItem(.separator())
        } else if IsSecureEventInputEnabled() {
            menu.addItem(
                NSMenuItem(title: "🔒 Đang ở ô nhập bảo mật (mật khẩu): tạm ngưng gõ", action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
        }
        menu.addItem(item("Gõ tiếng Việt  (\(tap.toggleHotkey.label))", #selector(toggleEnabled), on: tap.enabled))
        menu.addItem(.separator())
        let method = defaults.string(forKey: Key.method)
        menu.addItem(item("Telex", #selector(pickMethod(_:)), on: method == "telex", tag: "telex"))
        menu.addItem(item("VNI", #selector(pickMethod(_:)), on: method == "vni", tag: "vni"))
        menu.addItem(.separator())
        menu.addItem(item("Cài đặt…", #selector(openSettings)))
        menu.addItem(
            item("Ghi nhật ký gỡ lỗi (lưu cả nội dung gõ)", #selector(toggleLog), on: defaults.bool(forKey: Key.debugLog)))
        menu.addItem(item("Mở tệp nhật ký", #selector(openLog)))
        if #available(macOS 13.0, *) {
            menu.addItem(
                item("Mở cùng lúc đăng nhập", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        }
        menu.addItem(.separator())
        menu.addItem(item("Thoát VNKey", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector, on: Bool = false, tag: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        i.state = on ? .on : .off
        i.representedObject = tag
        return i
    }

    @objc private func toggleEnabled() { setEnabled(!tap.enabled, announce: false) }

    @objc private func pickMethod(_ sender: NSMenuItem) {
        defaults.set(sender.representedObject as? String, forKey: Key.method)
    }

    @objc private func toggleLog() {
        defaults.set(!defaults.bool(forKey: Key.debugLog), forKey: Key.debugLog)
    }

    @objc private func openLog() {
        NSWorkspace.shared.activateFileViewerSelecting([Log.url])
    }

    @objc private func openSettings() {
        if settings == nil { settings = SettingsController() }
        NSApp.activate(ignoringOtherApps: true)
        settings?.window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        let s = SMAppService.mainApp
        do { if s.status == .enabled { try s.unregister() } else { try s.register() } } catch {
            NSLog("VNKey: không đổi được mục đăng nhập: \(error)")
        }
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
