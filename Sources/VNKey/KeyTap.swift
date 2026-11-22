import AppKit
import VNEngine
import VNKeyCore

/// Đánh dấu sự kiện do chính VNKey phát ra để không xử lý lại.
private let kMagic: Int64 = 0x564E_4B59

private func tapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
    return tap.handle(proxy, type, event) ? Unmanaged.passUnretained(event) : nil
}

/// Chặn phím toàn hệ thống (CGEventTap), đưa qua Engine rồi phát lại xoá lùi + văn bản.
final class KeyTap {
    let engine: Engine
    var enabled = true
    /// Bundle ID của app đang ở trước (cập nhật từ AppDelegate).
    var frontApp = ""
    var fixAutocomplete = true
    var onToggle: (() -> Void)?

    var toggleHotkey = Hotkey.defaultToggle
    var restoreHotkey = Hotkey.defaultRestore

    private var port: CFMachPort?
    private var modifiers = ModifierTracker()
    private let source = CGEventSource(stateID: .privateState)

    init(engine: Engine) { self.engine = engine }

    var isRunning: Bool { port != nil }

    /// false nếu chưa được cấp quyền Trợ năng.
    func start() -> Bool {
        if port != nil { return true }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        guard
            let p = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: tapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        port = p
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, p, 0), .commonModes)
        CGEvent.tapEnable(tap: p, enable: true)
        return true
    }

    /// macOS tự tắt tap khi callback chậm hoặc sau khi ngủ máy: gọi định kỳ để bật lại.
    func ensureEnabled() {
        if let p = port, !CGEvent.tapIsEnabled(tap: p) {
            CGEvent.tapEnable(tap: p, enable: true)
            Log.write("TAP bị hệ thống tắt -> đã bật lại")
            reset("tap bật lại")
        }
    }

    private func reset(_ why: String) {
        Log.write("RESET \(why) | trước: \(engine.debugState)")
        engine.reset()
    }

    private func describe(_ out: Output) -> String {
        out.isPass ? "pass" : "bs=\(out.backspaces) text=\(Log.show(out.text)) passKey=\(out.passKey)"
    }

    fileprivate func handle(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Log.write("TAP nhận sự kiện bị tắt: \(type == .tapDisabledByTimeout ? "timeout" : "user input")")
            ensureEnabled()
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            modifiers.interrupted()
            reset("chuột")
        case .flagsChanged:
            trackModifiers(event.flags, proxy)
        case .keyDown:
            return keyDown(proxy, event)
        default: break
        }
        return true
    }

    private func mods(_ flags: CGEventFlags) -> UInt { UInt(flags.rawValue) & Hotkey.modMask }

    /// Phím tắt chỉ gồm phím bổ trợ: kích hoạt khi nhấn rồi thả mà không kèm phím khác.
    private func trackModifiers(_ flags: CGEventFlags, _ proxy: CGEventTapProxy) {
        guard let peak = modifiers.flagsChanged(mods(flags)), !hotkeyRecording else { return }
        if toggleHotkey.isModifierOnly, toggleHotkey.mods == peak {
            Log.write("HOTKEY bật/tắt (\(toggleHotkey.label))")
            onToggle?()
        } else if restoreHotkey.isModifierOnly, restoreHotkey.mods == peak {
            restoreWord(proxy)
        }
    }

    /// Đổi từ vừa gõ giữa phím gốc <-> tiếng Việt và ghi nhớ.
    private func restoreWord(_ proxy: CGEventTapProxy) {
        guard enabled else { return }
        let before = engine.debugState
        let out = engine.toggleLast()
        Log.write("HOTKEY đổi từ | \(before) -> \(describe(out)) | \(engine.debugState)")
        if !out.isPass { send(out, original: nil, proxy) }
    }

    private func keyDown(_ proxy: CGEventTapProxy, _ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == kMagic { return true }
        modifiers.interrupted()
        if hotkeyRecording { return true }
        let flags = event.flags
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let m = mods(flags)

        if toggleHotkey.matches(code: Int(code), mods: m) {
            Log.write("HOTKEY bật/tắt (\(toggleHotkey.label))")
            onToggle?()
            return false
        }
        if enabled, restoreHotkey.matches(code: Int(code), mods: m) {
            restoreWord(proxy)
            return false
        }

        var len = 0
        var buf = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &buf)
        let s = String(utf16CodeUnits: buf, count: len)
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        func tag() -> String {
            "KEY code=\(code) ch=\(Log.show(s))\(repeated ? " repeat" : "") mods=\(Hotkey(code: -1, mods: m, keyLabel: "").label) app=\(frontApp)"
        }

        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            Log.write("\(tag()) -> bỏ qua (phím tắt)")
            reset("phím bổ trợ")
            return true
        }
        guard enabled else {
            Log.write("\(tag()) -> bỏ qua (đang ở chế độ EN)")
            return true
        }

        let before = engine.debugState
        let out: Output
        switch classifyKey(code: Int(code), chars: s) {
        case .backspace:
            var route = SendPlanner.BackspaceRoute.normal
            if fixAutocomplete, engine.isTracking {
                let f = focus()
                route = SendPlanner.userBackspace(app: f.app, selection: f.selection, fixAutocomplete: true)
            }
            if route == .suggestionOnly {
                Log.write("\(tag()) -> đi thẳng (chỉ gạt gợi ý, giữ nguyên engine) | \(before)")
                return true
            }
            var o = engine.backspace()
            if o.isPass, route == .planned { o = Output(backspaces: 1, text: "", passKey: false) }
            out = o
        case .newline: out = engine.type("\n")
        case .tab: out = engine.type("\t")
        case .navigation:
            Log.write("\(tag()) -> bỏ qua (phím điều hướng)")
            reset("phím điều hướng")
            return true
        case .unprintable:
            Log.write("\(tag()) -> bỏ qua (không phải ký tự in được)")
            reset("ký tự lạ")
            return true
        case .character(let ch): out = engine.type(ch)
        }
        Log.write("\(tag()) | \(before) -> \(describe(out)) | \(engine.debugState)")
        if out.isPass { return true }
        send(out, original: event, proxy)
        return false
    }

    // MARK: - Phát phím

    private var bundleByPid: [pid_t: String] = [:]

    private struct Focus {
        var app: String
        var role = "?"
        /// Độ dài vùng đang bôi chọn trong ô nhập; nil nếu app không cho biết.
        var selection: Int?
        var note = ""
    }

    /// Ô đang thực sự nhận phím. Khác với app "ở trước": Spotlight và các bảng nổi
    /// nhận phím mà không trở thành app ở trước.
    private func focus() -> Focus {
        var f = Focus(app: frontApp)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref)
        guard err == .success, let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            f.note = "focusErr=\(err.rawValue)"
            return f
        }
        let el = ref as! AXUIElement
        AXUIElementSetMessagingTimeout(el, 0.1)
        var pid: pid_t = 0
        if AXUIElementGetPid(el, &pid) == .success {
            if let hit = bundleByPid[pid] {
                f.app = hit
            } else if let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
                if bundleByPid.count > 200 { bundleByPid.removeAll() }
                bundleByPid[pid] = id
                f.app = id
            }
        }
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role) == .success, let r = role as? String {
            f.role = r
        }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value) == .success,
            let v = value as? String
        {
            f.note = "valueLen=\(v.count) "
        }
        var range: CFTypeRef?
        let rerr = AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &range)
        if rerr == .success, let range, CFGetTypeID(range) == AXValueGetTypeID() {
            var r = CFRange(location: 0, length: 0)
            if AXValueGetValue(range as! AXValue, .cfRange, &r) { f.selection = r.length }
        } else {
            f.note += "rangeErr=\(rerr.rawValue)"
        }
        return f
    }

    private func send(_ out: Output, original: CGEvent?, _ proxy: CGEventTapProxy) {
        // Chỉ hỏi Accessibility khi sắp xoá lùi: đó là lúc gợi ý tự điền có thể làm hỏng kết quả.
        let f = out.backspaces > 0 && fixAutocomplete ? focus() : Focus(app: frontApp)
        let plan = SendPlanner.plan(
            backspaces: out.backspaces, text: out.text, passKey: out.passKey, app: f.app, selection: f.selection,
            fixAutocomplete: fixAutocomplete)
        Log.write(
            "  SEND mode=\(plan.mode) \(plan.steps) focus=\(f.app) role=\(f.role) sel=\(f.selection.map(String.init) ?? "nil") \(f.note)"
        )
        let arrow: CGEventFlags = [.maskNumericPad, .maskSecondaryFn]
        for step in plan.steps {
            switch step {
            case .arrowLeft: postKey(123, proxy, flags: arrow)
            case .arrowRight: postKey(124, proxy, flags: arrow)
            case .backspace(let n): for _ in 0..<n { postKey(51, proxy) }
            case .text(let t): postText(t, proxy)
            case .original:
                if let copy = original?.copy() {
                    copy.setIntegerValueField(.eventSourceUserData, value: kMagic)
                    copy.tapPostEvent(proxy)
                }
            }
        }
    }

    private func post(_ e: CGEvent?, _ proxy: CGEventTapProxy, flags: CGEventFlags = []) {
        guard let e else { return }
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: kMagic)
        e.tapPostEvent(proxy)
    }

    private func postKey(_ code: CGKeyCode, _ proxy: CGEventTapProxy, flags: CGEventFlags = []) {
        post(CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true), proxy, flags: flags)
        post(CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false), proxy, flags: flags)
    }

    private func postText(_ text: String, _ proxy: CGEventTapProxy) {
        for chunk in SendPlanner.chunks(text) {
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                post(e, proxy)
            }
        }
    }
}
