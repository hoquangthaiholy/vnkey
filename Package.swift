// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VNKey",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "VNEngine", targets: ["VNEngine"]),
        .executable(name: "VNKey", targets: ["VNKey"]),
    ],
    targets: [
        // Engine thuần Swift, không phụ thuộc AppKit: test được độc lập.
        .target(name: "VNEngine"),
        // App thanh menu: event tap + gửi phím.
        // Logic thuần của app (lập kế hoạch gửi phím, phím tắt, chế độ theo ứng dụng): test được.
        .target(name: "VNKeyCore"),
        .executableTarget(name: "VNKey", dependencies: ["VNEngine", "VNKeyCore"]),
        // Công cụ dòng lệnh: gõ lại một chuỗi phím qua engine, đo hiệu năng.
        .executableTarget(name: "vnkey-tool", dependencies: ["VNEngine"], path: "Sources/VNTool"),
        .testTarget(name: "VNEngineTests", dependencies: ["VNEngine"]),
        .testTarget(name: "VNKeyCoreTests", dependencies: ["VNKeyCore", "VNEngine"]),
    ]
)
