// swift-tools-version: 6.0
import PackageDescription

// Cores are optimised even in Debug builds so the simulator plays at full speed.
let fast: [SwiftSetting] = [.unsafeFlags(["-Ounchecked"])]

let package = Package(
    name: "CoreKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit", "NESCore", "GBCore"]),
    ],
    targets: [
        .target(name: "CoreKit", swiftSettings: fast),
        .target(name: "NESCore", dependencies: ["CoreKit"], swiftSettings: fast),
        .target(name: "GBCore", dependencies: ["CoreKit"], swiftSettings: fast),
        .testTarget(name: "CoreKitTests", dependencies: ["CoreKit", "NESCore", "GBCore"]),
    ]
)
