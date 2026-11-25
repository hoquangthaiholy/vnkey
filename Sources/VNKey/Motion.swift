import AppKit

/// Thời lượng và đường cong chung cho mọi chuyển động của VNKey, để chúng cùng một "nhịp": nhanh, giảm tốc mềm ở
/// cuối, không nảy. Bật "Giảm chuyển động" trong Cài đặt hệ thống thì chỉ còn mờ dần, không trượt hay phóng.
enum Motion {
    /// Giảm tốc mềm (ra nhanh, dừng êm).
    static let ease = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
    static let quick: CFTimeInterval = 0.07
    static let short: CFTimeInterval = 0.14
    static let medium: CFTimeInterval = 0.22
    /// Mỗi nét gạch trượt ra trong chừng này, nét sau trễ hơn nét trước `stagger`.
    static let draw: CFTimeInterval = 0.18
    static let stagger: CFTimeInterval = 0.035

    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Cho một bảng nổi hiện ra: mờ dần kèm phóng nhẹ từ 97% (neo ở góc trên-trái, chỗ gần con trỏ). Gọi ngay sau khi
    /// cửa sổ đã được đưa ra trước.
    static func present(_ window: NSWindow, duration: CFTimeInterval = short) {
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = ease
            window.animator().alphaValue = 1
        }
        guard !reduced, let view = window.contentView else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        // Lớp nền của NSView neo ở góc dưới-trái: phóng quanh góc trên-trái = phóng rồi đẩy lên phần hụt.
        let s: CGFloat = 0.97
        let from = CATransform3DScale(CATransform3DMakeTranslation(0, view.bounds.height * (1 - s), 0), s, s, 1)
        let a = CABasicAnimation(keyPath: "transform")
        a.fromValue = from
        a.toValue = CATransform3DIdentity
        a.duration = duration
        a.timingFunction = ease
        layer.add(a, forKey: "present")
    }
}
