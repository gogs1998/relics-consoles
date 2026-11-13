import Foundation
import MUPEN64

/// The hidden N64 speed test: runs our own bench ROM (`n64_rdpbench.z64`, built by Tools/build_n64_bench_rom.py)
/// through paraLLEl-RDP on MoltenVK + cxd4 and reports fps with a CPU / RSP / RDP / GPU breakdown
/// (docs/n64-rdp-spike.md). Needs a device with Vulkan (MoltenVK): in the simulator it reports that the RDP
/// didn't start. Runs on the calling thread for about a minute per mode; never while an N64 game is running
/// (mupen64plus is one machine per process: the run then fails with "n64_create failed").
public enum N64SpeedTest {
    public struct Result: Sendable {
        public let ok: Bool
        public let report: String
    }

    /// `progress` is called on the calling thread every 15 frames with a status line and the current
    /// 320 x 240 frame (0xAARRGGBB words).
    public static func run(synchronous: Bool, progress: (String, UnsafePointer<UInt32>?) -> Void) -> Result {
        guard let rom = Bundle.module.url(forResource: "n64_rdpbench", withExtension: "z64")
                .flatMap({ try? Data(contentsOf: $0) }),
              let ini = Bundle.module.url(forResource: "mupen64plus", withExtension: "ini") else {
            return Result(ok: false, report: "The speed-test files are missing from the app.\n")
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("n64-speedtest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        var buffer = [CChar](repeating: 0, count: 16384)
        let ok = withoutActuallyEscaping(progress) { progress in
            var box = progress
            return withUnsafeMutablePointer(to: &box) { ctx in
                rom.withUnsafeBytes { raw in
                    n64bench_run(raw.bindMemory(to: UInt8.self).baseAddress, rom.count, work.path,
                                 ini.deletingLastPathComponent().path, synchronous,
                                 { line, frame, ctx in
                                     guard let ctx else { return }
                                     let cb = ctx.assumingMemoryBound(to: ((String, UnsafePointer<UInt32>?) -> Void).self)
                                     cb.pointee(line.map { String(cString: $0) } ?? "", frame)
                                 },
                                 UnsafeMutableRawPointer(ctx), &buffer, buffer.count)
                }
            }
        }
        let report = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return Result(ok: ok, report: report)
    }
}
