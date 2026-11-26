import AppKit
import VNEngine
import VNKeyCore

/// Soát lỗi trong ô đang nhập, theo cách các công cụ soát chính tả làm trên desktop: đọc chữ của ô qua Trợ năng,
/// đưa cho `Proofreader`, hỏi ứng dụng khung của từng chỗ nghi sai (`AXBoundsForRange`) rồi vẽ nét gạch chân lên
/// một cửa sổ trong suốt phủ bên trên. Rê chuột lên chữ bị gạch thì nền chữ sáng dần và bảng đề nghị hiện ra (không
/// cần bấm, người dùng chọn 2026-11-25); chọn một đề nghị thì thay chữ bằng cách ghi `AXSelectedText`. Nét gạch đỏ
/// là gõ nhầm, cam là sai chính tả; dòng đang chọn trong bảng đề nghị dùng màu nhấn của macOS. VNKey KHÔNG tự thay chữ (người dùng chốt 2026-11-25).
///
/// Riêng tư: chữ của ô chỉ nằm trong bộ nhớ cho tới lần soát sau, không lưu, không ghi vào nhật ký (nhật ký chỉ có
/// số lượng, loại lỗi, thời gian). Ô mật khẩu không bao giờ được đọc.
///
/// Giới hạn hiện nay (chưa kiểm chứng trên ứng dụng thật):
/// - chỉ ứng dụng trả lời theo số thứ tự ký tự (AppKit: TextEdit, Ghi chú, Mail…); trang web và Electron dùng
///   text marker, chưa làm;
/// - không có thông báo cuộn đáng tin nên hỏi lại định kỳ: nét gạch bám theo chữ chậm một nhịp;
/// - ứng dụng không cho ghi `AXSelectedText` thì không thay được (có ghi nhật ký), chưa có đường dự phòng.
final class Proofing {
    /// Một lần đọc ô đang nhập, làm ở hàng đợi nền.
    private struct Snapshot {
        var element: AXUIElement
        /// Cửa sổ chứa ô nhập, để nghe khi nó bị dời hay đổi cỡ.
        var window: AXUIElement?
        var pid: pid_t
        /// Đoạn chữ được soát và vị trí (UTF-16) của nó trong toàn bộ nội dung ô.
        var text: String
        var base: Int
        var caret: Int?
        /// Vùng nhìn thấy của ô, toạ độ AX (gốc trên-trái). nil = không biết.
        var clip: CGRect?
    }

    /// Một chỗ đang được gạch chân: khung từng đoạn (toạ độ Cocoa) để vẽ và để biết chuột bấm trúng.
    private struct Mark {
        var issue: ProofIssue
        var rects: [NSRect]
        /// Đỏ: gõ nhầm (thiếu dấu, trật phím, đảo phím, lỗi gõ quen). Cam: sai chính tả (người dùng chọn 2026-11-25).
        var color: NSColor { issue.isMisspelling ? .systemOrange : .systemRed }
    }

    private let reader = Proofreader()
    private let queue = DispatchQueue(label: "vnkey.proofing", qos: .utility)
    private var timer: Timer?
    private var busy = false
    private var enabled = false

    private var element: AXUIElement?
    private var text = ""
    private var base = 0
    private var caret: Int?
    private var issues: [ProofIssue] = []
    private var marks: [Mark] = []
    private var lastKey = Date.distantPast
    /// Nghe cửa sổ chứa ô nhập bị dời / đổi cỡ: lúc đó nét gạch được ẩn ngay (người dùng yêu cầu 2026-11-25), và chỉ
    /// hiện lại khi khung ô nhập đã đứng yên qua hai nhịp soát.
    private var observer: AXObserver?
    private var observed: AXUIElement?
    private var settling = false
    private var movedAt = Date.distantPast
    private var lastClip: CGRect?
    /// Chữ trong ô đã đổi từ lần soát gần nhất (đang gõ dở, vừa thay chữ, vừa đổi cài đặt): soát lại khi ngừng gõ.
    private var stale = false

    private lazy var overlay = UnderlineOverlay()
    private lazy var popover = SuggestionPanel()
    private var shownIssue: ProofIssue?
    /// Khung (toạ độ Cocoa) của chỗ đang mở bảng đề nghị, để chuột đi từ chữ xuống bảng không làm bảng đóng.
    private var shownRects: [NSRect] = []
    /// Theo dõi chuột bằng cách hỏi vị trí 20 lần/giây, chỉ khi đang có nét gạch hoặc bảng đề nghị. (Không thêm
    /// `mouseMoved` vào event tap: callback của tap sẽ chạy cho mọi lần nhích chuột.)
    private var hoverTimer: Timer?
    private var hovered: ProofIssue?
    private var hoverSince = Date.distantPast
    private var leftAt: Date?
    private static let hoverDelay = 0.06, leaveDelay = 0.35

    /// VNKey có đang làm việc không (đang bật, không tạm ngưng).
    var isActive: () -> Bool = { true }
    /// Chữ trong ô vừa bị thay ngoài luồng gõ: engine phải quên trạng thái đang theo dõi.
    var didReplace: () -> Void = {}
    /// Người dùng thêm các từ này (chữ thường) vào từ điển của họ: lưu lại, không bao giờ gạch nữa.
    var ignore: ([String]) -> Void = { _ in }
    /// Từ không soát theo cài đặt, và từ người dùng bảo "bỏ qua lần này" (chỉ tới khi VNKey chạy lại).
    /// "Sửa cả câu": công tắc trong Cài đặt; câu đang được đề nghị (vị trí trong ô, câu gốc, câu đã sửa); số thứ tự
    /// lần hỏi, để câu trả lời tới muộn cho một bảng đã đóng thì bị bỏ.
    private var sentenceOn = false
    private var asking = 0

    // Bảng AI (riêng với bảng đề nghị cho từ; người dùng yêu cầu tách 2026-11-25). Mở từ nút ✦ hiện ra khi rê chuột
    // lên một câu, hoặc từ biểu tượng ✦ trong bảng từ. Bảng được GHIM: đóng bằng ×, Esc, bấm ra ngoài, hoặc gõ chữ.
    private lazy var aiPanel = AIPanel()
    private lazy var chip = AIChip()
    /// Đoạn chữ bảng AI đang làm việc: vị trí trong ô (UTF-16, tuyệt đối), nguyên văn, khung từng dòng (toạ độ
    /// Cocoa), và vị trí (trong `text`) nơi nó được mở, để đổi giữa câu và đoạn.
    private var ai: (range: CFRange, original: String, rects: [NSRect], index: Int)?
    private var aiParagraph = false
    private var aiTask = SentenceTask.fix
    private var aiOpen: Bool { ai != nil }
    /// Câu đang được gợi ý bằng nút ✦ (chuột vừa dừng trên nó): vị trí trong `text` và khung từng dòng.
    private var hint: (index: Int, rects: [NSRect])?
    private var hintLeftAt: Date?
    private var restPoint = NSPoint.zero
    private var restSince = Date()
    private var probed = false
    private static let restDelay = 0.45
    private var settingsSkip: Set<String> = []
    private var sessionSkip: Set<String> = []
    /// Bảng đề nghị vừa mở bằng bàn phím khi chuột đang ở chỗ này: chuột chưa nhúc nhích thì không được đóng bảng.
    private var keyboardAnchor: NSPoint?
    /// Người dùng vừa làm gì: gõ chữ, đi ngang (← → Home End), đi dọc (↑ ↓ Page), hay bấm chuột. Từ ngay tại con trỏ
    /// chỉ bị coi là "đang gõ dở" (chưa soát) khi họ đang GÕ; đi ngang tới một từ bị gạch thì bảng đề nghị tự mở
    /// (người dùng yêu cầu 2026-11-25). Đi dọc thì không mở: ↑ ↓ sẽ bị bảng giữ lại và họ kẹt giữa chừng.
    private enum Input { case typing, horizontal, vertical, mouse }
    private var lastInput = Input.typing
    /// Bảng đang mở là do con trỏ đi vào từ (không phải rê chuột): nó đóng khi con trỏ rời từ đó.
    private var caretOpened = false
    /// Chỗ người dùng vừa đóng bảng (Esc, đưa chuột đi) khi con trỏ vẫn nằm trong đó: không tự mở lại cho tới khi
    /// con trỏ rời đi.
    private var suppressed: ProofIssue?

    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    private static let maxChars = 6000, margin = 300, maxMarks = 40
    private static let idleInterval = 0.6, busyInterval = 0.15

    init() {
        popover.onPick = { [weak self] replacement in self?.apply(replacement) }
        popover.onOpenAI = { [weak self] in
            guard let self, let issue = self.shownIssue else { return }
            self.openAI(index: issue.range.lowerBound, anchor: self.shownRects.first)
        }
        popover.onCancel = { [weak self] in self?.closePopover(suppress: true) }
        aiPanel.onTask = { [weak self] task in self?.ask(task) }
        aiPanel.onRefresh = { [weak self] in self.map { $0.ask($0.aiTask, fresh: true) } }
        aiPanel.onScope = { [weak self] paragraph in self?.setScope(paragraph: paragraph) }
        aiPanel.onUse = { [weak self] text in self?.useAI(text) }
        aiPanel.onClose = { [weak self] in self?.closeAI() }
        chip.onOpen = { [weak self] in self.map { me in me.hint.map { me.openAI(index: $0.index, anchor: $0.rects.first) } } }
        popover.onAdd = { [weak self] in self?.ignoreShown(forever: true) }
        popover.onIgnore = { [weak self] in self?.ignoreShown(forever: false) }
    }

    /// Bảng đề nghị với dữ liệu mẫu, cho chế độ `--snapshot` (dòng đầu ở trạng thái đang rê chuột).
    static func samplePanel() -> NSWindow {
        let panel = SuggestionPanel()
        panel.show(
            ProofIssue(range: 0..<3, text: "dới", kind: .spelling, suggestions: ["với", "giới"]),
            below: NSRect(x: -4000, y: -3000, width: 60, height: 18), ai: true)
        panel.alphaValue = 1
        panel.move(1)
        return panel
    }

    /// Bảng AI với dữ liệu mẫu, cho chế độ `--snapshot`.
    static func sampleSentencePanel() -> NSWindow {
        let panel = AIPanel()
        panel.show(
            tasks: SentenceTask.allCases, task: .fix, paragraph: false, canRefresh: true,
            original: "em co muốn làm việc dới thầy không", state: .ready("em có muốn làm việc với thầy không"),
            anchor: NSRect(x: -4000, y: -3000, width: 200, height: 18))
        panel.alphaValue = 1
        return panel
    }

    // MARK: - Cài đặt

    func configure(on: Bool, config: Config, lexicon: Lexicon, context: ContextModel?, english: Bool, sentence: Bool, skip: Set<String>) {
        // Bảng AI chỉ có khi máy có Apple Intelligence; không có thì không hiện nút ✦ và không theo dõi chuột.
        sentenceOn = sentence && SentenceFix.available
        reader.config = config
        reader.lexicon = lexicon
        reader.context = context
        if reader.checkEnglish != english || settingsSkip != skip {
            reader.checkEnglish = english
            settingsSkip = skip
            reader.skip = skip.union(sessionSkip)
            stale = true  // soát lại ở nhịp sau
        }
        guard on != enabled else { return }
        enabled = on
        Log.write("PROOF \(on ? "bật" : "tắt")")
        if on { schedule(Proofing.idleInterval) } else { stop() }
    }

    private func schedule(_ interval: TimeInterval) {
        if let timer, abs(timer.timeInterval - interval) < 0.01 { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = interval / 5
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        clear("tắt")
    }

    private func clear(_ why: String) {
        if !marks.isEmpty || !issues.isEmpty { Log.write("PROOF xoá \(marks.count) nét: \(why)") }
        element = nil; text = ""; issues = []; marks = []; stale = false
        settling = false; lastClip = nil
        hovered = nil
        closeAI()
        hideHint()
        overlay.hide()
        closePopover()
    }

    // MARK: - Từ KeyTap (đang ở trong callback của event tap: chỉ làm việc rẻ, không gọi AX)

    /// Một phím vừa được gõ (mã phím, phím bổ trợ). Phím chữ hoãn việc soát tới khi ngừng gõ một nhịp; phím điều hướng
    /// thì không. Bảng đề nghị đang mở: ↑ ↓ đổi dòng đang chọn, ↩ hoặc ⇥ dùng dòng đó, Esc đóng (trả về true, phím bị
    /// nuốt); ← → đi tiếp trong văn bản, bảng theo con trỏ; phím khác đóng bảng và đi tiếp tới ứng dụng.
    func key(code: Int, mods: UInt) -> Bool {
        let horizontal = [123, 124, 115, 119].contains(code)  // ← → Home End
        let vertical = [125, 126, 116, 121].contains(code)  // ↓ ↑ Page Up, Page Down
        if hint != nil { DispatchQueue.main.async { self.hideHint() } }
        if aiOpen {
            // Bảng AI đang mở (ghim): ← → đổi thẻ, ↑ ↓ chọn, ↩ dùng, Esc đóng. Phím khác đóng bảng rồi đi tiếp.
            if mods == 0 {
                switch code {
                case 123, 124:
                    DispatchQueue.main.async { self.aiPanel.switchTask(code == 124 ? 1 : -1) }
                    return true
                case 125, 126:
                    DispatchQueue.main.async { self.aiPanel.move(code == 125 ? 1 : -1) }
                    return true
                case 36, 76, 48 where aiPanel.hasSelection:
                    DispatchQueue.main.async { self.aiPanel.activate() }
                    return true
                case 53:
                    DispatchQueue.main.async { self.closeAI() }
                    return true
                default: break
                }
            }
            DispatchQueue.main.async { self.closeAI() }
        }
        let open = shownIssue != nil
        if open, mods == 0 {
            switch code {
            case 125, 126:
                DispatchQueue.main.async { self.popover.move(code == 125 ? 1 : -1) }
                return true
            case 36, 76, 48 where popover.hasSelection:  // ↩, Enter, ⇥
                DispatchQueue.main.async { self.popover.activate() }
                return true
            case 53:  // Esc
                DispatchQueue.main.async { self.closePopover(suppress: true) }
                return true
            default: break
            }
        }
        if horizontal || vertical {
            lastInput = horizontal ? .horizontal : .vertical
            stale = true  // từ ở chỗ con trỏ cũ (trước đây coi là đang gõ dở) giờ phải được soát
            // Không đợi nhịp soát kế tiếp (tới 0,15 giây): xem con trỏ ngay sau khi ứng dụng kịp dời nó.
            if horizontal { DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { self.tick() } }
            if open, vertical { DispatchQueue.main.async { self.closePopover() } }
            return false
        }
        lastInput = .typing
        lastKey = Date()
        if open { DispatchQueue.main.async { self.closePopover() } }
        return false
    }

    /// Chuột trái vừa bấm ở `point` (toạ độ màn hình của CGEvent, gốc trên-trái): bấm ra ngoài bảng đề nghị thì
    /// đóng bảng. Cú bấm vẫn đi tiếp tới ứng dụng.
    func mouseDown(at point: CGPoint) {
        guard enabled else { return }
        if lastInput != .mouse {
            lastInput = .mouse
            stale = true
        }
        guard shownIssue != nil || aiOpen || hint != nil, let primary = NSScreen.screens.first else { return }
        let p = NSPoint(x: point.x, y: primary.frame.height - point.y)
        // Bấm vào chính bảng (hoặc nút ✦) thì để bảng xử lý; bấm ra ngoài thì đóng.
        if aiOpen, aiPanel.frame.contains(p) { return }
        if shownIssue != nil, popover.frame.contains(p) { return }
        if hint != nil, chip.frame.contains(p) { return }
        DispatchQueue.main.async {
            self.closePopover()
            self.closeAI()
            self.hideHint()
        }
    }

    // MARK: - Cửa sổ dời chỗ

    /// Đăng ký nghe cửa sổ `window` (đổi cửa sổ thì bỏ đăng ký cũ). Gọi ở luồng chính.
    private func watch(_ window: AXUIElement?, pid: pid_t) {
        if let window, let observed, CFEqual(window, observed) { return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        observed = nil
        guard let window else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<Proofing>.fromOpaque(refcon).takeUnretainedValue().windowMoved()
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            Log.write("PROOF không nghe được cửa sổ dời chỗ: dùng cách so khung mỗi nhịp")
            return
        }
        let me = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXMovedNotification, kAXResizedNotification] { AXObserverAddNotification(created, window, name as CFString, me) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observed = window
    }

    /// Cửa sổ chứa ô nhập vừa dời hoặc đổi cỡ: ẩn mọi thứ ngay, đợi nó đứng yên rồi `took()` vẽ lại.
    private func windowMoved() {
        movedAt = Date()
        guard !settling else { return }
        settling = true
        Log.write("PROOF cửa sổ dời chỗ: ẩn \(marks.count) nét")
        marks = []
        hovered = nil
        closeAI()
        hideHint()
        overlay.hide()
        closePopover()
    }

    // MARK: - Chữ vừa được thay

    /// Quét một dải sáng lên `length` ký tự (UTF-16) đứng trước con trỏ, bỏ qua `trailing` ký tự sát con trỏ (dấu
    /// cách vừa gõ). Dùng khi chữ vừa được thay: Đổi từ vừa gõ, chọn một đề nghị, gõ tắt bung ra. Ứng dụng không cho
    /// biết khung chữ thì không làm gì. Gọi ở luồng chính, sau khi chữ mới đã tới ứng dụng.
    func pulse(length: Int, trailing: Int = 0) {
        guard length > 0 else { return }
        queue.async { [weak self] in
            guard let snap = Proofing.read(), let caret = snap.caret else { return }
            let end = caret - trailing - snap.base, start = end - length
            let units = Array(snap.text.utf16)
            guard start >= 0, end <= units.count else { return }
            let piece = ProofIssue(
                range: start..<end, text: String(utf16CodeUnits: Array(units[start..<end]), count: length), kind: .phrase, suggestions: [])
            let rects = Proofing.frames(of: [piece], in: snap).first ?? []
            DispatchQueue.main.async {
                let cocoa = rects.compactMap(HUD.cocoa)
                Log.write("PROOF dải sáng \(length) ký tự: \(cocoa.isEmpty ? "ứng dụng không cho biết khung" : "\(cocoa.count) đoạn")")
                self?.overlay.sweep(cocoa, clip: snap.clip.flatMap(HUD.cocoa))
            }
        }
    }

    // MARK: - Rê chuột

    private func watchMouse() {
        guard hoverTimer == nil else { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.pointerMoved() }
        hoverTimer?.tolerance = 0.02
    }

    private func pointerMoved() {
        guard enabled, element != nil || shownIssue != nil || aiOpen else {
            hoverTimer?.invalidate()
            hoverTimer = nil
            return
        }
        if aiOpen { return }  // bảng AI đang mở: không tự đổi, không tự đóng
        if NSEvent.pressedMouseButtons != 0 { return }  // đang kéo chọn chữ: không chen vào
        let p = NSEvent.mouseLocation
        if let a = keyboardAnchor {
            if abs(p.x - a.x) < 4, abs(p.y - a.y) < 4 { return }
            keyboardAnchor = nil
        }
        let now = Date()
        if let over = marks.first(where: { $0.rects.contains { $0.insetBy(dx: -2, dy: -3).contains(p) } }) {
            leftAt = nil
            // Nút ✦ của câu đang hiện thì GIỮ khi chuột đi vào một từ bị gạch (người dùng yêu cầu 2026-11-26): bảng đề
            // nghị cho từ và nút ✦ cho câu cùng hiện.
            hintLeftAt = nil
            if shownIssue == over.issue { return }
            if hovered != over.issue {
                hovered = over.issue
                hoverSince = now
                overlay.highlight(over.rects, over.color)
            } else if now.timeIntervalSince(hoverSince) >= Proofing.hoverDelay {
                show(over)
            }
            return
        }
        hovered = nil
        if shownIssue != nil {
            // Chuột đang ở trên bảng, hoặc trên đường từ chữ xuống bảng: giữ bảng.
            let corridor = shownRects.reduce(popover.frame) { $0.union($1) }.insetBy(dx: -6, dy: -6)
            if corridor.contains(p) {
                leftAt = nil
            } else if let since = leftAt {
                if now.timeIntervalSince(since) >= Proofing.leaveDelay { closePopover(suppress: true) }
            } else {
                leftAt = now
            }
            return
        }
        guard sentenceOn else { return overlay.highlight([]) }
        // Nút ✦ đang hiện cho một câu: giữ khi chuột còn trên câu đó, trên đường tới nút, hoặc trên nút. Bảng AI chỉ mở
        // khi BẤM nút (`chip.onOpen`), không mở khi rê chuột vào (người dùng yêu cầu 2026-11-26).
        if let hint {
            let zone = hint.rects.reduce(chip.frame) { $0.union($1) }.insetBy(dx: -6, dy: -6)
            if zone.contains(p) {
                hintLeftAt = nil
            } else if let since = hintLeftAt {
                if now.timeIntervalSince(since) >= Proofing.leaveDelay { hideHint() }
            } else {
                hintLeftAt = now
            }
            return
        }
        // Chuột dừng yên trên vùng chữ đủ lâu: tìm câu nằm dưới nó (một lần cho mỗi chỗ dừng).
        if abs(p.x - restPoint.x) > 3 || abs(p.y - restPoint.y) > 3 {
            restPoint = p
            restSince = now
            probed = false
        } else if !probed, now.timeIntervalSince(restSince) >= Proofing.restDelay,
            lastClip.flatMap(HUD.cocoa)?.contains(p) ?? false
        {
            probed = true
            probe(at: p)
        }
    }

    /// Hỏi ứng dụng ký tự nằm dưới điểm `p` (toạ độ Cocoa), rồi hiện nút ✦ và tô nhẹ câu chứa nó.
    private func probe(at p: NSPoint) {
        guard let element, let primary = NSScreen.screens.first else { return }
        var point = CGPoint(x: p.x, y: primary.frame.height - p.y)
        let ticket = asking
        queue.async { [weak self] in
            AXUIElementSetMessagingTimeout(element, 0.1)
            var out: CFTypeRef?
            guard let value = AXValueCreate(.cgPoint, &point),
                AXUIElementCopyParameterizedAttributeValue(element, kAXRangeForPositionParameterizedAttribute as CFString, value, &out) == .success,
                let at = Proofing.range(out)
            else { return }
            DispatchQueue.main.async {
                guard let self, ticket == self.asking, !self.aiOpen, self.shownIssue == nil, self.hint == nil else { return }
                let index = at.location - self.base
                self.locate(index: index, paragraph: false) { found in
                    guard let found, !found.rects.isEmpty, !self.aiOpen, self.shownIssue == nil, let last = found.rects.last else { return }
                    self.hint = (index, found.rects)
                    self.hintLeftAt = nil
                    self.overlay.highlight(found.rects, .controlAccentColor, alpha: 0.1, clip: self.lastClip.flatMap(HUD.cocoa))
                    self.chip.show(at: NSPoint(x: last.maxX + 4, y: last.midY))
                    Log.write("PROOF nút ✦ cho một câu \(found.original.utf16.count) ký tự")
                }
            }
        }
    }

    private func hideHint() {
        guard hint != nil else { return }
        hint = nil
        hintLeftAt = nil
        chip.hide()
        if !aiOpen, shownIssue == nil { overlay.highlight([]) }
    }

    // MARK: - Vòng soát

    private func tick() {
        guard enabled, !busy else { return }
        guard isActive() else { return clear("VNKey đang tắt hoặc tạm ngưng") }
        // Bảng đề nghị mở do rê chuột: giữ nguyên nét gạch và vị trí. Mở do con trỏ thì vẫn phải theo dõi con trỏ.
        if aiOpen || (shownIssue != nil && !caretOpened) { return }
        busy = true
        let known = element, knownText = text, knownBase = base, knownIssues = issues
        queue.async { [weak self] in
            let start = CFAbsoluteTimeGetCurrent()
            let snap = Proofing.read()
            // Chữ không đổi: hỏi luôn khung của các chỗ đã biết, đỡ một lượt qua lại giữa hai luồng.
            var frames: [[CGRect]]?
            if let snap, let known, CFEqual(snap.element, known), snap.text == knownText, snap.base == knownBase {
                frames = Proofing.frames(of: knownIssues, in: snap)
            }
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            DispatchQueue.main.async { self?.took(snap, frames, readMs: ms) }
        }
    }

    private func took(_ snap: Snapshot?, _ frames: [[CGRect]]?, readMs: Double) {
        busy = false
        guard enabled else { return }
        guard let snap else { return clear("không ở trong ô nhập soát được") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == snap.pid else { return clear("ô không thuộc ứng dụng ở trước") }
        watch(snap.window, pid: snap.pid)
        if sentenceOn { watchMouse() }  // để nhận ra chuột dừng trên một câu, kể cả khi không có nét gạch nào
        // Dự phòng cho ứng dụng không phát thông báo dời cửa sổ: khung nhìn thấy của ô đổi so với nhịp trước.
        let shifted = lastClip != nil && snap.clip != lastClip
        lastClip = snap.clip
        if shifted { windowMoved() }
        if settling {
            if shifted || Date().timeIntervalSince(movedAt) < 0.25 { return }
            settling = false
            Log.write("PROOF cửa sổ đã đứng yên: vẽ lại nét gạch")
        }
        let typing = Date().timeIntervalSince(lastKey) < 0.4
        if let frames, !stale || typing {
            caret = snap.caret
            return draw(frames, snap)
        }
        // Chữ đã đổi. Đang gõ dở thì đợi ngừng một nhịp rồi mới soát lại; trong lúc đó giữ những nét gạch mà chữ bên
        // dưới còn nguyên chỗ cũ (gõ ở cuối văn bản không làm xê dịch chữ phía trước), để chúng không nhấp nháy.
        if typing {
            let units = Array(snap.text.utf16)
            let kept = issues.filter {
                snap.base == base && $0.range.upperBound <= units.count
                    && String(utf16CodeUnits: Array(units[$0.range]), count: $0.range.count) == $0.text
            }
            element = snap.element; text = snap.text; base = snap.base; caret = snap.caret
            issues = kept
            stale = true
            schedule(Proofing.busyInterval)
            guard !kept.isEmpty else {
                marks = []
                return overlay.hide()
            }
            busy = true
            queue.async { [weak self] in
                let frames = Proofing.frames(of: kept, in: snap)
                DispatchQueue.main.async {
                    self?.busy = false
                    self?.draw(frames, snap)
                }
            }
            return
        }
        stale = false
        let start = CFAbsoluteTimeGetCurrent()
        // Chỉ khi đang gõ thì từ ngay tại con trỏ mới là từ gõ dở; đi tới bằng phím điều hướng hay chuột thì soát cả nó.
        let found = reader.check(snap.text, caret: lastInput == .typing ? snap.caret.map { $0 - snap.base } : nil)
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        element = snap.element; text = snap.text; base = snap.base; caret = snap.caret
        issues = Array(found.prefix(Proofing.maxMarks))
        let kinds = Dictionary(grouping: issues, by: \.kind).map { "\($0.key.rawValue)=\($0.value.count)" }.sorted().joined(separator: " ")
        Log.write(String(format: "PROOF soát %d ký tự: %d chỗ %@ đọc %.1fms soát %.1fms", snap.text.utf16.count, found.count, kinds, readMs, ms))
        guard !issues.isEmpty else {
            marks = []
            overlay.hide()
            suppressed = nil
            closePopover()
            schedule(Proofing.idleInterval)
            return
        }
        schedule(Proofing.busyInterval)
        busy = true
        let asked = issues
        queue.async { [weak self] in
            let frames = Proofing.frames(of: asked, in: snap)
            DispatchQueue.main.async {
                self?.busy = false
                self?.draw(frames, snap)
            }
        }
    }

    private func draw(_ frames: [[CGRect]], _ snap: Snapshot) {
        guard enabled, frames.count == issues.count else { return }
        var next: [Mark] = []
        for (issue, parts) in zip(issues, frames) {
            let rects = parts.compactMap(HUD.cocoa)
            if !rects.isEmpty { next.append(Mark(issue: issue, rects: rects)) }
        }
        let moved = next.map(\.rects) != marks.map(\.rects)
        marks = next
        guard !marks.isEmpty else { return overlay.hide() }
        if moved {
            Log.write("PROOF vẽ \(marks.count)/\(issues.count) nét")
            // Khoá của một nét: chữ bị gạch + nó là lần thứ mấy chữ đó xuất hiện + đoạn thứ mấy. Không dùng vị trí ký
            // tự, để gõ thêm ở phía trước không làm mọi nét "mới lại" và trượt ra lần nữa.
            var seen: [String: Int] = [:]
            var lines: [(key: String, rect: NSRect, color: NSColor)] = []
            for m in marks {
                let n = seen[m.issue.text, default: 0]
                seen[m.issue.text] = n + 1
                for (i, r) in m.rects.enumerated() { lines.append(("\(m.issue.text)#\(n)#\(i)", r, m.color)) }
            }
            overlay.show(lines, clip: snap.clip.flatMap(HUD.cocoa))
            hovered = nil  // chữ vừa xê dịch: nền sáng cũ không còn đúng chỗ
            overlay.highlight([])
            if let shown = shownIssue, let m = marks.first(where: { $0.issue == shown }) { overlay.highlight(m.rects, m.color) }
        }
        watchMouse()
        followCaret()
    }

    /// Con trỏ soạn thảo vừa được đưa NGANG (← →, Home, End) vào một từ bị gạch: tự mở bảng đề nghị cho từ đó, chọn
    /// sẵn đề nghị đầu tiên. Con trỏ rời từ thì bảng đóng.
    private func followCaret() {
        // Soát lại xong mà chỗ đang mở không còn (chữ đã đổi): đóng bảng. Còn thì giữ nguyên, không đóng rồi mở lại.
        if let shown = shownIssue, !marks.contains(where: { $0.issue == shown }) { closePopover() }
        guard let caret else { return }
        let hit = marks.first { base + $0.issue.range.lowerBound <= caret && caret <= base + $0.issue.range.upperBound }
        if hit?.issue != suppressed { suppressed = nil }
        guard lastInput == .horizontal else { return }
        if let hit {
            guard shownIssue != hit.issue, suppressed != hit.issue else { return }
            keyboardAnchor = NSEvent.mouseLocation
            show(hit)
            caretOpened = true
            popover.move(1)
        } else if caretOpened {
            closePopover()
        }
    }

    // MARK: - Đọc qua Trợ năng (hàng đợi nền)

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var out: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &out) == .success ? out : nil
    }

    private static func ask(_ element: AXUIElement, _ attribute: String, _ range: CFRange) -> CFTypeRef? {
        var range = range
        var out: CFTypeRef?
        guard let v = AXValueCreate(.cfRange, &range),
            AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, v, &out) == .success
        else { return nil }
        return out
    }

    private static func range(_ value: CFTypeRef?) -> CFRange? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var r = CFRange(location: 0, length: 0)
        return AXValueGetValue(value as! AXValue, .cfRange, &r) ? r : nil
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let pos = copy(element, kAXPositionAttribute), let size = copy(element, kAXSizeAttribute),
            CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    /// Ô đang nhận phím và đoạn chữ quanh vùng nhìn thấy của nó. nil nếu không phải ô nhập soát được.
    private static func read() -> Snapshot? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        guard let focused = copy(system, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.1)
        guard let role = copy(element, kAXRoleAttribute) as? String, textRoles.contains(role),
            copy(element, kAXSubroleAttribute) as? String != "AXSecureTextField"  // ô mật khẩu: không bao giờ đọc
        else { return nil }
        let total = (copy(element, kAXNumberOfCharactersAttribute) as? Int) ?? 0
        guard total > 0 else { return nil }
        var window = CFRange(location: 0, length: min(total, maxChars))
        if total > maxChars, let visible = range(copy(element, kAXVisibleCharacterRangeAttribute)) {
            let from = max(0, visible.location - margin)
            window = CFRange(location: from, length: min(total - from, min(visible.length + 2 * margin, maxChars)))
        }
        guard let text = ask(element, kAXStringForRangeParameterizedAttribute, window) as? String else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        // Ô nằm trong vùng cuộn thì khung của ô là cả văn bản: vùng nhìn thấy là khung của vùng cuộn.
        var clip = frame(element)
        if let parent = copy(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID(),
            copy(parent as! AXUIElement, kAXRoleAttribute) as? String == "AXScrollArea", let r = frame(parent as! AXUIElement)
        {
            clip = r
        }
        let selection = range(copy(element, kAXSelectedTextRangeAttribute))
        var host: AXUIElement?
        if let w = copy(element, kAXWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID() { host = (w as! AXUIElement) }
        return Snapshot(element: element, window: host, pid: pid, text: text, base: window.location, caret: selection?.location, clip: clip)
    }

    /// Khung (toạ độ AX) của từng chỗ. Cụm nhiều từ hỏi riêng từng từ rồi gộp các từ cùng dòng, để cụm vắt qua hai
    /// dòng vẫn gạch đúng. Chỗ nằm ngoài vùng nhìn thấy trả về mảng rỗng.
    private static func frames(of issues: [ProofIssue], in snap: Snapshot) -> [[CGRect]] {
        issues.map { issue in
            var pieces: [CFRange] = []
            var offset = issue.range.lowerBound, start: Int?
            for unit in issue.text.utf16 {
                let space = unit == 0x20
                if !space, start == nil { start = offset }
                if space, let s = start { pieces.append(CFRange(location: snap.base + s, length: offset - s)); start = nil }
                offset += 1
            }
            if let s = start { pieces.append(CFRange(location: snap.base + s, length: offset - s)) }
            let rects = pieces.compactMap { HUD.rect(ask(snap.element, kAXBoundsForRangeParameterizedAttribute, $0)) }
                .filter { $0.width > 1 && $0.height > 1 }
            guard rects.count == pieces.count else { return [] }
            if let clip = snap.clip, !rects.allSatisfy({ clip.insetBy(dx: -2, dy: -2).contains($0) }) { return [] }
            // Các từ của một cụm nằm cùng dòng thì gộp thành một khung, để nét gạch và nền sáng phủ cả khoảng trống
            // giữa chúng (người dùng yêu cầu 2026-11-25). Từ rớt xuống dòng sau giữ khung riêng.
            var merged: [CGRect] = []
            for r in rects {
                if let last = merged.last, abs(last.midY - r.midY) < min(last.height, r.height) / 2, r.minX >= last.minX {
                    merged[merged.count - 1] = last.union(r)
                } else {
                    merged.append(r)
                }
            }
            return merged
        }
    }

    // MARK: - Bảng đề nghị

    private func show(_ mark: Mark) {
        guard enabled, let anchor = mark.rects.first else { return }
        shownIssue = mark.issue
        shownRects = mark.rects
        leftAt = nil
        overlay.highlight(mark.rects, mark.color)
        Log.write("PROOF rê chuột loại=\(mark.issue.kind.rawValue) đề nghị=\(mark.issue.suggestions.count)")
        asking += 1
        let whole = sentenceOn && SentenceFilter.sentence(in: text, around: mark.issue.range) != nil
        if whole { SentenceFix.warm() }
        popover.show(mark.issue, below: anchor, ai: whole)
    }

    /// `suppress`: người dùng chủ động đóng (Esc, đưa chuột đi): không tự mở lại khi con trỏ vẫn nằm trong từ đó.
    private func closePopover(suppress: Bool = false) {
        guard let shown = shownIssue else { return }
        if suppress { suppressed = shown }
        asking += 1
        shownIssue = nil
        shownRects = []
        keyboardAnchor = nil
        caretOpened = false
        hovered = nil
        overlay.highlight([])
        // Nút ✦ của câu còn hiện: tô lại nền câu đó.
        if let hint, !aiOpen { overlay.highlight(hint.rects, .controlAccentColor, alpha: 0.1, clip: lastClip.flatMap(HUD.cocoa)) }
        popover.dismiss()
    }

    private func rescanSoon() {
        stale = true
        lastKey = .distantPast
        schedule(Proofing.busyInterval)
    }

    /// `forever`: thêm vào từ điển của người dùng (lưu lại); không thì chỉ thôi gạch cho tới khi VNKey chạy lại.
    private func ignoreShown(forever: Bool) {
        guard let issue = shownIssue else { return }
        closePopover()
        let words = issue.text.lowercased().split(separator: " ").map(String.init)
        Log.write("PROOF \(forever ? "thêm vào từ điển" : "bỏ qua lần này") \(words.count) từ loại=\(issue.kind.rawValue)")
        sessionSkip.formUnion(words)
        reader.skip = settingsSkip.union(sessionSkip)
        if forever { ignore(words) }
        rescanSoon()
    }

    // MARK: - Sửa cả câu

    /// Câu (hoặc đoạn văn) chứa vị trí `index` của chữ đang soát, và khung từng dòng của nó. `done` chạy ở luồng chính;
    /// nil nếu không có câu nào ở đó (chỉ một từ, hoặc dài quá giới hạn).
    private func locate(index: Int, paragraph: Bool, done: @escaping ((range: Range<Int>, original: String, rects: [NSRect])?) -> Void) {
        let count = text.utf16.count
        guard let element, index >= 0, index <= count else { return done(nil) }
        let at = min(index, count)..<min(index, count)
        guard let range = paragraph ? SentenceFilter.paragraph(in: text, around: at) : SentenceFilter.sentence(in: text, around: at) else { return done(nil) }
        let units = Array(text.utf16)
        let original = String(utf16CodeUnits: Array(units[range]), count: range.count)
        let knownBase = base, clip = lastClip
        queue.async {
            let snap = Snapshot(element: element, window: nil, pid: 0, text: "", base: knownBase, caret: nil, clip: clip)
            // Hỏi khung theo từng DÒNG của đoạn chữ (cắt ở dấu xuống dòng) thay vì từng từ: đoạn văn dài có cả trăm từ.
            var pieces: [ProofIssue] = []
            var start = range.lowerBound
            for (i, u) in units[range].enumerated() where u == 0x0A || u == 0x0D {
                let end = range.lowerBound + i
                if end > start { pieces.append(ProofIssue(range: start..<end, text: String(utf16CodeUnits: Array(units[start..<end]), count: end - start), kind: .phrase, suggestions: [])) }
                start = end + 1
            }
            if range.upperBound > start {
                pieces.append(ProofIssue(range: start..<range.upperBound, text: String(utf16CodeUnits: Array(units[start..<range.upperBound]), count: range.upperBound - start), kind: .phrase, suggestions: []))
            }
            let rects = Proofing.frames(of: pieces, in: snap).flatMap { $0 }.compactMap(HUD.cocoa)
            DispatchQueue.main.async { done((range, original, rects)) }
        }
    }

    /// Mở bảng AI cho câu chứa vị trí `index` (trong `text`), ghim lại, tô nền cả câu, và hỏi luôn việc sửa chính tả.
    private func openAI(index: Int, anchor: NSRect?) {
        guard sentenceOn, enabled else { return }
        asking += 1
        let ticket = asking
        locate(index: index, paragraph: aiParagraph) { [weak self] found in
            guard let self, ticket == self.asking else { return }
            guard let found, let place = found.rects.first ?? anchor else {
                Log.write("PROOF bảng AI: không tìm được câu ở chỗ đó")
                return NSSound.beep()
            }
            self.closePopover()
            self.hideHint()
            self.ai = (CFRange(location: self.base + found.range.lowerBound, length: found.range.count), found.original, found.rects, index)
            self.aiTask = .fix
            self.overlay.highlight(found.rects, .controlAccentColor, alpha: 0.18, clip: self.lastClip.flatMap(HUD.cocoa))
            let below = found.rects.min(by: { $0.minY < $1.minY }) ?? place
            Log.write("PROOF mở bảng AI: \(self.aiParagraph ? "đoạn" : "câu") \(found.original.utf16.count) ký tự")
            self.aiPanel.show(
                tasks: SentenceTask.allCases, task: .fix, paragraph: self.aiParagraph, canRefresh: true,
                original: found.original, state: .loading, anchor: NSRect(x: place.minX, y: below.minY, width: place.width, height: below.height))
            SentenceFix.warm()
            self.ask(.fix)
        }
    }

    /// Hỏi việc `task` cho đoạn chữ bảng AI đang mở. `fresh`: người dùng bấm thử lại.
    private func ask(_ task: SentenceTask, fresh: Bool = false) {
        guard let ai else { return }
        aiTask = task
        aiPanel.update(task: task, state: .loading)
        asking += 1
        let ticket = asking
        SentenceFix.fix(ai.original, task: task, fresh: fresh) { [weak self] result in
            guard let self, ticket == self.asking, self.aiOpen, self.aiTask == task else { return }
            self.aiPanel.update(task: task, state: result.map { .ready($0) } ?? .nothing)
        }
    }

    private func setScope(paragraph: Bool) {
        guard let ai, paragraph != aiParagraph else { return }
        aiParagraph = paragraph
        let index = ai.index
        self.ai = nil
        openAI(index: index, anchor: ai.rects.first)
    }

    private func useAI(_ text: String) {
        guard let ai else { return }
        let label = (aiParagraph ? "đoạn-" : "câu-") + aiTask.rawValue
        closeAI()
        replace(ai.range, expecting: ai.original, with: text, label: label)
    }

    private func closeAI() {
        guard aiOpen else { return }
        ai = nil
        asking += 1
        aiPanel.dismiss()
        overlay.highlight([])
    }

    /// Thay chữ của chỗ đang mở bằng `replacement`.
    private func apply(_ replacement: String) {
        guard let issue = shownIssue else { return }
        closePopover()
        replace(CFRange(location: base + issue.range.lowerBound, length: issue.range.count), expecting: issue.text, with: replacement, label: issue.kind.rawValue)
    }

    /// Thay đoạn `target` trong ô đang soát bằng `replacement`: bôi chọn đúng đoạn đó rồi ghi `AXSelectedText`. Chỉ
    /// thay khi đoạn đó vẫn đúng là `expected` (chữ có thể đã đổi từ lần soát).
    private func replace(_ target: CFRange, expecting expected: String, with replacement: String, label: String) {
        guard let element else { return }
        queue.async { [weak self] in
            AXUIElementSetMessagingTimeout(element, 0.15)
            var outcome = "đã thay"
            var target = target
            if Proofing.ask(element, kAXStringForRangeParameterizedAttribute, target) as? String != expected {
                outcome = "chữ đã đổi, không thay"
            } else if let select = AXValueCreate(.cfRange, &target),
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, select) == .success
            {
                let err = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFString)
                if err != .success {
                    outcome = "ứng dụng không cho ghi (\(err.rawValue))"
                } else {
                    var end = CFRange(location: target.location + replacement.utf16.count, length: 0)
                    if let v = AXValueCreate(.cfRange, &end) {
                        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, v)
                    }
                }
            } else {
                outcome = "không bôi chọn được"
            }
            DispatchQueue.main.async {
                Log.write("PROOF thay loại=\(label): \(outcome)")
                if outcome == "đã thay" {
                    self?.didReplace()
                    self?.pulse(length: replacement.utf16.count)
                } else {
                    NSSound.beep()
                }
                self?.rescanSoon()
            }
        }
    }
}

// MARK: - Lớp phủ vẽ nét gạch chân

/// Một nét gạch: khoá để nhận ra nó qua các lần vẽ lại, khung (toạ độ của view) và màu.
private struct UnderlineStroke {
    var key: String
    var rect: NSRect
    var color: NSColor
}

private final class UnderlineView: NSView {
    /// Mỗi nét gạch là một lớp riêng, để nét MỚI trượt ra từ trái sang phải còn nét đã có chỉ dời chỗ.
    private var strokes: [String: CAShapeLayer] = [:]
    /// Nền sáng của chỗ đang rê chuột. Mọi chuyển động ngầm của lớp này đều tắt (kể cả vị trí và hình dạng): nó chỉ
    /// được mờ dần tại chỗ. Trước đây nền trượt từ chỗ cũ sang từ mới, người dùng thấy rối (2026-11-25).
    private let glow = CAShapeLayer()
    private static let still: [String: CAAction] = [
        "opacity": NSNull(), "path": NSNull(), "position": NSNull(), "bounds": NSNull(), "frame": NSNull(),
        "fillColor": NSNull(), "strokeColor": NSNull(), "strokeEnd": NSNull(), "lineWidth": NSNull(), "hidden": NSNull(),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glow.opacity = 0
        glow.actions = UnderlineView.still
        layer?.addSublayer(glow)
    }

    required init?(coder: NSCoder) { nil }

    /// Đặt lại toàn bộ nét gạch. Nét có khoá mới thì trượt ra từ trái sang phải, lần lượt theo thứ tự đọc (trên
    /// xuống, trái sang); nét đã có thì chỉ dời chỗ, không chạy lại (cuộn văn bản không nhấp nháy).
    func set(_ lines: [UnderlineStroke]) {
        let wanted = Set(lines.map(\.key))
        for (key, layer) in strokes where !wanted.contains(key) {
            layer.removeFromSuperlayer()
            strokes[key] = nil
        }
        // Thứ tự đọc: dòng trên trước (toạ độ Cocoa: y lớn ở trên), trong một dòng thì trái trước.
        let fresh = lines.filter { strokes[$0.key] == nil }.sorted { a, b in
            abs(a.rect.midY - b.rect.midY) > 6 ? a.rect.midY > b.rect.midY : a.rect.minX < b.rect.minX
        }
        let order = Dictionary(fresh.enumerated().map { ($0.element.key, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let now = CACurrentMediaTime()
        for line in lines {
            let isNew = strokes[line.key] == nil
            let layer = strokes[line.key] ?? {
                let l = CAShapeLayer()
                l.actions = UnderlineView.still
                l.fillColor = nil
                l.lineCap = .round
                self.layer?.insertSublayer(l, below: glow)
                strokes[line.key] = l
                return l
            }()
            let thick = line.rect.height
            let path = CGMutablePath()
            path.move(to: CGPoint(x: line.rect.minX + thick / 2, y: line.rect.midY))
            path.addLine(to: CGPoint(x: max(line.rect.minX + thick / 2, line.rect.maxX - thick / 2), y: line.rect.midY))
            layer.frame = bounds
            layer.path = path
            layer.lineWidth = thick
            layer.strokeColor = line.color.cgColor
            guard isNew else { continue }
            // Trễ dần theo thứ tự, nhưng cả loạt không kéo quá 0,4 giây.
            let delay = min(Double(order[line.key] ?? 0) * Motion.stagger, 0.4 - Motion.draw)
            let a = CABasicAnimation(keyPath: Motion.reduced ? "opacity" : "strokeEnd")
            a.fromValue = 0
            a.toValue = 1
            a.duration = Motion.draw
            a.beginTime = now + delay
            a.fillMode = .backwards
            a.timingFunction = Motion.ease
            layer.add(a, forKey: "appear")
        }
    }

    private func fade(to target: Float, _ duration: CFTimeInterval) {
        let from = glow.presentation()?.opacity ?? glow.opacity
        glow.removeAnimation(forKey: "fade")
        glow.opacity = target
        guard from != target else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = target
        a.duration = duration
        glow.add(a, forKey: "fade")
    }

    /// Phủ nền mờ cùng màu với nét gạch lên các khung này (hiện dần tại chỗ); mảng rỗng thì tắt dần.
    func highlight(_ rects: [NSRect], _ color: NSColor = .systemRed, alpha: CGFloat = 0.2) {
        guard !rects.isEmpty else { return fade(to: 0, 0.12) }
        let path = CGMutablePath()
        for r in rects { path.addRoundedRect(in: r.insetBy(dx: -2, dy: -1), cornerWidth: 3, cornerHeight: 3) }
        glow.removeAnimation(forKey: "fade")
        glow.opacity = 0  // sang từ khác: bắt đầu lại từ trong suốt, không kéo nền cũ theo
        glow.frame = bounds
        glow.path = path
        glow.fillColor = color.withAlphaComponent(alpha).cgColor
        fade(to: 1, Motion.quick)
    }

    /// Chữ vừa được thay: một dải màu nhấn mờ quét từ trái sang phải trên các khung này rồi tan.
    func sweep(_ rects: [NSRect]) {
        let now = CACurrentMediaTime()
        for r in rects {
            let band = CALayer()
            band.actions = UnderlineView.still
            band.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
            band.cornerRadius = 3
            band.anchorPoint = CGPoint(x: 0, y: 0.5)
            let box = r.insetBy(dx: -2, dy: -1)
            band.bounds = CGRect(origin: .zero, size: box.size)
            band.position = CGPoint(x: box.minX, y: box.midY)
            band.opacity = 0
            layer?.addSublayer(band)
            if !Motion.reduced {
                let grow = CABasicAnimation(keyPath: "bounds.size.width")
                grow.fromValue = 0
                grow.toValue = box.width
                grow.duration = Motion.medium
                grow.timingFunction = Motion.ease
                band.add(grow, forKey: "grow")
            }
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.15, 0.5, 1]
            fade.duration = 0.5
            fade.beginTime = now
            band.add(fade, forKey: "fade")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { band.removeFromSuperlayer() }
        }
    }
}

/// Một cửa sổ trong suốt, không nhận chuột, phủ vùng nhìn thấy của ô đang nhập.
private final class UnderlineOverlay {
    private let panel: NSPanel
    private let view = UnderlineView(frame: .zero)
    private var hasLines = false
    private var hideToken = 0

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = view
    }

    /// `lines`: khoá, khung của từ (toạ độ Cocoa) và màu của từng nét. Nét gạch nằm sát đáy mỗi khung.
    func show(_ lines: [(key: String, rect: NSRect, color: NSColor)], clip: NSRect?) {
        let rects = lines.map(\.rect)
        let bounds = rects.reduce(rects[0]) { $0.union($1) }.insetBy(dx: -2, dy: -3)
        let frame = clip.map { $0.insetBy(dx: -2, dy: -3) } ?? bounds
        hideToken += 1
        panel.setFrame(frame, display: false)
        // Nét gạch dày theo cỡ chữ: khoảng 1/10 chiều cao dòng (chữ 13pt: 2px; tiêu đề 30pt: 3–4px), từ 1 tới 6px.
        view.set(
            lines.map { line in
                let thick = min(6, max(1, (line.rect.height * 0.1).rounded()))
                return UnderlineStroke(
                    key: line.key,
                    rect: NSRect(x: line.rect.minX - frame.minX, y: line.rect.minY - frame.minY - (thick / 2).rounded(), width: line.rect.width, height: thick),
                    color: line.color)
            })
        hasLines = true
        panel.orderFrontRegardless()
    }

    /// Làm sáng nền các khung này (toạ độ Cocoa); mảng rỗng thì tắt. Chưa có nét gạch nào (cửa sổ phủ đang ẩn) thì
    /// mượn cửa sổ phủ, đặt theo `clip`, để tô nền một câu không có lỗi.
    func highlight(_ rects: [NSRect], _ color: NSColor = .systemRed, alpha: CGFloat = 0.2, clip: NSRect? = nil) {
        if rects.isEmpty {
            view.highlight([])
            if !hasLines, panel.isVisible {
                hideToken += 1
                let token = hideToken
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self, token == self.hideToken, !self.hasLines else { return }
                    self.panel.orderOut(nil)
                }
            }
            return
        }
        if !hasLines {
            hideToken += 1
            panel.setFrame((clip ?? rects.reduce(rects[0]) { $0.union($1) }).insetBy(dx: -4, dy: -4), display: false)
            panel.orderFrontRegardless()
        }
        let origin = panel.frame.origin
        view.highlight(rects.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }, color, alpha: alpha)
    }

    /// Quét dải sáng lên chữ vừa được thay (toạ độ Cocoa). Không có nét gạch nào thì mượn tạm cửa sổ phủ rồi cất đi.
    func sweep(_ rects: [NSRect], clip: NSRect?) {
        guard !rects.isEmpty else { return }
        if !hasLines {
            let frame = (clip ?? rects.reduce(rects[0]) { $0.union($1) }).insetBy(dx: -4, dy: -4)
            panel.setFrame(frame, display: false)
            panel.orderFrontRegardless()
            hideToken += 1
            let token = hideToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, token == self.hideToken, !self.hasLines else { return }
                self.panel.orderOut(nil)
            }
        }
        let origin = panel.frame.origin
        view.sweep(rects.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) })
    }

    func hide() {
        view.highlight([])
        view.set([])
        hasLines = false
        hideToken += 1
        if panel.isVisible { panel.orderOut(nil) }
    }
}

// MARK: - Bảng đề nghị

/// Một mục chọn được trong bảng: rê chuột vào hoặc đi tới bằng phím mũi tên thì sáng lên, ↩ hoặc bấm thì chạy.
private protocol PanelItem: NSView {
    var onHover: () -> Void { get set }
    func setSelected(_ on: Bool, animated: Bool)
    func fire()
}

/// Một dòng chữ trong bảng: đề nghị cho từ (một dòng), hoặc câu đề nghị (xuống dòng được, có biểu tượng đầu dòng).
/// Dòng đang chọn có nền hiện dần: màu nhấn cho đề nghị, xám cho dòng phụ.
private final class SuggestionRow: NSView, PanelItem {
    private let label: NSTextField
    private let fill = CALayer()
    private let primary: Bool
    private let action: () -> Void
    private let plain: NSAttributedString
    private let icon: NSImageView?
    var onHover: () -> Void = {}
    /// Dòng này vừa được chọn / thôi được chọn (bảng dùng để tô nền cả câu trong văn bản).
    var onFocus: (Bool) -> Void = { _ in }
    static let padding: CGFloat = 8

    init(title: String, primary: Bool, action: @escaping () -> Void) {
        label = NSTextField(labelWithString: title)
        plain = NSAttributedString(string: title)
        icon = nil
        self.primary = primary
        self.action = action
        super.init(frame: .zero)
        label.font = primary ? .systemFont(ofSize: NSFont.systemFontSize + 1, weight: .medium) : .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = primary ? .labelColor : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        setUp(title)
    }

    /// Dòng nhiều dòng chữ, có biểu tượng đầu dòng (câu đề nghị).
    init(text: NSAttributedString, symbol: String, action: @escaping () -> Void) {
        label = NSTextField(wrappingLabelWithString: "")
        label.attributedStringValue = text
        label.isSelectable = false
        plain = text
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = .controlAccentColor
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        icon = image
        primary = true
        self.action = action
        super.init(frame: .zero)
        addSubview(image)
        setUp(text.string)
    }

    private func setUp(_ name: String) {
        wantsLayer = true
        fill.cornerRadius = 5
        fill.opacity = 0
        layer?.addSublayer(fill)
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(name)
    }

    required init?(coder: NSCoder) { nil }

    private var lead: CGFloat { SuggestionRow.padding + (icon == nil ? 0 : 20) }
    var fittingWidth: CGFloat { ceil(label.fittingSize.width) + lead + SuggestionRow.padding }

    /// Chiều cao cần có khi dòng rộng `width` (dòng nhiều dòng chữ thì cao theo chữ).
    func height(forWidth width: CGFloat) -> CGFloat {
        guard icon != nil else { return primary ? 26 : 22 }
        let size = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width - lead - SuggestionRow.padding, height: 2000)) ?? .zero
        return max(26, ceil(size.height) + 10)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        CATransaction.commit()
        if let icon {
            icon.frame = NSRect(x: SuggestionRow.padding, y: bounds.height - 21, width: 16, height: 16)
            label.frame = NSRect(x: lead, y: 5, width: bounds.width - lead - SuggestionRow.padding, height: bounds.height - 10)
        } else {
            let h = label.fittingSize.height
            label.frame = NSRect(x: lead, y: ((bounds.height - h) / 2).rounded(), width: bounds.width - lead - SuggestionRow.padding, height: h)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    func setSelected(_ on: Bool, animated: Bool = true) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            fill.backgroundColor = (primary ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.1)).cgColor
        }
        CATransaction.begin()
        if animated { CATransaction.setAnimationDuration(on ? 0.1 : 0.18) } else { CATransaction.setDisableActions(true) }
        fill.opacity = on ? 1 : 0
        CATransaction.commit()
        if primary {
            if icon != nil {
                // Câu đề nghị: lúc được chọn thì cả dòng chữ trắng trên nền màu nhấn; thôi chọn thì trả lại chữ có tô màu.
                let white = NSMutableAttributedString(attributedString: plain)
                white.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: white.length))
                label.attributedStringValue = on ? white : plain
                icon?.contentTintColor = on ? .white : .controlAccentColor
            } else {
                label.textColor = on ? .white : .labelColor
            }
        }
        onFocus(on)
    }

    func fire() { action() }

    override func mouseEntered(with event: NSEvent) { onHover() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

/// Nút chỉ có biểu tượng (kèm chú thích khi rê chuột và nhãn trợ năng): lệnh phụ của bảng, và thẻ của bảng câu.
/// `active`: thẻ đang mở, tô màu nhấn.
private final class IconButton: NSView, PanelItem {
    private let image: NSImageView
    private let fill = CALayer()
    private let action: () -> Void
    var onHover: () -> Void = {}
    var active = false { didSet { refresh(selected: false) } }
    static let size = NSSize(width: 30, height: 24)

    init(symbol: String, tip: String, action: @escaping () -> Void) {
        image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage())
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        self.action = action
        super.init(frame: NSRect(origin: .zero, size: IconButton.size))
        wantsLayer = true
        fill.cornerRadius = 5
        layer?.addSublayer(fill)
        addSubview(image)
        toolTip = tip
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
        refresh(selected: false)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        CATransaction.commit()
        image.frame = bounds.insetBy(dx: 6, dy: 3)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    private func refresh(selected: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color: NSColor = active ? NSColor.controlAccentColor.withAlphaComponent(selected ? 0.28 : 0.18) : NSColor.labelColor.withAlphaComponent(selected ? 0.1 : 0)
            fill.backgroundColor = color.cgColor
        }
        image.contentTintColor = active ? .controlAccentColor : selected ? .labelColor : .secondaryLabelColor
    }

    func setSelected(_ on: Bool, animated: Bool = true) {
        CATransaction.begin()
        if animated { CATransaction.setAnimationDuration(on ? 0.1 : 0.18) } else { CATransaction.setDisableActions(true) }
        refresh(selected: on)
        CATransaction.commit()
    }

    func fire() { action() }

    override func mouseEntered(with event: NSEvent) { onHover() }
    override func mouseExited(with event: NSEvent) { setSelected(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

/// Nền của bảng đề nghị: một màu đặc, sáng (trắng ở giao diện sáng), bo góc. Không dùng NSVisualEffectView: hiệu
/// ứng mờ của nó không theo góc bo nên bóng của cửa sổ ra hình chữ nhật (người dùng báo 2026-11-25).
private final class PanelBackground: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor(white: 0.24, alpha: 1) : NSColor.white).cgColor
        layer?.cornerRadius = 9
        layer?.borderWidth = 0.5
        layer?.borderColor = (dark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.12)).cgColor
    }
}

/// Kết quả của một việc AI đang ở trạng thái nào.
private enum SentenceState: Equatable {
    case loading
    case ready(String)
    case nothing  // không thấy gì để đổi, hoặc không làm được
}

extension SentenceTask {
    fileprivate var symbol: String {
        switch self {
        case .fix: return "checkmark.circle"
        case .improve: return "wand.and.stars"
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .shorten: return "arrow.down.right.and.arrow.up.left"
        case .expand: return "arrow.up.left.and.arrow.down.right"
        case .translate: return "globe"
        case .compose: return "square.and.pencil"
        }
    }

    fileprivate var title: String {
        switch self {
        case .fix: return L("Sửa chính tả", "Fix spelling")
        case .improve: return L("Cải tiến câu", "Improve")
        case .rewrite: return L("Viết lại", "Rewrite")
        case .shorten: return L("Làm ngắn gọn", "Shorten")
        case .expand: return L("Mở rộng", "Expand")
        case .translate: return L("Dịch Việt ↔ Anh", "Translate Vietnamese ↔ English")
        case .compose: return L("Viết thành câu từ các ý", "Write sentences from notes")
        }
    }
}

/// Phần chung của các bảng nổi: không kéo VNKey ra trước, không lấy tiêu điểm của ô đang nhập (phím đi qua event tap,
/// xem `Proofing.key`), có danh sách mục chọn được bằng ↑ ↓ ↩, và giữ MÉP TRÊN đứng yên khi nội dung đổi.
private class FloatingPanel: NSPanel {
    private var generation = 0
    private var items: [PanelItem] = []
    private var selected: Int?
    var hasSelection: Bool { selected != nil }
    var anchor = NSRect.zero

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { false }

    func select(_ index: Int?, animated: Bool = true) {
        guard index != selected else { return }
        if let old = selected, items.indices.contains(old) { items[old].setSelected(false, animated: animated) }
        selected = index
        if let index, items.indices.contains(index) { items[index].setSelected(true, animated: animated) }
    }

    var selection: Int? { selected }

    /// Phím mũi tên: xuống (+1) hoặc lên (-1), đi vòng. Chưa chọn mục nào thì ↓ chọn mục đầu, ↑ chọn mục cuối.
    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        let next = selected.map { ($0 + delta + items.count) % items.count } ?? (delta > 0 ? 0 : items.count - 1)
        select(next)
    }

    /// ↩: dùng mục đang chọn.
    func activate() {
        if let i = selected, items.indices.contains(i) { items[i].fire() }
    }

    func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.isSelectable = false
        return label
    }

    func separator() -> NSBox {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    /// Đặt nội dung mới vào cửa sổ, giữ mép trên đứng yên ngay dưới chữ (bảng dài ra hay ngắn lại ở phía dưới), để con
    /// trỏ chuột đang ở phần trên của bảng không bị rơi ra ngoài khi nội dung đổi.
    func place(_ back: NSView, width: CGFloat, height: CGFloat, items: [PanelItem], animate: Bool) {
        generation += 1
        selected = nil
        self.items = items
        for (i, item) in items.enumerated() { item.onHover = { [weak self] in self?.select(i) } }
        back.frame = NSRect(x: 0, y: 0, width: width, height: height)
        contentView = back
        var origin = NSPoint(x: anchor.minX - 5 - SuggestionRow.padding, y: anchor.minY - height - 5)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        if let v = screen?.visibleFrame {
            if origin.y < v.minY { origin.y = anchor.maxY + 5 }  // sát đáy màn hình: hiện phía trên chữ
            origin.x = min(max(origin.x, v.minX + 4), v.maxX - width - 4)
        }
        setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: true)
        orderFrontRegardless()
        displayIfNeeded()
        invalidateShadow()  // bóng tính theo hình đã vẽ: phải tính lại sau khi nền bo góc được vẽ
        if animate { Motion.present(self, duration: Motion.quick) } else { alphaValue = 1 }
    }

    /// Mờ dần rồi ẩn.
    func dismiss() {
        generation += 1
        let g = generation
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = Motion.quick
                animator().alphaValue = 0
            },
            completionHandler: { if g == self.generation { self.orderOut(nil) } })
    }
}

/// Bảng đề nghị cho một TỪ bị gạch: các đề nghị, rồi một hàng biểu tượng: mở bảng AI cho cả câu (nếu có), thêm vào
/// từ điển, bỏ qua lần này. Tự đóng khi chuột rời đi.
private final class SuggestionPanel: FloatingPanel {
    var onPick: (String) -> Void = { _ in }
    var onAdd: () -> Void = {}
    var onIgnore: () -> Void = {}
    var onOpenAI: () -> Void = {}
    var onCancel: () -> Void = {}

    private static func title(_ kind: ProofIssue.Kind) -> String {
        switch kind {
        case .missingMark: return L("Có thể thiếu dấu", "Possibly missing marks")
        case .slippedKey: return L("Có thể trật phím dấu", "Possibly a slipped tone key")
        case .swappedKeys: return L("Có thể gõ đảo phím", "Possibly swapped keys")
        case .doubledKey: return L("Có thể gõ lặp phím", "Possibly a repeated key")
        case .learnedTypo: return L("Lỗi gõ bạn hay sửa", "A typo you often fix")
        case .phrase: return L("Đề nghị cho cả cụm", "Suggestion for the phrase")
        case .english: return L("Chính tả tiếng Anh", "English spelling")
        case .spelling: return L("Có thể sai chính tả", "Possibly misspelled")
        case .wrongTone: return L("Có thể sai dấu thanh", "Possibly the wrong tone mark")
        }
    }

    func show(_ issue: ProofIssue, below anchor: NSRect, ai: Bool = false) {
        self.anchor = anchor
        let inset: CGFloat = 5, pad = SuggestionRow.padding
        let picks = issue.suggestions.map { s in SuggestionRow(title: s, primary: true) { [weak self] in self?.onPick(s) } }
        var icons: [IconButton] = []
        if ai {
            icons.append(IconButton(symbol: "sparkles", tip: L("Cả câu: sửa, viết lại, dịch…", "Whole sentence: fix, rewrite, translate…")) { [weak self] in self?.onOpenAI() })
        }
        icons.append(IconButton(symbol: "text.book.closed", tip: L("Thêm vào từ điển", "Add to Dictionary")) { [weak self] in self?.onAdd() })
        icons.append(IconButton(symbol: "eye.slash", tip: L("Bỏ qua lần này", "Ignore for Now")) { [weak self] in self?.onIgnore() })
        let header = caption(SuggestionPanel.title(issue.kind))
        let headerSize = header.fittingSize
        let iconsWidth = CGFloat(icons.count) * (IconButton.size.width + 2)
        let inner = max(150, ([headerSize.width + 2 * pad, iconsWidth] + picks.map(\.fittingWidth)).max() ?? 0)
        let width = min(inner, 340) + 2 * inset, rowWidth = width - 2 * inset

        let back = PanelBackground(frame: .zero)
        back.wantsLayer = true
        var y = inset, x = inset
        for icon in icons {
            icon.frame = NSRect(origin: NSPoint(x: x, y: y), size: IconButton.size)
            x += IconButton.size.width + 2
            back.addSubview(icon)
        }
        y += IconButton.size.height + 4
        let line = separator()
        line.frame = NSRect(x: inset + pad, y: y, width: rowWidth - 2 * pad, height: 1)
        back.addSubview(line)
        y += 5
        for row in picks.reversed() {
            let h = row.height(forWidth: rowWidth)
            row.frame = NSRect(x: inset, y: y, width: rowWidth, height: h)
            back.addSubview(row)
            y += h
        }
        y += 4
        header.frame = NSRect(x: inset + pad, y: y, width: rowWidth - 2 * pad, height: headerSize.height)
        back.addSubview(header)
        y += headerSize.height + 8
        place(back, width: width, height: y, items: picks + icons, animate: true)
    }
}

/// Bảng AI cho một CÂU hoặc ĐOẠN VĂN (riêng với bảng từ; người dùng yêu cầu tách 2026-11-25). Hàng trên: các thẻ việc
/// (biểu tượng), nút thử lại, nút đóng. Dưới: tên việc và hai nút phạm vi (câu / đoạn), kết quả, rồi "Dùng". Bảng
/// được GHIM: không tự đóng khi chuột rời đi.
private final class AIPanel: FloatingPanel {
    var onTask: (SentenceTask) -> Void = { _ in }
    var onRefresh: () -> Void = {}
    var onScope: (Bool) -> Void = { _ in }
    var onUse: (String) -> Void = { _ in }
    var onClose: () -> Void = {}

    private var tasks: [SentenceTask] = []
    private(set) var task = SentenceTask.fix
    private var paragraph = false
    private var canRefresh = false
    private var original = ""

    func show(tasks: [SentenceTask], task: SentenceTask, paragraph: Bool, canRefresh: Bool, original: String, state: SentenceState, anchor: NSRect) {
        self.tasks = tasks
        self.task = task
        self.paragraph = paragraph
        self.canRefresh = canRefresh
        self.original = original
        self.anchor = anchor
        render(state, animate: !isVisible)
    }

    /// Đổi thẻ hoặc có kết quả mới: vẽ lại tại chỗ.
    func update(task: SentenceTask, state: SentenceState) {
        self.task = task
        render(state, animate: false)
    }

    /// ← →: sang thẻ bên cạnh.
    func switchTask(_ delta: Int) {
        guard let i = tasks.firstIndex(of: task), tasks.count > 1 else { return }
        onTask(tasks[(i + delta + tasks.count) % tasks.count])
    }

    private func marked(_ fixed: String) -> NSAttributedString {
        // Từ nào khác bản gốc thì in đậm màu nhấn (chỉ so được khi hai bản cùng số từ, tức việc "sửa chính tả").
        let text = NSMutableAttributedString()
        let old = original.split(separator: " ", omittingEmptySubsequences: false), new = fixed.split(separator: " ", omittingEmptySubsequences: false)
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize), .foregroundColor: NSColor.labelColor]
        for (i, word) in new.enumerated() {
            if i > 0 { text.append(NSAttributedString(string: " ", attributes: base)) }
            var attributes = base
            if old.count == new.count, old[i] != word {
                attributes[.foregroundColor] = NSColor.controlAccentColor
                attributes[.font] = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            }
            text.append(NSAttributedString(string: String(word), attributes: attributes))
        }
        return text
    }

    private func render(_ state: SentenceState, animate: Bool) {
        let inset: CGFloat = 5, pad = SuggestionRow.padding
        let width: CGFloat = 372, rowWidth = width - 2 * inset
        var tabs: [IconButton] = []
        for t in tasks {
            let b = IconButton(symbol: t.symbol, tip: t.title) { [weak self] in self?.onTask(t) }
            b.active = t == task
            tabs.append(b)
        }
        let close = IconButton(symbol: "xmark", tip: L("Đóng", "Close")) { [weak self] in self?.onClose() }
        let again = IconButton(symbol: "arrow.clockwise", tip: L("Thử lại: nhờ viết bản khác", "Try again: ask for another version")) { [weak self] in self?.onRefresh() }
        let whole = IconButton(symbol: "text.alignleft", tip: L("Một câu", "One sentence")) { [weak self] in self?.onScope(false) }
        let block = IconButton(symbol: "text.justify", tip: L("Cả đoạn văn", "The whole paragraph")) { [weak self] in self?.onScope(true) }
        whole.active = !paragraph
        block.active = paragraph
        let header = caption(task.title)
        var use: SuggestionRow?
        let body: NSTextField
        switch state {
        case .ready(let fixed):
            let label = NSTextField(wrappingLabelWithString: "")
            label.attributedStringValue = marked(fixed)
            label.isSelectable = false
            body = label
            use = SuggestionRow(title: paragraph ? L("Dùng đoạn này", "Use This Paragraph") : L("Dùng câu này", "Use This Sentence"), primary: true) { [weak self] in
                self?.onUse(fixed)
            }
        case .loading:
            body = note(L("Đang viết…", "Working…"))
        case .nothing:
            body = note(
                task == .fix
                    ? L("Không thấy gì cần sửa ở đây.", "Nothing to fix here.")
                    : L("Không đưa ra được bản nào khác. Thử lại bằng nút ↻.", "No different version came back. Try again with ↻."))
        }
        let bodySize = body.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: rowWidth - 2 * pad, height: 2000)) ?? .zero
        let bodyHeight = min(260, max(18, ceil(bodySize.height)))

        let back = PanelBackground(frame: .zero)
        back.wantsLayer = true
        var y = inset
        if let use {
            use.frame = NSRect(x: inset, y: y, width: rowWidth, height: 26)
            back.addSubview(use)
            y += 26 + 4
        }
        body.frame = NSRect(x: inset + pad, y: y + 2, width: rowWidth - 2 * pad, height: bodyHeight)
        back.addSubview(body)
        y += bodyHeight + 6
        // Hàng tên việc + phạm vi.
        header.frame = NSRect(x: inset + pad, y: y + 5, width: rowWidth - 2 * pad - 70, height: header.fittingSize.height)
        back.addSubview(header)
        block.frame = NSRect(origin: NSPoint(x: width - inset - IconButton.size.width, y: y), size: IconButton.size)
        whole.frame = NSRect(origin: NSPoint(x: block.frame.minX - IconButton.size.width - 2, y: y), size: IconButton.size)
        back.addSubview(whole)
        back.addSubview(block)
        y += IconButton.size.height + 3
        let line = separator()
        line.frame = NSRect(x: inset + pad, y: y, width: rowWidth - 2 * pad, height: 1)
        back.addSubview(line)
        y += 5
        var x = inset
        for tab in tabs {
            tab.frame = NSRect(origin: NSPoint(x: x, y: y), size: IconButton.size)
            x += IconButton.size.width + 2
            back.addSubview(tab)
        }
        close.frame = NSRect(origin: NSPoint(x: width - inset - IconButton.size.width, y: y), size: IconButton.size)
        back.addSubview(close)
        if canRefresh {
            again.frame = NSRect(origin: NSPoint(x: close.frame.minX - IconButton.size.width - 2, y: y), size: IconButton.size)
            back.addSubview(again)
        }
        y += IconButton.size.height + inset

        place(back, width: width, height: y, items: use.map { [$0] } ?? [], animate: animate)
        if use != nil { select(0, animated: false) }
    }
}

/// Nút ✦ nhỏ hiện cạnh câu mà chuột vừa dừng lên: BẤM thì mở bảng AI cho câu đó (rê chuột vào không mở).
private final class AIChip {
    var onOpen: () -> Void = {}
    private let panel: NSPanel
    var frame: NSRect { panel.isVisible ? panel.frame : .zero }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 30, height: 24), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let back = PanelBackground(frame: NSRect(x: 0, y: 0, width: 30, height: 24))
        back.wantsLayer = true
        let button = IconButton(symbol: "sparkles", tip: L("Sửa, viết lại, dịch câu này…", "Fix, rewrite or translate this sentence…")) { [weak self] in self?.onOpen() }
        button.active = true
        button.frame = back.bounds
        back.addSubview(button)
        panel.contentView = back
    }

    /// Hiện với mép trái ở `point.x`, canh giữa theo `point.y` (toạ độ Cocoa), kẹp trong màn hình.
    func show(at point: NSPoint) {
        var origin = NSPoint(x: point.x, y: point.y - 12)
        if let v = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, v.minX + 2), v.maxX - 32)
            origin.y = min(max(origin.y, v.minY + 2), v.maxY - 26)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        panel.invalidateShadow()
        Motion.present(panel, duration: Motion.quick)
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }
}
