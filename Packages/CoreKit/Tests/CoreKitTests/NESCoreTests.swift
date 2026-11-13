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
    /// Each new mapper's state survives a save/load byte for byte (latches, $6000 window, counter).
    @Test(arguments: ["mmc2_probe.nes", "mmc4_probe.nes", "colordreams_probe.nes", "gxrom_probe.nes", "fme7_probe.nes"])
    func newMapperStatesAreDeterministic(_ name: String) throws {
        let nes = try NESSystem(rom: try testROM(name), battery: nil)
        for _ in 0..<3 { nes.runFrame(input: []) }
        let start = nes.saveState()
        for _ in 0..<10 { nes.runFrame(input: []) }
        let after = nes.saveState()
        try nes.loadState(start)
        for _ in 0..<10 { nes.runFrame(input: []) }
        #expect(nes.saveState() == after)
    }

    /// The FME-7 counter: IRQ exactly as it wraps past zero, and only when enabled.
    @Test func fme7CounterWraps() throws {
        let nes = try NESSystem(rom: try testROM("fme7_probe.nes"), battery: nil)
        let m = try #require(nes.mapper as? FME7)
        m.write(0x8000, 0x0E, cycle: 0); m.write(0xA000, 2, cycle: 0)
        m.write(0x8000, 0x0F, cycle: 0); m.write(0xA000, 0, cycle: 0)
        m.write(0x8000, 0x0D, cycle: 0); m.write(0xA000, 0x81, cycle: 0)
        m.cpuCycle(); m.cpuCycle()
        #expect(!m.irqAsserted)          // 2 -> 1 -> 0
        m.cpuCycle()
        #expect(m.irqAsserted)           // 0 -> $FFFF
        m.write(0x8000, 0x0D, cycle: 0); m.write(0xA000, 0x80, cycle: 0)
        #expect(!m.irqAsserted)          // acknowledged; counting without IRQ
        for _ in 0..<0x10000 { m.cpuCycle() }
        #expect(!m.irqAsserted)
    }

    @Test(arguments: ["mmc1_probe.nes", "uxrom_probe.nes", "cnrom_probe.nes", "mmc3_probe.nes",
                      "mmc2_probe.nes", "mmc4_probe.nes", "colordreams_probe.nes", "gxrom_probe.nes", "fme7_probe.nes"])
    func mapperProbePasses(_ name: String) throws {
        let nes = try NESSystem(rom: try testROM(name), battery: nil)
        for _ in 0..<40 { nes.runFrame(input: []) }
        #expect(nes.debugPeek(0x6001) == 0xDE, "\(name) never started")
        let result = nes.debugPeek(0x6000)
        #expect(result == 0, "\(name) failed test \(result)")
    }
}

/// The second controller on $4017, read through the CPU-visible bus path (`read`/`write` tick the
/// machine like real accesses).
@Suite struct NESTwoPlayerTests {
    /// Strobes $4016, then reads `port` eight times; returns bit 0 of each read.
    private func shiftOut(_ nes: NESSystem, port: UInt16) -> [UInt8] {
        nes.write(0x4016, 1)
        nes.write(0x4016, 0)
        return (0..<8).map { _ in nes.read(port) & 1 }
    }

    private func bits(_ byte: UInt8) -> [UInt8] { (0..<8).map { (byte >> $0) & 1 } }

    @Test func reportsTwoPlayers() throws {
        let nes = try NESSystem(rom: try testROM("demo.nes"), battery: nil)
        #expect(nes.maxPlayers == 2)
        #expect(nes.stateVersion == 2)
    }

    @Test func player2BitsArriveInOrderAndDontLeak() throws {
        let nes = try NESSystem(rom: try testROM("demo.nes"), battery: nil)
        nes.runFrame(inputs: [[.a, .up], [.b, .start, .right]])
        #expect(nes.padState == NESSystem.padByte([.a, .up]))
        #expect(nes.pad2State == NESSystem.padByte([.b, .start, .right]))
        // Order A, B, Select, Start, Up, Down, Left, Right.
        #expect(shiftOut(nes, port: 0x4017) == [0, 1, 0, 1, 0, 0, 0, 1])
        #expect(shiftOut(nes, port: 0x4016) == [1, 0, 0, 0, 1, 0, 0, 0])
        // Interleaved reads: each port shifts independently.
        nes.write(0x4016, 1); nes.write(0x4016, 0)
        var p1: [UInt8] = [], p2: [UInt8] = []
        for _ in 0..<8 { p1.append(nes.read(0x4016) & 1); p2.append(nes.read(0x4017) & 1) }
        #expect(p1 == bits(NESSystem.padByte([.a, .up])))
        #expect(p2 == bits(NESSystem.padByte([.b, .start, .right])))
        // After eight reads both report 1s (official pads).
        #expect(nes.read(0x4017) & 1 == 1)
        #expect(nes.read(0x4016) & 1 == 1)
    }

    @Test func player2OnlyAndUpperBitsAreOpenBus() throws {
        let nes = try NESSystem(rom: try testROM("demo.nes"), battery: nil)
        nes.runFrame(inputs: [[], [.select, .left]])
        #expect(shiftOut(nes, port: 0x4016) == [0, 0, 0, 0, 0, 0, 0, 0])
        #expect(shiftOut(nes, port: 0x4017) == [0, 0, 1, 0, 0, 0, 1, 0])
        // Bits 1-4 are never driven; bits 5-7 come from open bus (on hardware, the operand's $40).
        nes.write(0x4016, 1); nes.write(0x4016, 0)
        nes.openBus = 0xFF
        #expect(nes.read(0x4017) & 0xFE == 0xE0)
        // While strobe is high, $4017 keeps returning the first bit (Select is bit 2, so A = 0).
        nes.write(0x4016, 1)
        #expect((0..<4).map { _ in nes.read(0x4017) & 1 } == [0, 0, 0, 0])
        nes.write(0x4016, 0)
    }

    @Test func singlePlayerCallReleasesPlayer2() throws {
        let nes = try NESSystem(rom: try testROM("demo.nes"), battery: nil)
        nes.runFrame(inputs: [[], [.a]])
        nes.runFrame(input: [.b])
        #expect(nes.pad2State == 0)
        #expect(nes.padState == NESSystem.padByte([.b]))
        nes.runFrame(inputs: [])
        #expect(nes.padState == 0 && nes.pad2State == 0)
    }

    @Test func saveStateKeepsPlayer2ShiftPosition() throws {
        let nes = try NESSystem(rom: try testROM("demo.nes"), battery: nil)
        nes.runFrame(inputs: [[], [.a, .start, .down]])
        nes.write(0x4016, 1); nes.write(0x4016, 0)
        _ = nes.read(0x4017); _ = nes.read(0x4017)        // A, B consumed
        let state = nes.saveState()
        let rest = (0..<6).map { _ in nes.read(0x4017) & 1 }
        #expect(rest == [0, 1, 0, 1, 0, 0])
        nes.runFrame(inputs: [])                         // changes pad state and shift
        try nes.loadState(state)
        #expect((0..<6).map { _ in nes.read(0x4017) & 1 } == rest)
    }
}
