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
        .executableTarget(name: "VNKey", dependencies: ["VNEngine"]),
        .testTarget(name: "VNEngineTests", dependencies: ["VNEngine"]),
    ]
)
