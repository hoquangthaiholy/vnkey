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
    /// Đang ở ô nhập bảo mật (mật khẩu): macOS không cho bộ gõ thấy phím.
    static let locked = make(symbol: "lock.fill")
    /// Chưa có quyền Trợ năng: VNKey chưa làm việc được.
    static let warning = make(symbol: "exclamationmark")
    static var all: [(String, NSImage)] {
        [("vn", vn), ("en", en), ("paused", paused), ("locked", locked), ("warning", warning)]
    }

    /// Cùng ô bo góc tô đặc như V/E, nhưng khoét rỗng một ký hiệu SF Symbols thay cho chữ: trạng thái đặc biệt
    /// vẫn đồng nhất với biểu tượng thường ngày (trước đây là emoji 🔒 / ⚠︎ đặt cạnh, lệch kiểu với thanh menu).
    private static func make(symbol: String) -> NSImage {
        let size = NSSize(width: 21, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5).fill()
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            else { return true }
            let g = glyph.size
            glyph.draw(
                in: NSRect(x: rect.midX - g.width / 2, y: rect.midY - g.height / 2, width: g.width, height: g.height),
                from: .zero, operation: .destinationOut, fraction: 1)
            return true
        }
        image.isTemplate = true
        return image
    }

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
