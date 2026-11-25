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
    /// Bàn phím hệ thống không phải tiếng Anh: đứng ngoài hoàn toàn cho tới khi người dùng đổi lại.
    var suspended = false
    /// Đang thật sự xử lý phím.
    var active: Bool { enabled && !suspended }
    /// Bundle ID của app đang ở trước (cập nhật từ AppDelegate).
    var frontApp = ""
    var fixAutocomplete = true
    var onToggle: (() -> Void)?
    /// Cho bộ soát lỗi: một phím vừa được gõ (mã phím, phím bổ trợ; trả về true nếu bộ soát lỗi đã dùng phím đó, khi
    /// ấy phím bị nuốt); chuột trái vừa bấm ở toạ độ màn hình này. Gọi ngay trong callback của event tap nên bên nhận
    /// chỉ được làm việc rẻ.
    var onKey: ((Int, UInt) -> Bool)?
    var onMouseDown: ((CGPoint) -> Void)?
    /// Chữ trước con trỏ vừa được thay (Đổi từ vừa gõ, gõ tắt bung ra): số ký tự UTF-16 của chữ mới, và số ký tự
    /// đứng giữa nó với con trỏ. App dùng để quét một dải sáng lên chữ đó. Gọi trong callback của event tap.
    var onReplaced: ((Int, Int) -> Void)?

    var toggleHotkey = Hotkey.defaultToggle
    var restoreHotkey = Hotkey.defaultRestore
    var clipboardHotkey = Hotkey.defaultClipboard
    /// Người dùng bấm phím tắt mở bảng clipboard (chạy cả ở chế độ EN).
    var onClipboard: (() -> Void)?

    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Bộ đệm nhận ký tự của phím, dùng lại cho mọi phím (khỏi cấp phát mỗi lần).
    private var uniBuf = [UniChar](repeating: 0, count: 4)
    /// Câu trả lời cho lần nhấn xoá lùi gần nhất; phím xoá đang lặp dùng lại nó.
    private var lastBackspaceRoute: SendPlanner.BackspaceRoute?
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
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, p, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: p, enable: true)
        return true
    }

    /// macOS tự tắt tap khi callback chậm hoặc sau khi ngủ máy: gọi định kỳ để bật lại.
    func ensureEnabled() {
        guard let p = port, !CGEvent.tapIsEnabled(tap: p) else { return }
        CGEvent.tapEnable(tap: p, enable: true)
        held.clear()
        if CGEvent.tapIsEnabled(tap: p) {
            Log.write("TAP bị hệ thống tắt -> đã bật lại")
            reset("tap bật lại", .system)
        } else {
            // Không bật lại được (thường là quyền Trợ năng vừa bị thu hồi): bỏ tap này để `isRunning` thành
            // false, thanh menu hiện cảnh báo và `start()` được thử lại định kỳ.
            Log.write("TAP không bật lại được -> huỷ, chờ tạo lại")
            stop()
            reset("tap hỏng", .system)
        }
    }

    private func stop() {
        if let s = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        if let p = port { CFMachPortInvalidate(p) }
        runLoopSource = nil
        port = nil
    }

    /// Ghi tổng kết hiệu năng của đợt phím vừa qua vào nhật ký.
    func flushPerf() {
        guard perf.keys > 0 else { return }
        Log.write("PERF \(perf.summary)")
        perf.reset()
    }

    private var state: String { engine.debugState }

    private func reset(_ why: String, _ event: FocusPolicy.Event) {
        Log.write("RESET \(why) | trước: \(state)")
        engine.reset()
        focusMayHaveChanged(event)
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
            if type == .leftMouseDown { onMouseDown?(event.location) }
            modifiers.interrupted()
            reset("chuột", .pointer)
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
        } else if clipboardHotkey.isModifierOnly, clipboardHotkey.mods == peak {
            Log.write("HOTKEY bảng clipboard (\(clipboardHotkey.label))")
            onClipboard?()
        } else if restoreHotkey.isModifierOnly, restoreHotkey.mods == peak {
            restoreWord(proxy)
        }
    }

    /// Đổi từ vừa gõ giữa phím gốc <-> tiếng Việt và ghi nhớ.
    private func restoreWord(_ proxy: CGEventTapProxy) {
        guard active else { return }
        let before = Log.enabled ? state : ""
        let out = engine.toggleLast()
        Log.write("HOTKEY đổi từ | \(before) -> \(describe(out)) | \(state)")
        if !out.isPass {
            send(out, original: nil, proxy)
            // Chữ mới là phần đầu của `out.text`; phần đuôi (dấu cách, dấu câu đã gõ sau từ) nằm sát con trỏ.
            let tail = out.text.reversed().prefix(while: { !$0.isLetter && !$0.isNumber }).count
            onReplaced?(String(out.text.dropLast(tail)).utf16.count, String(out.text.suffix(tail)).utf16.count)
        }
    }

    private func keyDown(_ proxy: CGEventTapProxy, _ event: CGEvent) -> Bool {
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
        if clipboardHotkey.matches(code: Int(code), mods: m) {
            Log.write("HOTKEY bảng clipboard (\(clipboardHotkey.label))")
            onClipboard?()
            return false
        }
        // Bảng đề nghị đang mở dùng ↑ ↓ ↩ Esc; phím khác đóng bảng rồi đi tiếp như thường.
        if let onKey, onKey(Int(code), m) {
            Log.write("KEY code=\(code) -> bảng đề nghị dùng")
            return false
        }
        if active, restoreHotkey.matches(code: Int(code), mods: m) {
            restoreWord(proxy)
            return false
        }

        var len = 0
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &uniBuf)
        let s = String(utf16CodeUnits: uniBuf, count: min(len, 4))
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        func tag() -> String {
            "KEY code=\(code) ch=\(Log.show(s))\(repeated ? " repeat" : "") mods=\(Hotkey(code: -1, mods: m, keyLabel: "").label) app=\(frontApp)"
        }

        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            Log.write("\(tag()) -> bỏ qua (phím tắt)")
            reset("phím bổ trợ", .shortcut)
            return true
        }
        guard active else {
            Log.write("\(tag()) -> bỏ qua (\(suspended ? "tạm ngưng: bàn phím hệ thống" : "đang ở chế độ EN"))")
            return true
        }

        let before = Log.enabled ? state : ""
        var focusMayMove = false
        let out: Output
        switch classifyKey(code: Int(code), chars: s) {
        case .backspace:
            var route = SendPlanner.BackspaceRoute.normal
            if fixAutocomplete, engine.isTracking {
                // Giữ phím xoá: chỉ hỏi ứng dụng ở lần nhấn đầu, các lần lặp dùng lại câu trả lời.
                if FocusPolicy.asksSelectionOnBackspace(repeated: repeated, hasPrevious: lastBackspaceRoute != nil) {
                    let f = focus()
                    route = SendPlanner.userBackspace(app: f.app, selection: f.selection, fixAutocomplete: true)
                    // Gợi ý (nếu có) đã được xử lý ở lần nhấn này; các lần lặp sau là xoá thường.
                    lastBackspaceRoute = .normal
                } else {
                    route = lastBackspaceRoute ?? .normal
                }
            }
            if route == .suggestionOnly {
                Log.write("\(tag()) -> đi thẳng (chỉ gạt gợi ý, giữ nguyên engine) | \(before)")
                return true
            }
            var o = engine.backspace(held: repeated)
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
            reset("phím điều hướng", .navigation)
            return true
        case .unprintable:
            Log.write("\(tag()) -> bỏ qua (không phải ký tự in được)")
            reset("ký tự lạ", .navigation)
            return true
        case .character(let ch):
            lastBackspaceRoute = nil
            out = engine.type(ch)
        }
        Log.write("\(tag()) | \(before) -> \(describe(out)) | \(state)")
        if !engine.note.isEmpty { Log.write("  PREDICT \(engine.note)") }
        // Enter và Tab thường chuyển tiêu điểm sang ô khác: quên ô đã nhớ SAU khi sửa xong từ hiện tại.
        defer { if focusMayMove { focusMayHaveChanged(.fieldExit) } }
        if out.isPass { return true }
        send(out, original: event, proxy)
        if let text = engine.replaced { onReplaced?(text.utf16.count, out.passKey ? 1 : 0) }
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

    /// Gọi từ AppDelegate khi đổi ứng dụng hoặc đổi chế độ.
    func invalidateFocus() { focusMayHaveChanged(.appSwitch) }

    private func focusMayHaveChanged(_ event: FocusPolicy.Event) {
        focusEpoch += 1
        lastBackspaceRoute = nil
        switch FocusPolicy.action(after: event) {
        case .drop:
            focusCache = nil
        case .refreshInBackground:
            // Bấm chuột hay phím mũi tên thường vẫn ở trong cùng ô: dùng tạm thông tin cũ và tra lại ở luồng
            // nền sau một nhịp ngắn (để ô mới, nếu có, kịp nhận tiêu điểm) thay vì tra đồng bộ ở phím sửa chữ kế.
            guard focusCache != nil else { return }
            focusCache!.created = 0
            let epoch = focusEpoch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.focusEpoch == epoch else { return }
                self.prefetchFocus()
            }
        }
    }

    /// Tra cứu ô đang nhận phím trên luồng nền ngay khi có phím đầu tiên sau khi tiêu điểm đổi, hoặc khi
    /// thông tin đã cũ. Lần tra cứu này đo được tới 85 ms ở Safari; làm ở đây thì nó không chặn phím nào.
    /// Phím sửa chữ hiếm khi là phím đầu của một từ, nên tới lúc cần thì kết quả thường đã có.
    private func prefetchFocus() {
        guard active, fixAutocomplete, !lookupPending else { return }
        if let c = focusCache, DispatchTime.now().uptimeNanoseconds - c.created <= focusCacheLifetimeNs { return }
        lookupPending = true
        let epoch = focusEpoch, front = frontApp, old = focusCache
        axQueue.async { [weak self] in
            let t0 = DispatchTime.now().uptimeNanoseconds
            let c = KeyTap.lookUpFocus(fallbackApp: front)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            DispatchQueue.main.async {
                guard let self else { return }
                self.lookupPending = false
                // Trong lúc chờ có thể đã có một lần tra đồng bộ (phím sửa chữ tới trước): giữ bản đó.
                let fresh = self.focusCache.map { $0.created > 0 && $0.created != old?.created } ?? false
                let current = FocusPolicy.acceptsBackgroundResult(sameEpoch: self.focusEpoch == epoch, haveFresh: fresh)
                if current {
                    var c = c
                    // Cùng một ô mà trước đó đã hỏi vùng chọn thất bại thì không hỏi lại.
                    if let o = self.focusCache, !o.canAskSelection, let a = o.element, let b = c.element, CFEqual(a, b) {
                        c.canAskSelection = false
                    }
                    self.focusCache = c
                }
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
        var askedAX = false
        defer {
            if askedAX {  // chỉ tính khi thật sự gọi sang ứng dụng khác
                let dt = DispatchTime.now().uptimeNanoseconds - t0
                perf.ax(dt); axNsThisKey += dt
            }
        }
        var note = focusCache?.created == 0 ? "cache(cũ)" : "cache"
        if focusCache == nil {  // tra cứu nền chưa kịp xong: đành tra ngay tại đây để không gửi sai kiểu
            focusCache = KeyTap.lookUpFocus(fallbackApp: frontApp)
            note = "lookup"
            askedAX = true
        }
        var f = Focus(app: focusCache!.app, role: focusCache!.role, selection: nil, note: note)
        guard let el = focusCache!.element, focusCache!.canAskSelection else { return f }
        askedAX = true
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
            var range: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
                let range, CFGetTypeID(range) == AXValueGetTypeID()
            else { return }
            var r = CFRange(location: 0, length: 0)
            guard AXValueGetValue(range as! AXValue, .cfRange, &r) else { return }
            // Chỉ cần đoạn ngay trước con trỏ; đọc cả tài liệu dài cho mỗi lần sửa chữ là phí.
            let start = max(0, r.location - 200)
            var window = CFRange(location: start, length: r.location - start)
            var tail: CFTypeRef?
            let result: ScreenCheck.Result
            if let w = AXValueCreate(.cfRange, &window),
                AXUIElementCopyParameterizedAttributeValue(
                    el, kAXStringForRangeParameterizedAttribute as CFString, w, &tail) == .success,
                let text = tail as? String
            {
                result = ScreenCheck.compare(value: text, caret: text.utf16.count, expected: expected)
            } else {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value) == .success,
                    let text = value as? String
                else { return }
                result = ScreenCheck.compare(value: text, caret: r.location, expected: expected)
            }
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

    /// Phát ⌘V vào ứng dụng đang ở trước, sau khi bảng clipboard đã đặt nội dung lên pasteboard. Gọi từ ngoài
    /// callback nên không có `proxy`: phát thẳng vào luồng sự kiện của phiên, vẫn gắn `kMagic`.
    /// Mã phím 9 là "V" trên bố cục ANSI/QWERTY; bố cục khác (Dvorak…) chưa được xử lý.
    func postPaste() {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down) else { continue }
            e.flags = .maskCommand
            e.setIntegerValueField(.eventSourceUserData, value: kMagic)
            e.post(tap: .cgSessionEventTap)
        }
        Log.write("CLIP phát ⌘V app=\(frontApp)")
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
