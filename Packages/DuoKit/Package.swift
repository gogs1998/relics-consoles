// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DuoKit",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "DuoKit", targets: ["DuoKit"])
    ],
    targets: [
        .target(name: "DuoKit"),
        .testTarget(name: "DuoKitTests", dependencies: ["DuoKit"])
    ]
)
