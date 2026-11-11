import CoreKit
import Foundation
@testable import GBCore
import Testing

/// Tests for the Game Boy core, using only our own ROMs (Tools/build_gb_roms.py).
@Suite struct GBCoreTests {
    @Test func selfTestPasses() throws {
        let gb = try GBSystem(rom: try testROM("gb_selftest.gb"), battery: nil)
        #expect(gb.system == .gb)
        for _ in 0..<60 { gb.runFrame(input: []) }
        #expect(gb.debugPeek(0xA001) == 0xDE)
        #expect(gb.debugPeek(0xA002) == 0xB0)
        #expect(gb.debugPeek(0xA003) == 0x61)
        let result = gb.debugPeek(0xA000)
        #expect(result == 0, "self test failed at test \(result), pc=\(String(gb.debugPC, radix: 16))")
        // the result is in battery RAM too
        #expect(gb.batteryRAM?.first == 0)
        dump(gb, "gb_selftest")
    }

    @Test func cgbHardwareTestPasses() throws {
        let gb = try GBSystem(rom: try testROM("gb_cgbtest.gbc"), battery: nil)
        #expect(gb.system == .gbc)
        for _ in 0..<60 { gb.runFrame(input: []) }
        #expect(gb.debugPeek(0xA001) == 0xDE)
        let result = gb.debugPeek(0xA000)
        #expect(result == 0, "CGB test failed at test \(result), pc=\(String(gb.debugPC, radix: 16))")
        dump(gb, "gb_cgbtest")
    }

    /// A ROM of `banks` 16 KB banks whose first byte is the bank number, with the given cartridge type.
    private func bankedROM(type: UInt8, banks: Int, ram: UInt8 = 0) -> Data {
        var rom = [UInt8](repeating: 0, count: banks * 0x4000)
        for bank in 0..<banks {
            rom[bank * 0x4000] = UInt8(bank & 0xFF)
            rom[bank * 0x4000 + 1] = UInt8(bank >> 8)
        }
        rom[0x147] = type
        rom[0x149] = ram
        return Data(rom)
    }

    private func bankAt4000(_ c: Cartridge) -> Int { Int(c.rom[c.hi]) | Int(c.rom[c.hi + 1]) << 8 }
    private func bankAt0000(_ c: Cartridge) -> Int { Int(c.rom[c.lo]) | Int(c.rom[c.lo + 1]) << 8 }

    @Test func mbc1Banking() throws {
        let c = try Cartridge(rom: bankedROM(type: 0x03, banks: 128, ram: 0x03))
        #expect(bankAt4000(c) == 1)
        c.writeROM(0x2000, 0x00); #expect(bankAt4000(c) == 1)           // 0 -> 1
        c.writeROM(0x2000, 0x1F); #expect(bankAt4000(c) == 0x1F)
        c.writeROM(0x2000, 0x20); #expect(bankAt4000(c) == 1)           // only 5 bits
        c.writeROM(0x4000, 0x02); #expect(bankAt4000(c) == 0x41)        // upper bits
        #expect(bankAt0000(c) == 0)
        c.writeROM(0x6000, 0x01); #expect(bankAt0000(c) == 0x40)        // mode 1 banks $0000 too
        // RAM banking in mode 1
        c.writeROM(0x0000, 0x0A)
        c.writeRAM(0xA000, 0x22)
        c.writeROM(0x4000, 0x00)
        c.writeRAM(0xA000, 0x11)
        c.writeROM(0x4000, 0x02)
        #expect(c.readRAM(0xA000) == 0x22)
        c.writeROM(0x6000, 0x00)                                        // mode 0: RAM bank 0
        #expect(c.readRAM(0xA000) == 0x11)
        c.writeROM(0x0000, 0x00)
        #expect(c.readRAM(0xA000) == 0xFF)
    }

    @Test func mbc2Banking() throws {
        let c = try Cartridge(rom: bankedROM(type: 0x06, banks: 16))
        #expect(c.ramSize == 512 && c.hasBattery)
        c.writeROM(0x2100, 0x05); #expect(bankAt4000(c) == 5)
        c.writeROM(0x2100, 0x00); #expect(bankAt4000(c) == 1)
        c.writeROM(0x0000, 0x0A)                                        // bit 8 clear: RAM enable
        c.writeRAM(0xA003, 0xAB)
        #expect(c.readRAM(0xA003) == 0xFB)                              // 4-bit cells
        #expect(c.readRAM(0xA203) == 0xFB)                              // mirrored
    }

    @Test func mbc3BankingAndRTC() throws {
        let c = try Cartridge(rom: bankedROM(type: 0x10, banks: 128, ram: 0x03))
        #expect(c.hasRTC)
        c.writeROM(0x2000, 0x7F); #expect(bankAt4000(c) == 0x7F)
        c.writeROM(0x2000, 0x00); #expect(bankAt4000(c) == 1)
        c.writeROM(0x0000, 0x0A)
        c.writeROM(0x4000, 0x03)
        c.writeRAM(0xA000, 0x33)
        c.writeROM(0x4000, 0x00)
        #expect(c.readRAM(0xA000) != 0x33)
        c.writeROM(0x4000, 0x03)
        #expect(c.readRAM(0xA000) == 0x33)
        c.writeROM(0x4000, 0x08)                                        // RTC seconds
        c.writeRAM(0xA000, 42)
        c.writeROM(0x6000, 0x00); c.writeROM(0x6000, 0x01)
        #expect(c.readRAM(0xA000) == 42)
    }

    @Test func mbc5Banking() throws {
        let c = try Cartridge(rom: bankedROM(type: 0x1B, banks: 512, ram: 0x04))
        c.writeROM(0x2000, 0x00); #expect(bankAt4000(c) == 0)
        c.writeROM(0x2000, 0xFF); #expect(bankAt4000(c) == 0xFF)
        c.writeROM(0x3000, 0x01); #expect(bankAt4000(c) == 0x1FF)       // 9-bit bank number
        c.writeROM(0x0000, 0x0A)
        c.writeROM(0x4000, 0x0F)
        c.writeRAM(0xBFFF, 0x5F)
        c.writeROM(0x4000, 0x00)
        #expect(c.readRAM(0xBFFF) != 0x5F)
        c.writeROM(0x4000, 0x0F)
        #expect(c.readRAM(0xBFFF) == 0x5F)
    }

    @Test func batteryRAMRestores() throws {
        var ram = Data(repeating: 0, count: 0x2000)
        ram[0x10] = 0x42
        let gb = try GBSystem(rom: try testROM("gb_selftest.gb"), battery: ram)
        #expect(gb.batteryRAM?[0x10] == 0x42)
    }

    @Test func demoDrawsPlaysAndResponds() throws {
        let gb = try GBSystem(rom: try testROM("gb_demo.gbc"), battery: nil)
        #expect(gb.system == .gbc)
        var maxAmp: Float = 0
        let ring = AudioRing()
        var samples = 0
        for f in 0..<240 {
            var input: InputState = []
            if f > 60 && f < 100 { input = [.right] }
            if f == 120 || f == 121 { input = [.a] }
            gb.runFrame(input: input)
            for s in gb.debugPendingAudio { maxAmp = max(maxAmp, abs(s)) }
            samples += gb.debugPendingAudio.count
            gb.drainAudio(into: ring)
            if f == 130 { dump(gb, "gb_demo_jump") }
        }
        let distinct = Set(gb.framebuffer).count
        #expect(distinct >= 4, "only \(distinct) colours on screen")
        #expect(maxAmp > 0.02, "audio peak \(maxAmp)")
        // 240 frames at ~59.7 Hz is ~4 s of audio at 48 kHz
        #expect(abs(samples - 240 * 48_000 * 70_224 / 4_194_304) < 2_000, "\(samples) samples")
        // the mascot moved right while held (starts at 72)
        #expect(gb.debugPeek(0xC101) > 100)
        // it switched to double speed
        #expect(gb.debugPeek(0xFF4D) & 0x80 != 0)
        dump(gb, "gb_demo")

        gb.runFrame(input: [.left, .b])
        gb.runFrame(input: [.left, .b])
        dump(gb, "gb_demo_status")
    }

    @Test func demoRunsOnDMG() throws {
        let gb = try GBSystem(rom: try testROM("gb_demo_dmg.gb"), battery: nil)
        #expect(gb.system == .gb)
        for f in 0..<120 { gb.runFrame(input: f > 30 && f < 50 ? [.left] : []) }
        let distinct = Set(gb.framebuffer)
        #expect(distinct.count == 4, "\(distinct.count) shades")
        #expect(gb.debugPeek(0xC101) < 72)
        dump(gb, "gb_demo_dmg")
    }

    @Test func systemDetection() throws {
        #expect(CoreFactory.detect(rom: try testROM("gb_demo.gbc"), fileExtension: "bin") == .gbc)
        #expect(CoreFactory.detect(rom: try testROM("gb_selftest.gb"), fileExtension: "bin") == .gb)
        #expect(CoreFactory.detect(rom: try testROM("gb_demo_dmg.gb"), fileExtension: "gbc") == .gb)
    }

    @Test func saveStateRoundTrip() throws {
        let gb = try GBSystem(rom: try testROM("gb_demo.gbc"), battery: nil)
        for _ in 0..<50 { gb.runFrame(input: []) }
        let state = gb.saveState()
        for f in 0..<20 { gb.runFrame(input: f == 5 ? [.a] : [.right]) }
        let hashA = framebufferHash(gb.framebuffer)
        let stateA = gb.saveState()
        try gb.loadState(state)
        for f in 0..<20 { gb.runFrame(input: f == 5 ? [.a] : [.right]) }
        #expect(framebufferHash(gb.framebuffer) == hashA)
        // the whole machine (CPU, PPU, APU, timers, memory) ends up bit-identical
        #expect(gb.saveState() == stateA)
        #expect(throws: CoreError.self) { try gb.loadState(Data([1, 2, 3])) }
        // a DMG-mode state doesn't load into a CGB-mode machine
        let dmg = try GBSystem(rom: try testROM("gb_demo_dmg.gb"), battery: nil)
        #expect(throws: CoreError.self) { try gb.loadState(dmg.saveState()) }
        // and the machine still runs after a rejected load
        gb.runFrame(input: [])
        #expect(framebufferHash(gb.framebuffer) != 0)
    }

    @Test func rejectsUnknownMapper() throws {
        var rom = [UInt8](try testROM("gb_demo_dmg.gb"))
        rom[0x147] = 0xFC
        #expect(throws: CoreError.unsupportedMapper(0xFC)) { try GBSystem(rom: Data(rom), battery: nil) }
    }

    @Test func speed() throws {
        let gb = try GBSystem(rom: try testROM("gb_demo_dmg.gb"), battery: nil)
        let start = Date()
        for _ in 0..<600 { gb.runFrame(input: []) }
        let fps = 600 / Date().timeIntervalSince(start)
        let cgb = try GBSystem(rom: try testROM("gb_demo.gbc"), battery: nil)
        let start2 = Date()
        for _ in 0..<600 { cgb.runFrame(input: []) }
        let fps2 = 600 / Date().timeIntervalSince(start2)
        // the self test ends in a busy loop: no HALT, the CPU runs every cycle
        let busy = try GBSystem(rom: try testROM("gb_selftest.gb"), battery: nil)
        let start3 = Date()
        for _ in 0..<600 { busy.runFrame(input: []) }
        let fps3 = 600 / Date().timeIntervalSince(start3)
        print("GB demo: \(Int(fps)) frames per second (DMG), \(Int(fps2)) (CGB double speed), busy CPU \(Int(fps3))")
        #expect(fps > 300)
        #expect(fps2 > 150)
        #expect(fps3 > 300)
    }

    private func dump(_ gb: GBSystem, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DUMP_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        writePNG(gb.framebuffer, width: 160, height: 144, to: "\(dir)/\(name).png")
    }
}
