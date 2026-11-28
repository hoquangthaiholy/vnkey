import AppKit

/// Công cụ chẩn đoán (`VNKey --ax-probe <tệp> [--wait giây]`): xem ô đang nhận phím của ứng dụng ở trước trả lời
/// những câu hỏi Trợ năng nào, để biết cách hỏi khung chữ ở trang web và ứng dụng Electron. Mở bằng
/// `open -n -g build/VNKey.app --args --ax-probe …` để tiến trình mang quyền Trợ năng của VNKey và không giành tiêu
/// điểm. KHÔNG khởi động event tap.
///
/// Riêng tư: báo cáo KHÔNG chứa chữ của ô. Chỉ có tên thuộc tính, vai trò, độ dài, toạ độ, và kết quả đúng / sai của
/// các phép so (chữ đọc theo cách A có trùng chữ đọc theo cách B không).
enum AXProbe {
    private static func copy(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
        var out: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, a as CFString, &out) == .success ? out : nil
    }

    private static func ask(_ e: AXUIElement, _ a: String, _ p: CFTypeRef) -> CFTypeRef? {
        var out: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(e, a as CFString, p, &out) == .success ? out : nil
    }

    private static func range(_ v: CFTypeRef?) -> CFRange? {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CFRange(location: 0, length: 0)
        return AXValueGetValue(v as! AXValue, .cfRange, &r) ? r : nil
    }

    private static func rect(_ v: CFTypeRef?) -> String {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return "không" }
        var r = CGRect.zero
        guard AXValueGetValue(v as! AXValue, .cgRect, &r) else { return "không phải khung" }
        return "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))"
    }

    private static func value(_ r: CFRange) -> AXValue {
        var r = r
        return AXValueCreate(.cfRange, &r)!
    }

    private static func names(_ e: AXUIElement, parameterized: Bool) -> [String] {
        var out: CFArray?
        if parameterized { AXUIElementCopyParameterizedAttributeNames(e, &out) } else { AXUIElementCopyAttributeNames(e, &out) }
        return (out as? [String] ?? []).sorted()
    }

    private static func element(_ v: CFTypeRef?) -> AXUIElement? {
        guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    /// Ô đang nhận phím: hỏi hệ thống, không được thì hỏi ứng dụng ở trước.
    private static func focused() -> (AXUIElement?, String) {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        let front = NSWorkspace.shared.frontmostApplication
        let name = front?.bundleIdentifier ?? "?"
        if let e = element(copy(system, kAXFocusedUIElementAttribute)) { return (e, name) }
        if let pid = front?.processIdentifier, let e = element(copy(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute)) {
            return (e, name + " (hỏi qua ứng dụng)")
        }
        return (nil, name)
    }

    /// `VNKey --ax-unenhance <tệp>`: tắt `AXEnhancedUserInterface` ở các trình duyệt đang chạy (bản thử 2026-11-27 đã
    /// bật nó và làm Chrome nặng), ghi kết quả từng trình duyệt vào tệp. Dùng một lần khi cần gỡ, không chạy tự động:
    /// công cụ trợ năng khác có thể đang cần cờ đó.
    static func unenhance(_ bundleIDs: Set<String>, into url: URL) { setEnhanced(false, bundleIDs, into: url) }

    /// `VNKey --ax-enhance <tệp>`: BẬT cờ đó, để đo trình duyệt nặng thêm bao nhiêu (xem `Eval/` không có; đo bằng trang
    /// thử trong Chrome). Nhớ chạy `--ax-unenhance` sau khi đo.
    static func enhance(_ bundleIDs: Set<String>, into url: URL) { setEnhanced(true, bundleIDs, into: url) }

    private static func setEnhanced(_ on: Bool, _ bundleIDs: Set<String>, into url: URL) {
        var lines: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, bundleIDs.contains(id) else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            let was = copy(element, "AXEnhancedUserInterface") as? Bool
            let err = AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
            let now = copy(element, "AXEnhancedUserInterface") as? Bool
            lines.append("\(id): trước=\(was.map(String.init) ?? "?") ghi=\(err.rawValue) sau=\(now.map(String.init) ?? "?")")
        }
        try? ((lines.isEmpty ? ["không có trình duyệt nào đang chạy"] : lines).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// `VNKey --ax-type <tệp> [--count N]`: phát N phím THẬT (t, h, u, dấu cách, lặp lại: chuỗi này engine cho đi thẳng)
    /// vào ứng dụng đang ở trước, cách nhau 80 ms, và ghi thời điểm phát từng phím (mili giây kể từ 1970) vào tệp. Dùng
    /// với trang thử để đo độ trễ từ phím tới trang, qua đúng đường phím thật (event tap của VNKey đang chạy, tiến trình
    /// chính của trình duyệt). An toàn: chỉ phát khi ứng dụng ở trước là một trình duyệt trong `allowed`; ứng dụng ở trước
    /// đổi giữa chừng thì dừng ngay.
    /// `keys`: chuỗi chữ thường và dấu cách để gõ lặp lại (bố cục QWERTY), ví dụ "tooi ddang " để thử Telex; nil thì
    /// gõ "thu ".
    /// `waitFront`: đợi tối đa chừng này giây cho tới khi một trình duyệt trong `allowed` ở phía trước liền 5 giây rồi
    /// mới gõ (để người dùng kịp chuyển sang trang cần đo). `erase`: gõ xong thì phát chừng này phím xoá lùi, trả ô về
    /// như cũ. Sau mỗi phím còn đo thời gian tiến trình chính của trình duyệt trả lời một câu hỏi Trợ năng vặt (cửa
    /// sổ đang chọn): tiến trình đó cũng là nơi phím đi qua, nên nó bận thì gõ trễ.
    static func typeKeys(count: Int, keys: String? = nil, erase: Int = 0, waitFront: Double = 0, allowed: Set<String>, into url: URL) {
        let map: [Character: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, " ": 49,
        ]
        // Giữ cả ký tự: sự kiện phím tạo từ mã phím không tự mang ký tự, mà event tap của VNKey phân loại phím theo ký
        // tự (không có thì coi là "không phải ký tự in được" và cho đi thẳng; đã gặp khi đo 2026-11-27).
        let typed = Array((keys ?? "thu ").filter { map[$0] != nil })
        let codes = typed.map { map[$0]! }
        let source = CGEventSource(stateID: .hidSystemState)
        func front() -> NSRunningApplication? {
            guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier, allowed.contains(id) else { return nil }
            return app
        }
        var stamps: [String] = [], lag: [String] = []
        var note = "xong"
        if waitFront > 0 {
            let deadline = Date().addingTimeInterval(waitFront)
            var steady = 0
            while steady < 5 {
                if Date() > deadline {
                    try? "HẾT GIỜ: trình duyệt không ở phía trước\n".write(to: url, atomically: true, encoding: .utf8)
                    return
                }
                steady = front() == nil ? 0 : steady + 1
                Thread.sleep(forTimeInterval: 1)
            }
        }
        func press(_ code: CGKeyCode, _ char: Character?) {
            let unit = char.map { Array(String($0).utf16) } ?? []
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
                if !unit.isEmpty { e?.keyboardSetUnicodeString(stringLength: unit.count, unicodeString: unit) }
                e?.post(tap: .cghidEventTap)
            }
        }
        var sent = 0
        for i in 0..<count {
            guard let app = front() else {
                note = "DỪNG ở phím \(i): ứng dụng ở trước không phải trình duyệt"
                break
            }
            stamps.append(String(format: "%.2f", Date().timeIntervalSince1970 * 1000))
            press(codes[i % codes.count], typed[i % typed.count])
            sent += 1
            Thread.sleep(forTimeInterval: 0.04)
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 1)
            let t0 = CFAbsoluteTimeGetCurrent()
            _ = copy(element, kAXFocusedWindowAttribute)
            lag.append(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))
            Thread.sleep(forTimeInterval: 0.04)
        }
        // Xoá lại những gì đã gõ (chỉ khi đã gõ đủ: gõ dở thì không đoán số ký tự).
        var erased = 0
        if erase > 0, sent == count {
            Thread.sleep(forTimeInterval: 0.8)
            for _ in 0..<erase {
                guard front() != nil else { break }
                press(51, nil)
                erased += 1
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        let body = "\(note); đã gõ \(sent) phím, đã xoá \(erased)\nax: " + lag.joined(separator: " ") + "\n" + stamps.joined(separator: "\n") + "\n"
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Đợi tới khi ô đang nhận phím là ô nhập có ít nhất 8 ký tự (tối đa `wait` giây), rồi ghi báo cáo.
    static func run(into url: URL, wait: Double) {
        let deadline = Date().addingTimeInterval(wait)
        var lines = ["AX trusted=\(AXIsProcessTrusted())"]
        while true {
            let (found, app) = focused()
            if let e = found {
                AXUIElementSetMessagingTimeout(e, 0.5)
                let role = copy(e, kAXRoleAttribute) as? String ?? "?"
                let text = copy(e, kAXValueAttribute) as? String
                if ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"].contains(role), (text?.utf16.count ?? 0) >= 8 {
                    lines.append("ứng dụng=\(app) role=\(role) subrole=\(copy(e, kAXSubroleAttribute) as? String ?? "-")")
                    lines += report(e, text ?? "")
                    break
                }
                if Date() > deadline {
                    lines.append("HẾT GIỜ: ô cuối cùng thấy được: ứng dụng=\(app) role=\(role) độ dài=\(text?.utf16.count ?? -1)")
                    break
                }
            } else if Date() > deadline {
                lines.append("HẾT GIỜ: không thấy ô nào đang nhận phím, ứng dụng=\(app)")
                break
            }
            Thread.sleep(forTimeInterval: 1)
        }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func report(_ e: AXUIElement, _ text: String) -> [String] {
        var out: [String] = []
        let units = Array(text.utf16), n = units.count
        func piece(_ r: CFRange) -> String { String(utf16CodeUnits: Array(units[r.location..<(r.location + r.length)]), count: r.length) }
        func same(_ a: String?, _ b: String) -> String {
            guard let a else { return "không đọc được" }
            if a.precomposedStringWithCanonicalMapping == b.precomposedStringWithCanonicalMapping { return "TRÙNG" }
            // Chữ đọc được có nằm ở chỗ khác trong ô không (chỉ in vị trí)?
            let found = (text as NSString).range(of: a)
            return "KHÁC (dài \(a.utf16.count)\(found.location != NSNotFound ? ", thấy trong ô ở vị trí \(found.location)" : ", không có trong ô"))"
        }
        out.append("thuộc tính: " + names(e, parameterized: false).joined(separator: " "))
        out.append("thuộc tính có tham số: " + names(e, parameterized: true).joined(separator: " "))
        out.append("độ dài AXValue=\(n) AXNumberOfCharacters=\(copy(e, kAXNumberOfCharactersAttribute) as? Int ?? -1) xuống dòng=\(units.filter { $0 == 0x0A }.count) U+FFFC=\(units.filter { $0 == 0xFFFC }.count)")
        let sel = range(copy(e, kAXSelectedTextRangeAttribute))
        out.append("AXSelectedTextRange=\(sel.map { "\($0.location)+\($0.length)" } ?? "không")")
        // Đoạn thử: 4 ký tự gần cuối ô.
        let probe = CFRange(location: max(0, n - 6), length: 4), want = piece(probe)
        out.append("đoạn thử=\(probe.location)+\(probe.length)")
        out.append("A. AXStringForRange: \(same(ask(e, kAXStringForRangeParameterizedAttribute, value(probe)) as? String, want))")
        out.append("B. AXBoundsForRange: \(rect(ask(e, kAXBoundsForRangeParameterizedAttribute, value(probe))))")

        func markerRange(_ base: Int, _ r: CFRange, on target: AXUIElement) -> CFTypeRef? {
            guard let a = ask(target, "AXTextMarkerForIndex", (base + r.location) as CFNumber),
                let b = ask(target, "AXTextMarkerForIndex", (base + r.location + r.length) as CFNumber)
            else { return nil }
            return ask(target, "AXTextMarkerRangeForUnorderedTextMarkers", [a, b] as CFArray)
        }
        func tryBase(_ label: String, _ base: Int, on target: AXUIElement) {
            guard let mr = markerRange(base, probe, on: target) else { return out.append("\(label) gốc=\(base): không dựng được marker") }
            out.append("\(label) gốc=\(base): chữ \(same(ask(target, "AXStringForTextMarkerRange", mr) as? String, want)); khung \(rect(ask(target, "AXBoundsForTextMarkerRange", mr)))")
        }
        tryBase("C. marker theo số của ô,", 0, on: e)

        // Vùng chọn dạng marker: so với vùng chọn dạng số để suy ra độ lệch giữa hai cách đánh số.
        if let selMarkers = copy(e, "AXSelectedTextMarkerRange") {
            let start = ask(e, "AXStartTextMarkerForTextMarkerRange", selMarkers)
            let index = start.flatMap { ask(e, "AXIndexForTextMarker", $0) as? Int }
            out.append("D. AXSelectedTextMarkerRange: có; marker đầu=\(start == nil ? "không" : "có") AXIndexForTextMarker=\(index.map(String.init) ?? "không")")
            if let index, let sel { tryBase("E. marker, gốc suy từ vùng chọn,", index - sel.location, on: e) }
            if let start {
                // Đi lùi từng ký tự từ con trỏ: có đi được không, và đi `k` bước có tới đúng đầu đoạn thử không.
                var m: CFTypeRef? = start
                var steps = 0
                let need = (sel?.location ?? n) - probe.location
                while steps < need, steps < 60, let cur = m { m = ask(e, "AXPreviousTextMarkerForTextMarker", cur); steps += 1 }
                if let from = m, steps == need, need >= 0 {
                    var to: CFTypeRef? = from
                    for _ in 0..<probe.length { to = to.flatMap { ask(e, "AXNextTextMarkerForTextMarker", $0) } }
                    if let to, let mr = ask(e, "AXTextMarkerRangeForUnorderedTextMarkers", [from, to] as CFArray) {
                        out.append("F. đi lùi \(steps) bước từ con trỏ: chữ \(same(ask(e, "AXStringForTextMarkerRange", mr) as? String, want)); khung \(rect(ask(e, "AXBoundsForTextMarkerRange", mr)))")
                    } else {
                        out.append("F. đi lùi \(steps) bước: không dựng được đoạn")
                    }
                } else {
                    out.append("F. đi lùi từng ký tự: dừng ở bước \(steps)/\(need) (\(m == nil ? "không đi được" : "quá xa"))")
                }
            }
        } else {
            out.append("D. AXSelectedTextMarkerRange: không")
        }

        // Marker của chính ô và của cả trang.
        let own = ask(e, "AXTextMarkerRangeForUIElement", e)
        out.append("G. AXTextMarkerRangeForUIElement(ô): \(own == nil ? "không" : "có, chữ \(same(ask(e, "AXStringForTextMarkerRange", own!) as? String, text))")")
        var node = e, hops = 0, web: AXUIElement?
        var chain: [String] = []
        while hops < 40, let parent = element(copy(node, kAXParentAttribute)) {
            node = parent
            hops += 1
            let role = copy(node, kAXRoleAttribute) as? String ?? "?"
            chain.append(role)
            if role == "AXWebArea" { web = node; break }
        }
        out.append("H. tổ tiên: \(chain.joined(separator: " < ")); vùng trang web=\(web == nil ? "không thấy" : "cách \(hops) cấp")")
        for (label, target) in [("ô", e)] + (web.map { [("vùng trang web", $0)] } ?? []) {
            let top = copy(target, "AXStartTextMarker")
            out.append("I. AXStartTextMarker trên \(label): \(top == nil ? "không" : "có")")
            if let own, let first = ask(target, "AXStartTextMarkerForTextMarkerRange", own), let top,
                let lead = ask(target, "AXTextMarkerRangeForUnorderedTextMarkers", [top, first] as CFArray)
            {
                let length = ask(target, "AXLengthForTextMarkerRange", lead) as? Int
                out.append("   độ dài từ đầu trang tới đầu ô (hỏi \(label))=\(length.map(String.init) ?? "không")")
                if let length { tryBase("J. marker, gốc theo độ dài, hỏi \(label),", length, on: target) }
            }
        }
        if let web, let mine = copy(e, "AXStartTextMarker") {
            let origin = ask(web, "AXIndexForTextMarker", mine) as? Int
            out.append("M. vị trí đầu ô trong trang (AXIndexForTextMarker hỏi vùng trang web, marker đầu của ô)=\(origin.map(String.init) ?? "không")")
            if let origin {
                tryBase("N. marker hỏi vùng trang web,", origin, on: web)
                // Cùng marker đó nhưng hỏi chữ và khung trên chính ô.
                if let mr = markerRange(origin, probe, on: web) {
                    out.append("O. cùng đoạn, hỏi trên ô: chữ \(same(ask(e, "AXStringForTextMarkerRange", mr) as? String, want)); khung \(rect(ask(e, "AXBoundsForTextMarkerRange", mr)))")
                }
                // Cả ô và một đoạn dài hơn, để xem xuống dòng có làm lệch số không.
                let all = CFRange(location: 0, length: n)
                if let mr = markerRange(origin, all, on: web) { out.append("P. cả ô qua marker: chữ \(same(ask(web, "AXStringForTextMarkerRange", mr) as? String, text))") }
            }
            // Đi từng ký tự từ marker đầu của ô.
            var m: CFTypeRef? = mine
            for _ in 0..<probe.location { m = m.flatMap { ask(e, "AXNextTextMarkerForTextMarker", $0) } }
            var to = m
            for _ in 0..<probe.length { to = to.flatMap { ask(e, "AXNextTextMarkerForTextMarker", $0) } }
            if let m, let to, let mr = ask(e, "AXTextMarkerRangeForUnorderedTextMarkers", [m, to] as CFArray) {
                out.append("Q. đi \(probe.location) bước từ đầu ô: chữ \(same(ask(e, "AXStringForTextMarkerRange", mr) as? String, want)); khung \(rect(ask(e, "AXBoundsForTextMarkerRange", mr)))")
            } else {
                out.append("Q. đi từng ký tự từ đầu ô: không được")
            }
            // Ghi: bôi chọn và thay chữ có được phép không (chỉ hỏi, KHÔNG ghi gì).
            var settable: DarwinBoolean = false
            for attr in [kAXSelectedTextRangeAttribute, kAXSelectedTextAttribute, kAXValueAttribute, "AXSelectedTextMarkerRange"] {
                let err = AXUIElementIsAttributeSettable(e, attr as CFString, &settable)
                out.append("R. ghi được \(attr): \(err == .success ? (settable.boolValue ? "có" : "không") : "lỗi \(err.rawValue)")")
            }
        }
        if let web {
            tryBase("K. marker theo số của ô, hỏi vùng trang web,", 0, on: web)
            out.append("   thuộc tính có tham số của vùng trang web: " + names(web, parameterized: true).joined(separator: " "))
        }

        // Các phần tử con: có phải mỗi đoạn chữ là một phần tử trả lời được khung không.
        let kids = (copy(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        out.append("L. phần tử con: \(kids.count): " + kids.prefix(8).map { copy($0, kAXRoleAttribute) as? String ?? "?" }.joined(separator: " "))
        func describe(_ k: AXUIElement, _ depth: Int) {
            let role = copy(k, kAXRoleAttribute) as? String ?? "?"
            let v = copy(k, kAXValueAttribute) as? String
            var line = String(repeating: "  ", count: depth) + "- \(role) độ dài=\(v?.utf16.count ?? -1)"
            if let v, v.utf16.count >= 2 {
                let r = CFRange(location: 0, length: min(4, v.utf16.count))
                line += " AXBoundsForRange(0+\(r.length))=\(rect(ask(k, kAXBoundsForRangeParameterizedAttribute, value(r))))"
                line += " có trong ô ở vị trí \((text as NSString).range(of: v).location == NSNotFound ? -1 : (text as NSString).range(of: v).location)"
            }
            out.append(line)
            if depth < 3 { for c in ((copy(k, kAXChildrenAttribute) as? [AXUIElement]) ?? []).prefix(4) { describe(c, depth + 1) } }
        }
        for k in kids.prefix(4) { describe(k, 1) }
        if let first = kids.first { out.append("   thuộc tính có tham số của phần tử con đầu: " + names(first, parameterized: true).joined(separator: " ")) }
        return out
    }
}
