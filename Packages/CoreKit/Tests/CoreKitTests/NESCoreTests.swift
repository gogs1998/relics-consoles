import CoreKit
import Foundation
@testable import NESCore
import Testing

/// Our own test ROMs, assembled by Tools/build_test_roms.py into TestROMs/build/.
func testROM(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("TestROMs/build/\(name)"))
}

func framebufferHash(_ fb: UnsafeBufferPointer<UInt32>) -> UInt32 {
    var data = Data(capacity: fb.count * 4)
    for px in fb { withUnsafeBytes(of: px) { data.append(contentsOf: $0) } }
    return CRC32.checksum(data)
}

@Suite struct NESCoreTests {
    @Test func cpuSelfTestPasses() throws {
        let nes = try NESSystem(rom: try testROM("cpu_selftest.nes"), battery: nil)
        for _ in 0..<30 { nes.runFrame(input: []) }
        let result = nes.debugPeek(0x6000)
        #expect(nes.debugPeek(0x6001) == 0xDE)
        #expect(result == 0, "self test failed at test \(result), pc=\(String(nes.debugPC, radix: 16))")
    }

    @Test func demoDrawsAndPlays() throws {
        let nes = try NESSystem(rom: try testROM("demo.nes"), battery: nil)
        var maxAmp: Float = 0
        let ring = AudioRing()
        for f in 0..<180 {
            nes.runFrame(input: f > 60 && f < 90 ? [.right] : [])
            for s in nes.debugPendingAudio { maxAmp = max(maxAmp, abs(s)) }
            nes.drainAudio(into: ring)
        }
        let fb = nes.framebuffer
        let distinct = Set(fb).count
        #expect(distinct >= 8, "only \(distinct) colours on screen")
        #expect(maxAmp > 0.02, "audio peak \(maxAmp)")
        // the mascot moved right while held
        #expect(nes.debugPeek(0x20) > 60)
    }

    @Test func saveStateRoundTrip() throws {
        let nes = try NESSystem(rom: try testROM("demo.nes"), battery: nil)
        for _ in 0..<50 { nes.runFrame(input: []) }
        let state = nes.saveState()
        for _ in 0..<10 { nes.runFrame(input: [.right]) }
        let hashA = framebufferHash(nes.framebuffer)
        try nes.loadState(state)
        for _ in 0..<10 { nes.runFrame(input: [.right]) }
        #expect(framebufferHash(nes.framebuffer) == hashA)
        #expect(throws: CoreError.self) { try nes.loadState(Data([1, 2, 3])) }
    }

    /// Byte-for-byte determinism across a load, on the MMC3 probe (mapper IRQ, A12 state, APU).
    @Test func saveStateIsDeterministicOnMMC3() throws {
        let nes = try NESSystem(rom: try testROM("mmc3_probe.nes"), battery: nil)
        for _ in 0..<5 { nes.runFrame(input: []) }
        let start = nes.saveState()
        for _ in 0..<12 { nes.runFrame(input: []) }
        let first = nes.saveState()
        try nes.loadState(start)
        for _ in 0..<12 { nes.runFrame(input: []) }
        #expect(nes.saveState() == first)
    }

    @Test func speed() throws {
        let nes = try NESSystem(rom: try testROM("demo.nes"), battery: nil)
        let start = Date()
        for _ in 0..<600 { nes.runFrame(input: []) }
        let fps = 600 / Date().timeIntervalSince(start)
        print("NES demo: \(Int(fps)) frames per second")
        #expect(fps > 120)
    }
}

@Suite struct NESMapperTests {
    @Test(arguments: ["mmc1_probe.nes", "uxrom_probe.nes", "cnrom_probe.nes", "mmc3_probe.nes"])
    func mapperProbePasses(_ name: String) throws {
        let nes = try NESSystem(rom: try testROM(name), battery: nil)
        for _ in 0..<40 { nes.runFrame(input: []) }
        #expect(nes.debugPeek(0x6001) == 0xDE, "\(name) never started")
        let result = nes.debugPeek(0x6000)
        #expect(result == 0, "\(name) failed test \(result)")
    }
}
