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
    private var perf = PerfStats()
    private var held = HeldKeys()
    /// Số thứ tự phím; dùng để bỏ phép đối chiếu màn hình nếu người dùng đã gõ tiếp.
    private var keySeq = 0
    /// Thời gian hỏi Accessibility trong phím đang xử lý (ns).
    private var axNsThisKey: UInt64 = 0
    private let source = CGEventSource(stateID: .privateState)

    init(engine: Engine) { self.engine = engine }

    var isRunning: Bool { port != nil }

    /// false nếu chưa được cấp quyền Trợ năng.
    func start() -> Bool {
        if port != nil { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
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
            held.clear()
            Log.write("TAP bị hệ thống tắt -> đã bật lại")
            reset("tap bật lại")
        }
    }

    /// Ghi tổng kết hiệu năng của đợt phím vừa qua vào nhật ký.
    func flushPerf() {
        guard perf.keys > 0 else { return }
        Log.write("PERF \(perf.summary)")
        perf.reset()
    }

    private func reset(_ why: String) {
        Log.write("RESET \(why) | trước: \(engine.debugState)")
        engine.reset()
        invalidateFocus()
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
        case .keyUp:
            if event.getIntegerValueField(.eventSourceUserData) != kMagic {
                held.up(Int(event.getIntegerValueField(.keyboardEventKeycode)))
            }
        case .keyDown:
            if event.getIntegerValueField(.eventSourceUserData) == kMagic { return true }
            held.down(Int(event.getIntegerValueField(.keyboardEventKeycode)))
            axNsThisKey = 0
            keySeq += 1
            let t0 = DispatchTime.now().uptimeNanoseconds
            let epochBefore = focusEpoch
            let pass = keyDown(proxy, event)
            // Phím vừa làm tiêu điểm có thể đổi (⌘Space mở Spotlight, Tab, Enter…) thì CHƯA tra cứu:
            // ô mới chưa kịp nhận tiêu điểm, tra bây giờ sẽ nhớ nhầm ô cũ. Đợi phím thường kế tiếp.
            if focusEpoch == epochBefore { prefetchFocus() }
            let dt = DispatchTime.now().uptimeNanoseconds - t0
            perf.key(dt)
            if dt >= 2_000_000 {
                Log.write(String(format: "SLOW dt=%.2fms ax=%.2fms app=%@", Double(dt) / 1e6, Double(axNsThisKey) / 1e6, frontApp))
            }
            if perf.keys >= 200 { flushPerf() }
            return pass
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
        var focusMayMove = false
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
        case .newline:
            out = engine.type("\n")
            focusMayMove = true
        case .tab:
            out = engine.type("\t")
            focusMayMove = true
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
        // Enter và Tab thường chuyển tiêu điểm sang ô khác: quên ô đã nhớ SAU khi sửa xong từ hiện tại.
        defer { if focusMayMove { invalidateFocus() } }
        if out.isPass { return true }
        send(out, original: event, proxy)
        return false
    }

    // MARK: - Phát phím

    private struct Focus {
        var app: String
        var role = "?"
        /// Độ dài vùng đang bôi chọn trong ô nhập; nil nếu app không cho biết.
        var selection: Int?
        var note = ""
    }

    /// Ô đang nhận phím, nhớ lại cho tới khi tiêu điểm có thể đã đổi (chuột, phím tắt, Tab, Enter,
    /// đổi ứng dụng). Hỏi Accessibility là lời gọi đồng bộ sang ứng dụng khác, đo được tới 45 ms/lần.
    private struct FocusCache {
        var element: AXUIElement?
        var app: String
        var role: String
        /// Ứng dụng có trả lời được câu hỏi về vùng bôi chọn không; sai một lần thì thôi hỏi.
        var canAskSelection: Bool
        var created = DispatchTime.now().uptimeNanoseconds
    }
    /// Lưới an toàn: tiêu điểm đôi khi đổi mà không có sự kiện nào báo (trang web tự chuyển ô),
    /// nên sau khoảng này thông tin được làm mới ở luồng nền (trong lúc đó vẫn dùng bản cũ).
    private let focusCacheLifetimeNs: UInt64 = 5_000_000_000
    private var focusCache: FocusCache?
    /// Tăng mỗi lần tiêu điểm có thể đã đổi; kết quả tra cứu nền của đợt cũ bị bỏ.
    private var focusEpoch = 0
    private var lookupPending = false
    private let axQueue = DispatchQueue(label: "local.vnkey.ax", qos: .userInteractive)

    func invalidateFocus() {
        focusCache = nil
        focusEpoch += 1
    }

    /// Tra cứu ô đang nhận phím trên luồng nền ngay khi có phím đầu tiên sau khi tiêu điểm đổi, hoặc khi
    /// thông tin đã cũ. Lần tra cứu này đo được tới 85 ms ở Safari; làm ở đây thì nó không chặn phím nào.
    /// Phím sửa chữ hiếm khi là phím đầu của một từ, nên tới lúc cần thì kết quả thường đã có.
    private func prefetchFocus() {
        guard enabled, fixAutocomplete, !lookupPending else { return }
        if let c = focusCache, DispatchTime.now().uptimeNanoseconds - c.created <= focusCacheLifetimeNs { return }
        lookupPending = true
        let epoch = focusEpoch, front = frontApp
        axQueue.async { [weak self] in
            let t0 = DispatchTime.now().uptimeNanoseconds
            let c = KeyTap.lookUpFocus(fallbackApp: front)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            DispatchQueue.main.async {
                guard let self else { return }
                self.lookupPending = false
                let current = self.focusEpoch == epoch
                if current { self.focusCache = c }
                Log.write(String(format: "FOCUS nền %.2fms app=%@ role=%@%@", ms, c.app, c.role, current ? "" : " (bỏ: tiêu điểm đã đổi)"))
            }
        }
    }

    /// Chạy được trên luồng bất kỳ: không đụng tới trạng thái của KeyTap.
    private static func lookUpFocus(fallbackApp: String) -> FocusCache {
        var c = FocusCache(element: nil, app: fallbackApp, role: "?", canAskSelection: false)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
            let ref, CFGetTypeID(ref) == AXUIElementGetTypeID()
        else { return c }
        let el = ref as! AXUIElement
        AXUIElementSetMessagingTimeout(el, 0.1)
        c.element = el
        var pid: pid_t = 0
        if AXUIElementGetPid(el, &pid) == .success,
            let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        {
            c.app = id
        }
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role) == .success, let r = role as? String {
            c.role = r
        }
        // Chỉ hỏi vùng chọn ở ô một dòng, và không hỏi Spotlight (nó không báo gợi ý qua vùng chọn).
        c.canAskSelection = SendPlanner.shouldAskSelection(app: c.app, role: c.role)
        return c
    }

    /// Ô đang thực sự nhận phím. Khác với app "ở trước": Spotlight và các bảng nổi
    /// nhận phím mà không trở thành app ở trước.
    private func focus() -> Focus {
        let t0 = DispatchTime.now().uptimeNanoseconds
        defer {
            let dt = DispatchTime.now().uptimeNanoseconds - t0
            perf.ax(dt); axNsThisKey += dt
        }
        var note = "cache"
        if focusCache == nil {  // tra cứu nền chưa kịp xong: đành tra ngay tại đây
            focusCache = KeyTap.lookUpFocus(fallbackApp: frontApp)
            note = "lookup"
        }
        var f = Focus(app: focusCache!.app, role: focusCache!.role, selection: nil, note: note)
        guard let el = focusCache!.element, focusCache!.canAskSelection else { return f }
        var range: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &range)
        if err == .success, let range, CFGetTypeID(range) == AXValueGetTypeID() {
            var r = CFRange(location: 0, length: 0)
            if AXValueGetValue(range as! AXValue, .cfRange, &r) { f.selection = r.length }
        } else {
            focusCache!.canAskSelection = false
            f.note += " rangeErr=\(err.rawValue)"
        }
        return f
    }

    private func send(_ out: Output, original: CGEvent?, _ proxy: CGEventTapProxy) {
        // Chỉ hỏi Accessibility khi sắp xoá lùi: đó là lúc gợi ý tự điền có thể làm hỏng kết quả.
        let f = out.backspaces > 0 && fixAutocomplete ? focus() : Focus(app: frontApp)
        let plan = SendPlanner.plan(
            backspaces: out.backspaces, text: out.text, passKey: out.passKey, app: f.app, selection: f.selection,
            fixAutocomplete: fixAutocomplete, role: f.role)
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
        verifyScreen(mode: plan.mode)
    }

    /// Khi bật nhật ký: sau một lần sửa chữ, đọc lại nội dung ô nhập ở luồng nền và ghi `VERIFY` nếu
    /// màn hình khác với điều engine mong đợi. Bỏ qua nếu người dùng đã gõ tiếp (màn hình đã đổi).
    private func verifyScreen(mode: String) {
        let expected = engine.currentWord
        guard Log.enabled, !expected.isEmpty, let el = focusCache?.element else { return }
        let seq = keySeq, app = focusCache?.app ?? "?"
        axQueue.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            var value: CFTypeRef?, range: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value) == .success,
                let text = value as? String,
                AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
                let range, CFGetTypeID(range) == AXValueGetTypeID()
            else { return }
            var r = CFRange(location: 0, length: 0)
            guard AXValueGetValue(range as! AXValue, .cfRange, &r) else { return }
            let result = ScreenCheck.compare(value: text, caret: r.location, expected: expected)
            DispatchQueue.main.async {
                guard let self, self.keySeq == seq else { return }
                switch result {
                case .match: Log.write("  VERIFY khớp app=\(app) mode=\(mode)")
                case .mismatch(let e, let a):
                    Log.write("  VERIFY LỆCH app=\(app) mode=\(mode) engine=\(Log.show(e)) màn hình=…\(Log.show(a)) sel=\(r.length)")
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
        // Mã phím chở chữ không được trùng phím người dùng đang giữ (xem HeldKeys).
        let carrier = CGKeyCode(held.carrier)
        if carrier != 0 { Log.write("  CARRIER mã phím \(carrier) (phím A đang được giữ)") }
        for chunk in SendPlanner.chunks(text) {
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: source, virtualKey: carrier, keyDown: down)
                e?.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
                e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                post(e, proxy)
            }
        }
    }
}
