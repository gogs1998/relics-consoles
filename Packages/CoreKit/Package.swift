// swift-tools-version: 6.0
import PackageDescription

// Cores are optimised even in Debug builds so the simulator plays at full speed.
let fast: [SwiftSetting] = [.unsafeFlags(["-Ounchecked"])]

// mGBA (MPL-2.0), vendored unmodified in Sources/MGBA/mgba (see ThirdParty/mgba/README.md).
// GBA core only: no GB core, threads, debugger, scripting, file system, zlib/png/lzma/elf or GL.
// These defines replace mGBA's CMake-generated flags.h.
let mgbaC: [CSetting] = [
    .headerSearchPath("mgba/include"),
    .headerSearchPath("mgba/src"),
    .define("M_CORE_GBA"),
    .define("DISABLE_THREADING"),
    .define("MINIMAL_CORE", to: "2"),
    .define("MGBA_STANDALONE"),
    .define("_DARWIN_C_SOURCE"),
    .define("HAVE_STRDUP"),
    .define("HAVE_STRLCPY"),
    .define("HAVE_STRNDUP"),
    .define("HAVE_VASPRINTF"),
    .define("HAVE_LOCALE"),
    .define("HAVE_SNPRINTF_L"),
    .define("HAVE_LOCALTIME_R"),
    .define("HAVE_XLOCALE"),
    .define("HAVE_STRTOF_L"),
    .define("NDEBUG"),
    // Optimised even in Debug (like the Swift cores); upstream's own warnings are not ours to fix.
    .unsafeFlags(["-O2", "-std=gnu11", "-w"]),
]

let package = Package(
    name: "CoreKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit", "NESCore", "GBCore", "GBACore"]),
    ],
    targets: [
        .target(name: "CoreKit", swiftSettings: fast),
        .target(name: "NESCore", dependencies: ["CoreKit"], swiftSettings: fast),
        .target(name: "GBCore", dependencies: ["CoreKit"], swiftSettings: fast),
        .target(name: "MGBA", publicHeadersPath: "glue/include", cSettings: mgbaC),
        .target(name: "GBACore", dependencies: ["CoreKit", "MGBA"], swiftSettings: fast),
        .testTarget(name: "CoreKitTests", dependencies: ["CoreKit", "NESCore", "GBCore", "GBACore"]),
    ]
)
