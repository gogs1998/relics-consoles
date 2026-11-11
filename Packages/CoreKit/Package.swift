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

// ares (ISC), SNES and Mega Drive cores, vendored unmodified in Sources/ARES/ares (see
// ThirdParty/ares/README.md). Only our own build units (Sources/ARES/glue/units, glue/src) are
// compiled; they #include the upstream files. glue/shim comes first on the include path and
// replaces three generated/JIT headers (sljit.h, nall's recompiler, the resource header).
// No sljit, no recompiler, no executable memory (see glue/shim/ares_prelude.h).
let aresPaths: [String] = ["glue/shim", "glue/include", "ares/ares", "ares/nall", "ares", "ares/thirdparty"]
let aresCXX: [CXXSetting] = aresPaths.map { .headerSearchPath($0) } + [
    .define("PROFILE_PERFORMANCE"),
    .define("CORE_SFC"),
    .define("CORE_MD"),
    .define("BUILD_RELEASE"),
    .define("NDEBUG"),
    // Optimised even in Debug (like the other cores); upstream's own warnings are not ours to fix.
    .unsafeFlags(["-O2", "-w", "-fno-strict-aliasing"]),
]
let aresC: [CSetting] = [
    .define("LIBCO_MP"),  // libco's active-context pointer is thread-local
    .unsafeFlags(["-O2", "-w"]),
]

let package = Package(
    name: "CoreKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit", "NESCore", "GBCore", "GBACore"]),
        // Separate product so the app opts in when it wires the new systems up.
        .library(name: "AresCore", targets: ["AresCore"]),
    ],
    targets: [
        .target(name: "CoreKit", swiftSettings: fast),
        .target(name: "NESCore", dependencies: ["CoreKit"], swiftSettings: fast),
        .target(name: "GBCore", dependencies: ["CoreKit"], swiftSettings: fast),
        .target(name: "MGBA", publicHeadersPath: "glue/include", cSettings: mgbaC),
        .target(name: "GBACore", dependencies: ["CoreKit", "MGBA"], swiftSettings: fast),
        .target(name: "ARES", sources: ["glue/units", "glue/src"], publicHeadersPath: "glue/include",
                cSettings: aresC, cxxSettings: aresCXX),
        .target(name: "AresCore", dependencies: ["CoreKit", "ARES"], swiftSettings: fast),
        .testTarget(name: "CoreKitTests", dependencies: ["CoreKit", "NESCore", "GBCore", "GBACore", "AresCore"]),
    ],
    cxxLanguageStandard: .cxx20
)
