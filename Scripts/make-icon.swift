// Vẽ biểu tượng app và đóng thành Resources/AppIcon.icns.  Chạy: swift Scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // Khuôn biểu tượng macOS: ô bo góc 824pt giữa khung 1024pt.
    let box = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: box, xRadius: 185 * s, yRadius: 185 * s)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(
        starting: NSColor(srgbRed: 0.98, green: 0.36, blue: 0.27, alpha: 1),
        ending: NSColor(srgbRed: 0.78, green: 0.10, blue: 0.20, alpha: 1))!.draw(in: shape, angle: -90)

    // Chữ "ế": một chữ cái mang cả dấu mũ lẫn dấu thanh — đúng việc bộ gõ làm.
    let font = NSFont.systemFont(ofSize: 600 * s, weight: .bold)
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor(white: 0, alpha: 0.18)
    glyphShadow.shadowBlurRadius = 10 * s
    glyphShadow.shadowOffset = NSSize(width: 0, height: -6 * s)
    let text = NSAttributedString(
        string: "ế", attributes: [.font: font, .foregroundColor: NSColor.white, .shadow: glyphShadow])
    let t = text.size()
    text.draw(at: NSPoint(x: box.midX - t.width / 2, y: box.midY - t.height / 2 - 30 * s))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let set = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: set.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: set.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try FileManager.default.createDirectory(at: root.appendingPathComponent("Resources"), withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Đã tạo Resources/AppIcon.icns" : "iconutil lỗi \(p.terminationStatus)")
