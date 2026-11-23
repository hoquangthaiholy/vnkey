import AppKit

/// Biểu tượng trên thanh menu (ảnh template: macOS tự đổi màu theo nền sáng/tối).
/// Cả hai chế độ dùng cùng một ô bo góc tô đặc, chỉ khác chữ khoét rỗng bên trong: V hoặc E.
enum StatusIcon {
    static let vn = make("V")
    static let en = make("E")
    /// Đang tạm ngưng theo bàn phím hệ thống: cùng hình chữ V nhưng mờ hẳn (không còn nghĩa VN hay EN).
    static let paused: NSImage = {
        let image = NSImage(size: vn.size, flipped: false) { rect in
            vn.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.32)
            return true
        }
        image.isTemplate = true
        return image
    }()
    static var all: [(String, NSImage)] { [("vn", vn), ("en", en), ("paused", paused)] }

    private static func make(_ letter: Character) -> NSImage {
        let size = NSSize(width: 21, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5).fill()

            // Canh giữa theo khung bao của chính nét chữ, không theo ô chữ của font: ô chữ có phần chừa
            // cho dấu và chân chữ nên chữ hoa sẽ lệch (chữ V nhìn rõ nhất vì đỉnh nhọn ở dưới).
            let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            var chars = Array(String(letter).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: chars.count)
            guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count) else { return true }
            let glyph = NSBezierPath()
            glyph.move(to: .zero)
            glyph.append(withCGGlyph: glyphs[0], in: font)
            let b = glyph.bounds
            let move = AffineTransform(translationByX: rect.midX - b.midX, byY: rect.midY - b.midY)
            glyph.transform(using: move)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            glyph.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        return image
    }
}
