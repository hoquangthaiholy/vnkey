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
// Cỡ lớn nhất là 512 px (không có 512@2x = 1024 px): VNKey là app thanh menu, logo chỉ hiện ở cỡ nhỏ, mà
// riêng ảnh 1024 px đã nặng hơn mọi cỡ khác cộng lại.
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: set.appendingPathComponent("icon_\(size)x\(size).png"))
    if size < 512 { try render(size * 2).write(to: set.appendingPathComponent("icon_\(size)x\(size)@2x.png")) }
}
try FileManager.default.createDirectory(at: root.appendingPathComponent("Resources"), withIntermediateDirectories: true)
let icns = root.appendingPathComponent("Resources/AppIcon.icns")

@discardableResult func sh(_ tool: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

guard sh("/usr/bin/iconutil", ["-c", "icns", set.path, "-o", icns.path]) == 0 else {
    print("iconutil lỗi")
    exit(1)
}

// Nén thêm (tuỳ chọn): `brew install pngquant oxipng`. iconutil tự mã hoá lại ảnh, nên nén trước khi đóng gói
// không có tác dụng; thay vào đó nén từng ảnh rồi chép thẳng vào chỗ của nó trong tệp .icns.
func find(_ name: String) -> String? {
    ["/opt/homebrew/bin/", "/usr/local/bin/"].map { $0 + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
}
let pngs = try FileManager.default.contentsOfDirectory(at: set, includingPropertiesForKeys: nil).filter { $0.pathExtension == "png" }
if let pngquant = find("pngquant") {  // giảm còn bảng 256 màu, có rung màu để dải chuyển màu không bị sọc
    for f in pngs { sh(pngquant, ["--quality", "90-100", "--speed", "1", "--strip", "--skip-if-larger", "--force", "--ext", ".png", f.path]) }
}
if let oxipng = find("oxipng") { sh(oxipng, ["-o", "max", "--strip", "all", "-q"] + pngs.map(\.path)) }
if find("pngquant") == nil && find("oxipng") == nil {
    print("Không thấy pngquant/oxipng: giữ ảnh chưa nén thêm.")
}

/// Loại phần tử trong .icns -> tệp trong iconset. (16 và 32 px được iconutil lưu dạng ARGB, để nguyên.)
let slots = [
    "ic11": "icon_16x16@2x", "ic12": "icon_32x32@2x", "ic07": "icon_128x128", "ic13": "icon_128x128@2x",
    "ic08": "icon_256x256", "ic14": "icon_256x256@2x", "ic09": "icon_512x512",
]
func be32(_ n: Int) -> Data { withUnsafeBytes(of: UInt32(n).bigEndian) { Data($0) } }
let old = try Data(contentsOf: icns)
var body = Data(), i = 8
while i + 8 <= old.count {
    let type = String(decoding: old[i..<i + 4], as: UTF8.self)
    let len = Int(old[i + 4..<i + 8].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    guard len >= 8, i + len <= old.count else { break }
    var payload = old[(i + 8)..<(i + len)]
    if let name = slots[type], let small = try? Data(contentsOf: set.appendingPathComponent(name + ".png")),
        small.count < payload.count
    {
        payload = small[...]
    }
    body += Data(type.utf8) + be32(payload.count + 8) + payload
    i += len
}
try (Data("icns".utf8) + be32(body.count + 8) + body).write(to: icns)
guard NSImage(contentsOf: icns)?.isValid == true else {
    print("Tệp .icns sau khi nén không đọc được")
    exit(1)
}
print("Đã tạo Resources/AppIcon.icns (\((try Data(contentsOf: icns)).count / 1024) KB)")
