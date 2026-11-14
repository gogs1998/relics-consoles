// swift-tools-version: 6.0
import PackageDescription

// Cores are optimised even in Debug builds so the simulator plays at full speed.
let fast: [SwiftSetting] = [.unsafeFlags(["-Ounchecked", "-enforce-exclusivity=unchecked"])]

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

// melonDS (GPL-3.0-or-later), Nintendo DS mode only, vendored unmodified in Sources/MELONDS/melonds
// (see ThirdParty/melonds/README.md). Interpreter only: JIT_ENABLED is never defined and no JIT file is
// vendored (glue/shim holds the non-JIT stand-ins for ARMJIT.h / ARMJIT_Memory.h and the generated
// version.h). No DSi, Wi-Fi networking, OpenGL or GDB stub sources; glue/src/melonds_stubs.cpp stands
// in for the DSi/SD-card classes the NDS code names but never reaches in DS mode.
// Built through glue/units instead (see there), plus the licence and template files.
let melondsExcluded = ["melonds/ARM.cpp", "melonds/NDS.cpp", "melonds/NDSCart.cpp", "melonds/LICENSE",
                       "melonds/version.h.in", "melonds/blip-buf/license.txt", "melonds/blip-buf/readme.txt",
                       "melonds/fatfs/LICENSE.txt", "melonds/tiny-AES-c/unlicense.txt"]
let melondsPaths: [String] = ["glue/shim", "glue/include", "melonds"]
let melondsCXX: [CXXSetting] = melondsPaths.map { .headerSearchPath($0) } + [
    .define("NDEBUG"),
    // Optimised even in Debug (like the other cores); upstream's own warnings are not ours to fix.
    .unsafeFlags(["-O2", "-w", "-fwrapv", "-Wno-invalid-offsetof"]),
]
let melondsC: [CSetting] = [.define("NDEBUG"), .unsafeFlags(["-O2", "-w", "-fwrapv"])]

// mupen64plus-core + mupen64plus-rsp-hle (GPL-2.0-or-later), Nintendo 64, vendored unmodified in
// Sources/MUPEN64/mupen64plus-core and Sources/MUPEN64/rsp-hle (see ThirdParty/mupen64/README.md).
// Cached interpreter only: NO_ASM, no DYNAREC/NEW_DYNAREC, no recompiler file vendored. No
// M64P_PARALLEL (the work queue runs inline), no OSD, netplay, debugger, LIRC or libpng.
// glue/shim comes first on the include path (a pthread-backed stand-in for the few SDL calls).
// glue/src holds our front end, static plugin tables and stand-ins for the files left out;
// glue/units compiles rsp-hle's plugin.c with renamed entry points.
let mupenExcluded = ["mupen64plus-core/LICENSES", "mupen64plus-core/doc", "rsp-hle/LICENSES",
                     "rsp-hle/src/plugin.c", "mupen64plus-core/src/main/main.c",
                     "mupen64plus-core/src/device/r4300/opcodes.md",
                     "mupen64plus-core/src/device/r4300/mips_instructions.def"]
let mupenC: [CSetting] = [
    .headerSearchPath("glue/shim"),
    .headerSearchPath("mupen64plus-core/src"),
    .headerSearchPath("mupen64plus-core/src/api"),
    .headerSearchPath("mupen64plus-core/subprojects"),
    .headerSearchPath("mupen64plus-core/subprojects/md5"),
    .headerSearchPath("mupen64plus-core/subprojects/xxhash"),
    .define("NO_ASM"),
    .define("NOCRYPT"),
    .define("NOUNCRYPT"),
    .define("NDEBUG"),
    // Optimised even in Debug (like the other cores); upstream's own warnings are not ours to fix.
    .unsafeFlags(["-O2", "-w", "-fno-strict-aliasing"]),
]
// paraLLEl-RDP (MIT; with Granite's Vulkan backend, volk and Vulkan-Headers) vendored unmodified in
// Sources/MUPEN64/parallel-rdp, and cxd4's RSP interpreter (CC0) vendored unmodified in Sources/MUPEN64/rsp-cxd4.
// Both are compiled only through our build units in glue/rdp (see glue/rdp/n64_rdp.h). MoltenVK (Apache-2.0) is
// linked by the app for iPhone/iPad builds (ThirdParty/moltenvk); elsewhere the RDP layer finds no Vulkan and the
// glue falls back to VI scan-out.
let parallelRdpPaths: [String] = ["parallel-rdp/parallel-rdp", "parallel-rdp/volk", "parallel-rdp/vulkan",
                                  "parallel-rdp/vulkan-headers/include", "parallel-rdp/util"]
let mupenRdpC: [CSetting] = mupenC + parallelRdpPaths.map { .headerSearchPath($0) }
let mupenRdpCXX: [CXXSetting] = (parallelRdpPaths + ["glue/include", "mupen64plus-core/src", "mupen64plus-core/src/api"])
    .map { .headerSearchPath($0) } + [
    .define("NDEBUG"),
    .unsafeFlags(["-O2", "-w"]),
]

let package = Package(
    name: "CoreKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit", "NESCore", "GBCore", "GBACore"]),
        // Separate product so the app opts in when it wires the new systems up.
        .library(name: "AresCore", targets: ["AresCore"]),
        .library(name: "DSCore", targets: ["DSCore"]),
        .library(name: "N64Core", targets: ["N64Core"]),
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
        .target(name: "MELONDS", exclude: melondsExcluded,
                sources: ["melonds", "glue/src", "glue/units"], publicHeadersPath: "glue/include",
                cSettings: melondsC, cxxSettings: melondsCXX),
        .target(name: "DSCore", dependencies: ["CoreKit", "MELONDS"], swiftSettings: fast),
        .target(name: "MUPEN64", exclude: mupenExcluded,
                sources: ["mupen64plus-core/src", "mupen64plus-core/subprojects", "rsp-hle/src", "glue/src",
                          "glue/units", "glue/rdp"],
                publicHeadersPath: "glue/include", cSettings: mupenRdpC, cxxSettings: mupenRdpCXX,
                linkerSettings: [.linkedLibrary("z")]),
        .target(name: "N64Core", dependencies: ["CoreKit", "MUPEN64"],
                resources: [.copy("Resources/mupen64plus.ini")],
                swiftSettings: fast),
        .testTarget(name: "CoreKitTests",
                    dependencies: ["CoreKit", "NESCore", "GBCore", "GBACore", "AresCore", "DSCore", "N64Core", "MUPEN64"]),
    ],
    cxxLanguageStandard: .cxx20
)
