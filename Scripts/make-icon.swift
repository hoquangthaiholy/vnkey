// Dựng Resources/AppIcon.icns từ Resources/AppIcon.svg.  Chạy: swift Scripts/make-icon.swift
import AppKit

guard let art = NSImage(contentsOfFile: "Resources/AppIcon.svg"), art.isValid else {
    print("Không đọc được Resources/AppIcon.svg")
    exit(1)
}

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

    // Hình vẽ lấy từ Resources/AppIcon.svg, cắt theo khuôn bo góc của macOS.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGraphicsContext.current?.imageInterpolation = .high
    art.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
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
