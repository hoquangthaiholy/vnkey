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
/// - ứng dụng trả lời theo số thứ tự ký tự (AppKit: TextEdit, Ghi chú, Mail…) hỏi `AXBoundsForRange`; trang web và
///   Electron không trả lời câu đó nên hỏi qua "text marker" (`bounds(_:_:text:stamp:)`, làm 2026-11-27, CHƯA kiểm
///   chứng trên ứng dụng thật). Ứng dụng Electron chỉ dựng cây trợ năng khi được yêu cầu (`AXManualAccessibility`);
/// - không có thông báo cuộn đáng tin nên hỏi lại định kỳ: nét gạch bám theo chữ chậm một nhịp;
/// - ứng dụng không cho ghi `AXSelectedText` (web, Electron) thì bôi chọn chữ cũ rồi GÕ chữ mới bằng sự kiện phím
///   (`typeText`); không bôi chọn được thì không thay (có ghi nhật ký).
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
    /// Gõ một đoạn chữ vào ứng dụng đang ở trước bằng sự kiện phím (KeyTap), cho ô không cho ghi qua Trợ năng.
    var typeText: (String) -> Void = { _ in }
    /// Lý do gần nhất khiến ô đang nhập không được soát; chỉ ghi nhật ký khi lý do đổi.
    private var lastWhy = ""
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
    private static let restDelay = 0.2
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

    func configure(on: Bool, config: Config, lexicon: Lexicon, context: ContextModel?, english: Bool, sentence: Bool, browsers: Bool, skip: Set<String>) {
        if browsers != Proofing.allowEnhanced {
            Proofing.allowEnhanced = browsers
            Log.write("PROOF gợi ý trong trình duyệt Chromium: \(browsers ? "bật" : "tắt")")
            if !browsers { queue.async { Proofing.relax("tắt công tắc") } }
        }
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
                // `where` chỉ áp cho mẫu đứng ngay trước nó, nên phải lặp lại cho từng phím.
                case 36 where aiPanel.hasSelection, 76 where aiPanel.hasSelection,
                    48 where aiPanel.hasSelection:  // ↩, Enter, ⇥
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
            case 36 where popover.hasSelection, 76 where popover.hasSelection,
                48 where popover.hasSelection:  // ↩, Enter, ⇥
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
    /// `at`: vị trí tuyệt đối (UTF-16) của chữ mới khi đã biết (chọn một đề nghị): dùng nó thay vì suy từ con trỏ, vì
    /// ở ứng dụng web con trỏ chưa kịp dời tới sau chữ vừa gõ thay, dải sáng sẽ rơi vào chữ đứng TRƯỚC (người dùng báo
    /// ở Zalo 2026-11-27).
    func pulse(length: Int, trailing: Int = 0, at absolute: Int? = nil) {
        guard length > 0 else { return }
        queue.async { [weak self] in
            guard let snap = Proofing.read().snap else { return }
            let end: Int
            if let absolute {
                end = absolute - snap.base + length
            } else if let caret = snap.caret {
                end = caret - trailing - snap.base
            } else {
                return
            }
            let start = end - length
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
            guard let value = AXValueCreate(.cgPoint, &point) else { return }
            var at: CFRange?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXRangeForPositionParameterizedAttribute as CFString, value, &out) == .success {
                at = Proofing.range(out)
            }
            // Trang web / Electron: hỏi text marker dưới điểm đó rồi đổi ra số thứ tự ký tự.
            if at == nil, let marker = Proofing.askAny(element, "AXTextMarkerForPosition", value),
                let index = Proofing.askAny(element, "AXIndexForTextMarker", marker) as? Int
            {
                at = CFRange(location: index, length: 0)
            }
            guard let at else { return }
            DispatchQueue.main.async {
                guard let self, ticket == self.asking, !self.aiOpen, self.shownIssue == nil, self.hint == nil else { return }
                let index = at.location - self.base
                self.locate(index: index, paragraph: false) { found in
                    guard let found, !found.rects.isEmpty, !self.aiOpen, self.shownIssue == nil, let last = found.rects.last else { return }
                    // Chuột ở chỗ trống của ô (cuối dòng, dưới đoạn chữ) thì ứng dụng vẫn trả về ký tự GẦN NHẤT: phải
                    // kiểm lại là chuột thật sự nằm trên chữ của câu, nếu không câu sáng lên dù không ai rê chuột vào nó.
                    guard found.rects.contains(where: { $0.insetBy(dx: -3, dy: -3).contains(p) }) else {
                        Log.write("PROOF chuột dừng ở chỗ trống của ô, không trên câu: không hiện nút ✦")
                        return
                    }
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
        // Đang gõ dở và không có nét gạch nào phải giữ đúng chỗ: KHÔNG đọc ô. Đọc lúc này chẳng để làm gì (chữ đổi mà
        // còn gõ thì `took` cũng chỉ ghi nhớ rồi đợi), trong khi mỗi lần đọc là chục câu hỏi Trợ năng mà trang web phải
        // trả lời trên luồng chính của nó, ngay giữa lúc nó đang vẽ chữ vừa gõ (người dùng báo 2026-11-28: gõ ở Gemini
        // trong Safari hơi khựng). Giữ nhịp nhanh để soát ngay khi ngừng gõ.
        if issues.isEmpty, shownIssue == nil, lastInput == .typing, Date().timeIntervalSince(lastKey) < 0.4 {
            stale = true
            schedule(Proofing.busyInterval)
            return
        }
        busy = true
        let known = element, knownText = text, knownBase = base, knownIssues = issues
        queue.async { [weak self] in
            let start = CFAbsoluteTimeGetCurrent()
            let (snap, why) = Proofing.read()
            // Chữ không đổi: hỏi luôn khung của các chỗ đã biết, đỡ một lượt qua lại giữa hai luồng.
            var frames: [[CGRect]]?
            if let snap, let known, CFEqual(snap.element, known), snap.text == knownText, snap.base == knownBase {
                frames = Proofing.frames(of: knownIssues, in: snap)
            }
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            DispatchQueue.main.async { self?.took(snap, frames, readMs: ms, why: why) }
        }
    }

    private func took(_ snap: Snapshot?, _ frames: [[CGRect]]?, readMs: Double, why: String) {
        busy = false
        guard enabled else { return }
        if why != lastWhy {
            lastWhy = why
            if !why.isEmpty { Log.write("PROOF không soát: \(why)") }
        }
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
        if Log.enabled {
            // Tên ứng dụng để đọc nhật ký biết dòng này thuộc về đâu (rê chuột và dán không sinh dòng KEY nào).
            let app = NSRunningApplication(processIdentifier: snap.pid)?.bundleIdentifier ?? "?"
            Log.write(String(format: "PROOF soát %d ký tự: %d chỗ %@ đọc %.1fms soát %.1fms app=%@", snap.text.utf16.count, found.count, kinds, readMs, ms, app))
        }
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

    // Các bảng nhớ dưới đây CHỈ được đụng tới ở hàng đợi nền `queue`.
    /// Ứng dụng đã được yêu cầu dựng cây trợ năng (mỗi tiến trình một lần).
    private static var askedTree: Set<pid_t> = []
    /// Cách đã tìm ra để hỏi khung của một đoạn chữ.
    private enum Located {
        /// Đoạn nằm trọn trong một phần tử chữ con (`AXStaticText`), tại khoảng này của nó.
        case leaf(AXUIElement, CFRange)
        case marker(CFTypeRef)
        /// Không cách nào dùng được: khỏi hỏi lại mỗi nhịp.
        case none
    }
    /// Cách hỏi khung của từng đoạn trong lần đọc hiện tại (`stamp` = mã băm của chữ + vị trí). Đoạn đã có trong bảng
    /// thì khỏi hỏi `AXBoundsForRange` trên ô nữa. (Không nhớ theo tiến trình: trong trình duyệt, thanh địa chỉ và
    /// trang web cùng một tiến trình nhưng trả lời khác nhau; nhật ký 2026-11-27 ở Chrome.)
    private static var located: (stamp: Int, found: [String: Located], retried: Bool, rebuilt: Bool) = (0, [:], false, false)
    /// Các phần tử chữ con của ô và vị trí của chúng trong chữ của ô (số thứ tự tuyệt đối), xem `leaves`.
    private static var leafCache: (element: AXUIElement, leaves: [(element: AXUIElement, start: Int, length: Int)], at: CFAbsoluteTime)?
    /// Các vị trí có thể của ô trong cả trang (cái trúng gần nhất đứng đầu), nhớ theo ô: tính lại tốn cả chục câu hỏi.
    private static var originCache: (element: AXUIElement, candidates: [Int], note: String)?
    /// Số liệu chẩn đoán (không có chữ): số đoạn phải tìm cách hỏi khác, số tìm được qua phần tử con / qua marker, số
    /// lệch chữ, số không dựng được; độ dài cần và đọc được ở lần lệch gần nhất (-1 = ứng dụng không trả chữ).
    private struct MarkerStats: Equatable {
        var asked = 0, viaLeaf = 0, viaMarker = 0, mismatched = 0, missing = 0, origin = -1, wanted = 0, got = 0, leaves = -1
        var note = "", origins = ""
    }
    private static var markerStats = MarkerStats(), markerReported = MarkerStats()
    /// Trình duyệt nhân Chromium: phải bật `AXEnhancedUserInterface` thì chúng mới dựng cây trợ năng của trang web
    /// và báo ô nhập. Người dùng thấy gõ trong Chrome NẶNG hơn khi chế độ đó bật, nhất là ở ô chat với AI
    /// (2026-11-27), nên chỉ làm khi họ bật công tắc `proofreadBrowsers` (mặc định tắt): `allowEnhanced`. Bật MỘT LẦN
    /// cho mỗi tiến trình rồi để yên, tắt khi công tắc tắt. Đã thử "chỉ bật lúc ngừng gõ, tắt khi gõ tiếp" rồi bỏ: đo
    /// 2026-11-27 trên trang thử 3.600 phần tử, lần đọc đầu tiên sau mỗi lần bật mất 0,4 giây (trình duyệt dựng lại cả
    /// cây), còn khi đã bật sẵn thì trong trang không đo được khác biệt; bật tắt liên tục chỉ trả cái giá đó nhiều lần.
    /// `enhancedOn`: tiến trình đang bật (chỉ đụng tới ở hàng đợi nền).
    private static var allowEnhanced = false
    private static var enhancedOn: Set<pid_t> = []

    /// Tắt chế độ trợ năng ở mọi trình duyệt VNKey đang bật. Gọi ở hàng đợi nền.
    private static func relax(_ why: String) {
        guard !enhancedOn.isEmpty else { return }
        for pid in enhancedOn {
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        let n = enhancedOn.count
        enhancedOn = []
        DispatchQueue.main.async { Log.write("PROOF trình duyệt: tắt trợ năng ở \(n) tiến trình (\(why))") }
    }

    static let enhancedBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]
    /// Trình soạn mã dựng trên Electron: bật cây trợ năng làm chúng chuyển sang chế độ cho trình đọc màn hình (hỏi
    /// người dùng, đổi cách hiển thị), và soát chính tả tiếng Việt trong mã nguồn không có ích. Không yêu cầu.
    private static let noTreeRequest: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
    ]

    private static func askAny(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var out: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &out) == .success ? out : nil
    }

    /// Ô đang nhận phím. Hỏi cả hệ thống trước; ứng dụng Electron / Chromium thường không trả lời vì chưa dựng cây
    /// trợ năng: khi đó hỏi thẳng ứng dụng ở trước và yêu cầu nó dựng (có hiệu lực cho các nhịp sau).
    private static func focused() -> (element: AXUIElement?, why: String) {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        if let f = copy(system, kAXFocusedUIElementAttribute), CFGetTypeID(f) == AXUIElementGetTypeID() { return ((f as! AXUIElement), "") }
        guard let front = NSWorkspace.shared.frontmostApplication else { return (nil, "không có ứng dụng ở trước") }
        let pid = front.processIdentifier, name = front.bundleIdentifier ?? "?"
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        if let f = copy(app, kAXFocusedUIElementAttribute), CFGetTypeID(f) == AXUIElementGetTypeID() { return ((f as! AXUIElement), "") }
        if noTreeRequest.contains(name) { return (nil, "\(name) không báo ô đang nhập; không yêu cầu bật cây trợ năng (trình soạn mã)") }
        if askedTree.insert(pid).inserted {
            let err = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            return (nil, "\(name) không báo ô đang nhập; đã yêu cầu bật cây trợ năng (\(err.rawValue))")
        }
        // Trình duyệt nhân Chromium không nhận `AXManualAccessibility` (đó là của Electron; nhật ký 2026-11-27: Chrome
        // trả -25205 và vẫn không báo ô nhập của trang web). Chúng chỉ dựng cây trợ năng cho trang web khi một công
        // cụ trợ năng tự giới thiệu bằng `AXEnhancedUserInterface`. Cái giá: trình duyệt tốn thêm tài nguyên, và vài
        // trình quản lý cửa sổ dời / đổi cỡ cửa sổ của nó chậm đi. Chỉ làm với các trình duyệt trong danh sách, một
        // lần cho mỗi tiến trình, và chỉ khi người dùng đã bật công tắc; khởi động lại trình duyệt là hết.
        if allowEnhanced, enhancedBrowsers.contains(name), enhancedOn.insert(pid).inserted {
            let err = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            return (nil, "\(name) không báo ô đang nhập; đã bật trợ năng của trình duyệt (\(err.rawValue))")
        }
        return (nil, "\(name) không báo ô đang nhập")
    }

    /// Chữ của một đoạn trong ô: hỏi theo đoạn, không được thì cắt từ toàn bộ nội dung (`AXValue`).
    private static func string(_ element: AXUIElement, _ range: CFRange) -> String? {
        if let s = ask(element, kAXStringForRangeParameterizedAttribute, range) as? String { return s }
        guard let whole = copy(element, kAXValueAttribute) as? String else { return nil }
        let units = Array(whole.utf16)
        guard range.location >= 0, range.length >= 0, range.location + range.length <= units.count else { return nil }
        return String(utf16CodeUnits: Array(units[range.location..<(range.location + range.length)]), count: range.length)
    }

    /// Ô đang nhận phím và đoạn chữ quanh vùng nhìn thấy của nó. Không soát được thì `snap` là nil và `why` nói lý do
    /// (chỉ có vai trò của ô và tên ứng dụng, không có chữ).
    private static func read() -> (snap: Snapshot?, why: String) {
        let found = focused()
        guard let element = found.element else { return (nil, found.why) }
        AXUIElementSetMessagingTimeout(element, 0.1)
        let role = copy(element, kAXRoleAttribute) as? String ?? "?"
        guard textRoles.contains(role) else { return (nil, "không phải ô nhập (role=\(role))") }
        // Ô mật khẩu: không bao giờ đọc.
        guard copy(element, kAXSubroleAttribute) as? String != "AXSecureTextField" else { return (nil, "ô mật khẩu") }
        var total = (copy(element, kAXNumberOfCharactersAttribute) as? Int) ?? 0
        // Ô của trang web có khi không báo số ký tự: đếm từ toàn bộ nội dung.
        if total == 0 { total = (copy(element, kAXValueAttribute) as? String)?.utf16.count ?? 0 }
        guard total > 0 else { return (nil, "") }  // ô trống: bình thường, không cần ghi
        var window = CFRange(location: 0, length: min(total, maxChars))
        if total > maxChars, let visible = range(copy(element, kAXVisibleCharacterRangeAttribute)) {
            let from = max(0, visible.location - margin)
            window = CFRange(location: from, length: min(total - from, min(visible.length + 2 * margin, maxChars)))
        }
        guard let text = string(element, window) else { return (nil, "không đọc được chữ của ô (role=\(role))") }
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
        return (Snapshot(element: element, window: host, pid: pid, text: text, base: window.location, caret: selection?.location, clip: clip), "")
    }

    /// Text marker (kiểu định vị của WebKit / Chromium) cho một đoạn tính theo số thứ tự ký tự.
    private static func markerRange(_ element: AXUIElement, _ range: CFRange) -> CFTypeRef? {
        guard let from = askAny(element, "AXTextMarkerForIndex", range.location as CFNumber),
            let to = askAny(element, "AXTextMarkerForIndex", (range.location + range.length) as CFNumber)
        else { return nil }
        return askAny(element, "AXTextMarkerRangeForUnorderedTextMarkers", [from, to] as CFArray)
    }

    /// Các vị trí có thể (số thứ tự ký tự trong CẢ TRANG) của ký tự đầu tiên trong ô. `AXTextMarkerForIndex` của
    /// WebKit và Chromium đếm từ đầu trang chứ không từ đầu ô, nên phải cộng thêm chừng này. Nhật ký 2026-11-27 ở
    /// Claude desktop: dựng theo số của ô thì đọc ra chữ khác cùng độ dài, và `AXIndexForTextMarker` của đầu ô trả 0
    /// (nó đếm trong phần tử chứa marker, không phải trong trang). Cách đáng tin hơn: đo độ dài đoạn từ đầu trang tới
    /// đầu ô. Trả về mọi ứng viên; `bounds` thử từng cái và chỉ nhận cái đọc ra đúng chữ.
    private static func origins(of element: AXUIElement) -> (candidates: [Int], note: String) {
        var out: [Int] = [], note = ""
        if let whole = askAny(element, "AXTextMarkerRangeForUIElement", element),
            let first = askAny(element, "AXStartTextMarkerForTextMarkerRange", whole)
        {
            // Marker đầu trang: hỏi ô, không có thì leo lên vùng trang web chứa nó.
            var top = copy(element, "AXStartTextMarker"), node = element, hops = 0
            while top == nil, hops < 40, let parent = copy(node, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() {
                node = parent as! AXUIElement
                hops += 1
                if copy(node, kAXRoleAttribute) as? String == "AXWebArea" { top = copy(node, "AXStartTextMarker"); break }
            }
            if let top, let lead = askAny(element, "AXTextMarkerRangeForUnorderedTextMarkers", [top, first] as CFArray),
                let n = askAny(element, "AXLengthForTextMarkerRange", lead) as? Int
            {
                out.append(n)
                note += "theo độ dài=\(n)"
            } else {
                note += "theo độ dài=không(\(top == nil ? "không có marker đầu trang, leo \(hops) cấp" : "không đo được"))"
            }
            if let i = askAny(element, "AXIndexForTextMarker", first) as? Int {
                out.append(i)
                note += " theo chỉ số=\(i)"
            } else {
                note += " theo chỉ số=không"
            }
        } else {
            note = "ô không trả marker của chính nó"
        }
        out.append(0)
        var seen: Set<Int> = []
        return (out.filter { seen.insert($0).inserted }, note)
    }

    /// Các phần tử chữ (`AXStaticText`) nằm trong ô, mỗi cái kèm vị trí chữ của nó trong `text` (cộng `base` thành số
    /// thứ tự tuyệt đối). Tìm bằng cách dò chữ của từng phần tử trong `text`, lần lượt từ trái sang. Giới hạn số phần
    /// tử phải hỏi để một văn bản rất dài không làm ứng dụng kia bận.
    private static func leaves(of element: AXUIElement, text: String, base: Int) -> [(element: AXUIElement, start: Int, length: Int)] {
        var out: [(element: AXUIElement, start: Int, length: Int)] = []
        let whole = text as NSString
        var cursor = 0, visited = 0
        func walk(_ node: AXUIElement, _ depth: Int) {
            guard depth <= 8, visited < 300, let kids = copy(node, kAXChildrenAttribute) as? [AXUIElement] else { return }
            for kid in kids {
                visited += 1
                if visited >= 300 { return }
                if copy(kid, kAXRoleAttribute) as? String == "AXStaticText" {
                    guard let value = copy(kid, kAXValueAttribute) as? String, !value.isEmpty, cursor < whole.length else { continue }
                    let at = whole.range(of: value, options: [], range: NSRange(location: cursor, length: whole.length - cursor))
                    guard at.location != NSNotFound else { continue }
                    out.append((kid, base + at.location, at.length))
                    cursor = at.location + at.length
                } else {
                    walk(kid, depth + 1)
                }
            }
        }
        walk(element, 0)
        return out
    }

    /// Khung (toạ độ AX) của một đoạn chữ, hỏi theo ba cách, cách trước không được mới tới cách sau:
    /// 1. `AXBoundsForRange` trên chính ô: ứng dụng AppKit, và ô nhập của Safari.
    /// 2. Chromium / Electron trả khung RỖNG cho câu trên (đo bằng `VNKey --ax-probe` ở Claude desktop, 2026-11-27),
    ///    nhưng phần tử chữ con (`AXStaticText`) của ô thì trả khung thật: tìm phần tử con chứa đoạn đó rồi hỏi nó.
    /// 3. Text marker, đánh số theo cả trang (WebKit). Ở Chromium cách này đọc ra chữ của chỗ khác trong trang.
    /// Cách 2 và 3 CHỈ được tin khi chữ ứng dụng đọc ra đúng là `text`: lệch thì thà không gạch còn hơn gạch nhầm chữ.
    private static func bounds(_ element: AXUIElement, _ range: CFRange, text: String, snap: Snapshot, stamp: Int) -> CGRect? {
        if located.stamp != stamp { located = (stamp, [:], false, false) }
        let key = "\(range.location):\(range.length)"
        if located.found[key] == nil {
            if let r = HUD.rect(ask(element, kAXBoundsForRangeParameterizedAttribute, range)), r.width > 1, r.height > 1 { return r }
            markerStats.asked += 1
            let want = text.precomposedStringWithCanonicalMapping
            var found = Located.none

            // Cách 2: phần tử chữ con. Bảng phần tử dùng lại giữa các lần đọc (dựng lại tốn nhiều câu hỏi); chữ đọc ra
            // không khớp thì dựng lại một lần cho lần đọc này rồi thử lại.
            func viaLeaf() -> Bool {
                guard let cache = leafCache, CFEqual(cache.element, element) else { return false }
                guard let leaf = cache.leaves.first(where: { $0.start <= range.location && range.location + range.length <= $0.start + $0.length })
                else { return false }
                let inside = CFRange(location: range.location - leaf.start, length: range.length)
                guard (ask(leaf.element, kAXStringForRangeParameterizedAttribute, inside) as? String)?.precomposedStringWithCanonicalMapping == want
                else { return false }
                found = .leaf(leaf.element, inside)
                return true
            }
            func rebuildLeaves() {
                leafCache = (element, leaves(of: element, text: snap.text, base: snap.base), CFAbsoluteTimeGetCurrent())
                located.rebuilt = true
                markerStats.leaves = leafCache?.leaves.count ?? 0
            }
            if leafCache == nil || !CFEqual(leafCache!.element, element) { rebuildLeaves() }
            if !viaLeaf(), !located.rebuilt {
                rebuildLeaves()
                _ = viaLeaf()
            }

            // Cách 3: text marker.
            if case .none = found, leafCache?.leaves.isEmpty ?? true {
                var built = false
                func attempt() {
                    if originCache == nil || !CFEqual(originCache!.element, element) {
                        let o = origins(of: element)
                        originCache = (element, o.candidates, o.note)
                        markerStats.origins = o.note
                    }
                    for base in originCache?.candidates ?? [0] {
                        guard let made = markerRange(element, CFRange(location: base + range.location, length: range.length)) else { continue }
                        built = true
                        let read = (askAny(element, "AXStringForTextMarkerRange", made) as? String)?.precomposedStringWithCanonicalMapping
                        if read == want {
                            found = .marker(made)
                            markerStats.origin = base
                            if var cache = originCache, cache.candidates.first != base {
                                cache.candidates.removeAll { $0 == base }
                                cache.candidates.insert(base, at: 0)
                                originCache = cache
                            }
                            return
                        }
                        markerStats.wanted = want.utf16.count
                        markerStats.got = read?.utf16.count ?? -1
                    }
                }
                attempt()
                // Chữ phía trước ô trong trang có thể vừa đổi: tính lại vị trí gốc một lần cho mỗi lần đọc.
                if case .none = found, !located.retried {
                    located.retried = true
                    originCache = nil
                    attempt()
                }
                if case .none = found { if built { markerStats.mismatched += 1 } else { markerStats.missing += 1 } }
            }
            switch found {
            case .leaf: markerStats.viaLeaf += 1
            case .marker: markerStats.viaMarker += 1
            case .none: break
            }
            located.found[key] = found
        }
        let r: CGRect?
        switch located.found[key] ?? .none {
        case .leaf(let leaf, let inside): r = HUD.rect(ask(leaf, kAXBoundsForRangeParameterizedAttribute, inside))
        case .marker(let span): r = HUD.rect(askAny(element, "AXBoundsForTextMarkerRange", span))
        case .none: return nil
        }
        guard let r, r.width > 1, r.height > 1 else {
            markerStats.note = "tìm đúng chữ nhưng ứng dụng không trả khung"
            return nil
        }
        return r
    }

    /// Khung (toạ độ AX) của từng chỗ. Cụm nhiều từ hỏi riêng từng từ rồi gộp các từ cùng dòng, để cụm vắt qua hai
    /// dòng vẫn gạch đúng. Chỗ nằm ngoài vùng nhìn thấy trả về mảng rỗng.
    private static func frames(of issues: [ProofIssue], in snap: Snapshot) -> [[CGRect]] {
        var hasher = Hasher()
        hasher.combine(snap.text)
        hasher.combine(snap.base)
        let stamp = hasher.finalize()
        defer {
            // Lần đầu dùng text marker ở một ô, hoặc khi có đoạn lệch: ghi số lượng (không có chữ) để chẩn đoán.
            if markerStats != markerReported {
                markerReported = markerStats
                let s = markerStats
                DispatchQueue.main.async {
                    Log.write(
                        "PROOF khung web: \(s.asked) đoạn ô không trả khung; qua phần tử con \(s.viaLeaf) (ô có \(s.leaves) phần tử chữ), qua marker \(s.viaMarker), lệch chữ \(s.mismatched) (cần \(s.wanted), đọc \(s.got)), không dựng được \(s.missing) \(s.origins) \(s.note)")
                }
            }
        }
        return issues.map { issue in
            var pieces: [(range: CFRange, text: String)] = []
            let units = Array(issue.text.utf16)
            var start: Int?
            func close(_ end: Int) {
                guard let s = start else { return }
                pieces.append((CFRange(location: snap.base + issue.range.lowerBound + s, length: end - s), String(utf16CodeUnits: Array(units[s..<end]), count: end - s)))
                start = nil
            }
            for (i, unit) in units.enumerated() {
                if unit == 0x20 { close(i) } else if start == nil { start = i }
            }
            close(units.count)
            let rects = pieces.compactMap { bounds(snap.element, $0.range, text: $0.text, snap: snap, stamp: stamp) }
            guard rects.count == pieces.count else { return [] }
            if let clip = snap.clip, !rects.allSatisfy({ clip.insetBy(dx: -2, dy: -2).contains($0) }) {
                // Toạ độ màn hình, không phải chữ: để biết khung chữ lệch khỏi ô bao xa.
                if let r = rects.first {
                    markerStats.note = "khung chữ nằm ngoài vùng nhìn thấy của ô: chữ \(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)); ô \(Int(clip.minX)),\(Int(clip.minY)) \(Int(clip.width))x\(Int(clip.height))"
                }
                return []
            }
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
        let knownBase = base, clip = lastClip, knownText = text
        queue.async {
            // Cùng chữ với lần soát gần nhất, để bảng "cách hỏi khung" (`located`) dùng chung được với vòng soát.
            let snap = Snapshot(element: element, window: nil, pid: 0, text: knownText, base: knownBase, caret: nil, clip: clip)
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
            var typeIt = false
            if Proofing.string(element, target) != expected {
                outcome = "chữ đã đổi, không thay"
            } else {
                var selected = false
                if let select = AXValueCreate(.cfRange, &target) {
                    selected = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, select) == .success
                }
                if !selected, let span = Proofing.markerRange(element, target) {
                    selected = AXUIElementSetAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, span) == .success
                }
                if !selected {
                    outcome = "không bôi chọn được"
                } else {
                    func count() -> Int { (Proofing.copy(element, kAXNumberOfCharactersAttribute) as? Int) ?? (Proofing.copy(element, kAXValueAttribute) as? String)?.utf16.count ?? -1 }
                    let before = count()
                    let err = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFString)
                    // Ứng dụng AppKit ghi ngay. Chromium / Electron BÁO thành công nhưng không đổi gì (nhật ký
                    // 2026-11-27 ở Claude desktop: "đã thay" mà chữ còn nguyên), nên phải đọc lại: chữ mới nằm đúng chỗ
                    // và độ dài của ô đổi đúng bằng chênh lệch giữa chữ mới và chữ cũ.
                    var written = false
                    if err == .success {
                        let after = CFRange(location: target.location, length: replacement.utf16.count)
                        for attempt in 0..<4 where !written {
                            if attempt > 0 { usleep(50_000) }
                            written = Proofing.string(element, after) == replacement && count() - before == replacement.utf16.count - expected.utf16.count
                        }
                    }
                    if written {
                        var end = CFRange(location: target.location + replacement.utf16.count, length: 0)
                        if let v = AXValueCreate(.cfRange, &end) {
                            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, v)
                        }
                    } else if Proofing.string(element, target) != expected {
                        // Chữ đã đổi theo cách không ngờ tới: không gõ thêm gì vào.
                        outcome = "ghi qua Trợ năng cho kết quả lạ (\(err.rawValue)), không gõ thêm"
                    } else {
                        // Chữ cũ còn nguyên và đang được bôi chọn: gõ chữ mới đè lên. Trình duyệt bôi chọn không tức
                        // thì, nên đợi tới khi vùng chọn ĐÚNG là chữ cũ rồi mới gõ; không thấy đúng thì thôi, để khỏi
                        // gõ chữ vào sai chỗ.
                        var seen = "không đọc được vùng chọn"
                        for attempt in 0..<5 where !typeIt {
                            if attempt > 0 { usleep(60_000) }
                            if let now = Proofing.range(Proofing.copy(element, kAXSelectedTextRangeAttribute)) {
                                typeIt = now.location == target.location && now.length == target.length
                                seen = "vùng chọn \(now.location)+\(now.length), cần \(target.location)+\(target.length)"
                            }
                        }
                        let why = err == .success ? "ứng dụng báo đã ghi nhưng chữ không đổi" : "ứng dụng không cho ghi (\(err.rawValue))"
                        outcome = typeIt ? "đã gõ thay (\(why))" : "\(why); không bôi chọn được chữ cũ (\(seen))"
                    }
                }
            }
            let location = target.location
            DispatchQueue.main.async {
                Log.write("PROOF thay loại=\(label): \(outcome)")
                if typeIt { self?.typeText(replacement) }
                if outcome == "đã thay" || typeIt {
                    self?.didReplace()
                    // Chữ gõ thay cần một nhịp mới tới ứng dụng: đợi rồi mới hỏi khung của chữ mới.
                    DispatchQueue.main.asyncAfter(deadline: .now() + (typeIt ? 0.15 : 0)) {
                        self?.pulse(length: replacement.utf16.count, at: location)
                    }
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

/// Một dòng đề nghị trong bảng của từ. Dòng đang chọn có nền màu nhấn hiện dần, chữ trắng.
private final class SuggestionRow: NSView, PanelItem {
    private let label: NSTextField
    private let fill = CALayer()
    private let action: () -> Void
    var onHover: () -> Void = {}
    static let padding: CGFloat = 8
    static let height: CGFloat = 26

    init(title: String, action: @escaping () -> Void) {
        label = NSTextField(labelWithString: title)
        self.action = action
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: NSFont.systemFontSize + 1, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        wantsLayer = true
        fill.cornerRadius = 5
        fill.opacity = 0
        layer?.addSublayer(fill)
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { nil }

    var fittingWidth: CGFloat { ceil(label.fittingSize.width) + 2 * SuggestionRow.padding }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        CATransaction.commit()
        let h = label.fittingSize.height
        label.frame = NSRect(
            x: SuggestionRow.padding, y: ((bounds.height - h) / 2).rounded(), width: bounds.width - 2 * SuggestionRow.padding, height: h)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    func setSelected(_ on: Bool, animated: Bool = true) {
        effectiveAppearance.performAsCurrentDrawingAppearance { fill.backgroundColor = NSColor.controlAccentColor.cgColor }
        CATransaction.begin()
        if animated { CATransaction.setAnimationDuration(on ? 0.1 : 0.18) } else { CATransaction.setDisableActions(true) }
        fill.opacity = on ? 1 : 0
        CATransaction.commit()
        label.textColor = on ? .white : .labelColor
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
    /// Việc chính của bảng ("Dùng câu này"): tô đặc màu nhấn, biểu tượng trắng.
    var solid = false { didSet { refresh(selected: false) } }
    private let tip: String
    static let size = NSSize(width: 30, height: 24)

    init(symbol: String, tip: String, action: @escaping () -> Void) {
        image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage())
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        self.action = action
        self.tip = tip
        super.init(frame: NSRect(origin: .zero, size: IconButton.size))
        wantsLayer = true
        fill.cornerRadius = 5
        layer?.addSublayer(fill)
        addSubview(image)
        // Không dùng `toolTip` của AppKit: nó chỉ hiện khi ứng dụng đang ở trước, mà VNKey không bao giờ ở trước.
        // Chú thích do `PanelTip` hiện (xem `mouseEntered`).
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
            let color: NSColor =
                solid
                ? NSColor.controlAccentColor.withAlphaComponent(selected ? 1 : 0.82)
                : active ? NSColor.controlAccentColor.withAlphaComponent(selected ? 0.28 : 0.18) : NSColor.labelColor.withAlphaComponent(selected ? 0.1 : 0)
            fill.backgroundColor = color.cgColor
        }
        image.contentTintColor = solid ? .white : active ? .controlAccentColor : selected ? .labelColor : .secondaryLabelColor
    }

    func setSelected(_ on: Bool, animated: Bool = true) {
        CATransaction.begin()
        if animated { CATransaction.setAnimationDuration(on ? 0.1 : 0.18) } else { CATransaction.setDisableActions(true) }
        refresh(selected: on)
        CATransaction.commit()
    }

    func fire() { action() }

    override func mouseEntered(with event: NSEvent) {
        onHover()
        PanelTip.shared.schedule(tip, for: self)
    }
    override func mouseExited(with event: NSEvent) {
        setSelected(false)
        PanelTip.shared.hide()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { PanelTip.shared.hide() }  // bảng vẽ lại: nút cũ bị gỡ, chú thích của nó phải đi theo
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { PanelTip.shared.hide() }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

/// Nền của chú thích: màu đặc, bo góc nhỏ.
private final class TipBackground: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor(white: 0.2, alpha: 1) : NSColor(white: 0.97, alpha: 1)).cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5
        layer?.borderColor = (dark ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 0, alpha: 0.14)).cgColor
    }
}

/// Chú thích cho nút chỉ có biểu tượng: một nhãn nhỏ hiện ngay dưới nút sau khi chuột dừng trên nó. Tự làm vì chú
/// thích của AppKit (`toolTip`) không hiện trong cửa sổ của ứng dụng không ở trước. Không nhận chuột, không lấy tiêu điểm.
private final class PanelTip {
    static let shared = PanelTip()
    private static let delay = 0.45
    private let panel: NSPanel
    private let back = TipBackground(frame: .zero)
    private let label = NSTextField(labelWithString: "")
    private var ticket = 0

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        back.wantsLayer = true
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        back.addSubview(label)
        panel.contentView = back
    }

    /// Hẹn hiện chú thích cho `view`; chuột rời đi (hoặc nút bị gỡ) trước hạn thì thôi.
    func schedule(_ text: String, for view: NSView) {
        ticket += 1
        let mine = ticket
        DispatchQueue.main.asyncAfter(deadline: .now() + PanelTip.delay) { [weak self, weak view] in
            guard let self, mine == self.ticket, let view, let window = view.window, window.isVisible else { return }
            self.show(text, below: window.convertToScreen(view.convert(view.bounds, to: nil)))
        }
    }

    private func show(_ text: String, below button: NSRect) {
        label.stringValue = text
        let size = label.fittingSize
        let width = ceil(size.width) + 20, height = ceil(size.height) + 12
        var origin = NSPoint(x: (button.midX - width / 2).rounded(), y: button.minY - height - 5)
        if let v = (NSScreen.screens.first { $0.frame.intersects(button) } ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, v.minX + 2), v.maxX - width - 2)
            if origin.y < v.minY + 2 { origin.y = button.maxY + 5 }  // sát đáy màn hình: hiện phía trên nút
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: false)
        label.frame = NSRect(x: 10, y: 6, width: ceil(size.width), height: ceil(size.height))
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        panel.invalidateShadow()
        Motion.present(panel, duration: Motion.quick)
    }

    func hide() {
        ticket += 1
        if panel.isVisible { panel.orderOut(nil) }
    }
}

/// Nền của các bảng nổi (đề nghị, AI, nút ✦): một màu đặc, sáng (trắng ở giao diện sáng), bo góc. Không dùng nền mờ:
/// đã thử `NSVisualEffectView` và kính `NSGlassEffectView` 2026-11-26, người dùng thấy bảng khó nhìn nên bỏ.
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

    override func orderOut(_ sender: Any?) {
        PanelTip.shared.hide()
        super.orderOut(sender)
    }

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
        let picks = issue.suggestions.map { s in SuggestionRow(title: s) { [weak self] in self?.onPick(s) } }
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
            let h = SuggestionRow.height
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
/// (biểu tượng), nút đóng. Dưới: tên việc và hai nút phạm vi (câu / đoạn), kết quả, rồi hàng chân: nút thử lại bên
/// trái, nút "Dùng" (biểu tượng ✓ tô đặc) bên phải (người dùng yêu cầu 2026-11-26). Bảng được GHIM: không tự đóng khi
/// chuột rời đi.
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
        var use: IconButton?
        let body: NSTextField
        switch state {
        case .ready(let fixed):
            let label = NSTextField(wrappingLabelWithString: "")
            label.attributedStringValue = marked(fixed)
            label.isSelectable = false
            body = label
            let button = IconButton(symbol: "checkmark", tip: paragraph ? L("Dùng đoạn này (↩)", "Use this paragraph (↩)") : L("Dùng câu này (↩)", "Use this sentence (↩)")) { [weak self] in
                self?.onUse(fixed)
            }
            button.solid = true
            use = button
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
        // Hàng chân: thử lại bên trái, "Dùng" bên phải.
        if use != nil || canRefresh {
            if canRefresh {
                again.frame = NSRect(origin: NSPoint(x: inset, y: y), size: IconButton.size)
                back.addSubview(again)
            }
            if let use {
                let useWidth: CGFloat = 44
                use.frame = NSRect(x: width - inset - useWidth, y: y, width: useWidth, height: IconButton.size.height)
                back.addSubview(use)
            }
            y += IconButton.size.height + 4
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
        y += IconButton.size.height + inset

        var items: [PanelItem] = []
        if let use { items.append(use) }
        if canRefresh { items.append(again) }
        place(back, width: width, height: y, items: items, animate: animate)
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
        PanelTip.shared.hide()
        if panel.isVisible { panel.orderOut(nil) }
    }
}
