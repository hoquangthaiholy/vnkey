import AppKit
import VNKeyCore

/// Cửa sổ "Có gì mới": nhật ký thay đổi đóng gói kèm app (CHANGELOG.md), và ghi chú của bản mới đang chờ
/// (lấy từ GitHub) nếu có. Chỉ để đọc.
final class ChangelogWindow: NSObject {
    static let shared = ChangelogWindow()
    private var window: NSWindow?
    private let textView = NSTextView()

    func show() {
        if window == nil { build() }
        textView.textStorage?.setAttributedString(content())
        textView.scrollToBeginningOfDocument(nil)
        window?.title = L("Có gì mới trong VNKey", "What’s New in VNKey")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 420, height: 300)
        let scroll = NSScrollView(frame: w.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        textView.frame = scroll.bounds
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        w.contentView?.addSubview(scroll)
        w.center()
        window = w
    }

    private func content() -> NSAttributedString {
        let out = NSMutableAttributedString()
        // Bản mới đang chờ (nếu có) đứng đầu.
        if let r = Updater.shared.available, !r.notes.isEmpty {
            out.append(heading(L("Bản mới \(r.version) (chưa cài)", "New version \(r.version) (not installed)")))
            out.append(Markdown.render(r.notes))
        }
        let bundled = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let sections = Changelog.sections(from: bundled ?? "")
        for s in sections {
            let current = s.version == AppInfo.version ? L("  ·  bản đang dùng", "  ·  installed") : ""
            out.append(heading("\(s.version)\(s.date.isEmpty ? "" : "  —  \(s.date)")\(current)"))
            out.append(Markdown.render(s.body))
        }
        if sections.isEmpty && out.length == 0 {
            out.append(Markdown.render(L("Bản dựng này không kèm nhật ký thay đổi.", "This build has no bundled release notes.")))
        }
        return out
    }

    private func heading(_ text: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = 14
        p.paragraphSpacing = 6
        return NSAttributedString(
            string: text + "\n",
            attributes: [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: p])
    }
}

/// Dựng Markdown đơn giản (đủ cho CHANGELOG): tiêu đề `###`, gạch đầu dòng `-`, **đậm**, `mã`.
enum Markdown {
    static func render(_ text: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 13)
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            let p = NSMutableParagraphStyle()
            p.paragraphSpacing = 4
            p.lineSpacing = 2
            var font = body
            if line.hasPrefix("### ") || line.hasPrefix("## ") || line.hasPrefix("# ") {
                line = String(line.drop(while: { $0 == "#" || $0 == " " }))
                font = .systemFont(ofSize: 13, weight: .semibold)
                p.paragraphSpacingBefore = 8
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "•\t" + line.dropFirst(2)
                p.headIndent = 16
                p.tabStops = [NSTextTab(textAlignment: .left, location: 16)]
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            out.append(inline(line, font: font, paragraph: p))
            out.append(NSAttributedString(string: "\n"))
        }
        return out
    }

    /// **đậm** và `mã` trong một dòng; mọi thứ khác giữ nguyên văn.
    private static func inline(_ line: String, font: NSFont, paragraph: NSParagraphStyle) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        var rest = Substring(line)
        while !rest.isEmpty {
            if rest.hasPrefix("**"), let end = rest.dropFirst(2).range(of: "**") {
                var a = base
                a[.font] = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
                out.append(NSAttributedString(string: String(rest.dropFirst(2)[..<end.lowerBound]), attributes: a))
                rest = rest[end.upperBound...]
            } else if rest.hasPrefix("`"), let end = rest.dropFirst().firstIndex(of: "`") {
                var a = base
                a[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
                out.append(NSAttributedString(string: String(rest.dropFirst()[..<end]), attributes: a))
                rest = rest[rest.index(after: end)...]
            } else {
                let next = rest.dropFirst().firstIndex(where: { $0 == "*" || $0 == "`" }) ?? rest.endIndex
                out.append(NSAttributedString(string: String(rest[..<next]), attributes: base))
                rest = rest[next...]
            }
        }
        return out
    }
}
