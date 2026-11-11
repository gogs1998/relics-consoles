import CoreKit
import Foundation
@testable import AresCore
import Testing

/// Tests for the SNES and Mega Drive cores (vendored ares), using only our own ROMs
/// (Tools/build_ares_roms.py). Serialized: ares allows one live SNES/Mega Drive core per process.
@Suite(.serialized) struct AresCoreTests {
    private func snes(battery: Data? = nil) throws -> SNESSystem {
        try SNESSystem(rom: try testROM("ares_snes_demo.sfc"), battery: battery)
    }

    private func md(battery: Data? = nil) throws -> MDSystem {
        try MDSystem(rom: try testROM("ares_md_demo.md"), battery: battery)
    }

    private func centre(_ core: some EmulatorCore) -> UInt32 {
        let s = core.videoSize
        return core.framebuffer[(s.height / 2) * s.width + s.width / 2]
    }

    private func isBlue(_ c: UInt32) -> Bool { c & 0xFF > 0xA0 && (c >> 16) & 0xFF < 0x40 }
    private func isRed(_ c: UInt32) -> Bool { (c >> 16) & 0xFF > 0xA0 && c & 0xFF < 0x40 }

    // MARK: detection

    @Test func detectsSystems() throws {
        let sfc = try testROM("ares_snes_demo.sfc")
        let gen = try testROM("ares_md_demo.md")
        #expect(CoreFactory.detect(rom: sfc, fileExtension: "sfc") == .snes)
        #expect(CoreFactory.detect(rom: sfc, fileExtension: "") == .snes)
        #expect(CoreFactory.detect(rom: Data(count: 512) + sfc, fileExtension: "smc") == .snes)  // copier header
        #expect(CoreFactory.detect(rom: gen, fileExtension: "bin") == .md)
        #expect(CoreFactory.detect(rom: gen, fileExtension: "") == .md)
        #expect(CoreFactory.detect(rom: Data(count: 0x2000), fileExtension: "bin") == nil)  // .bin needs "SEGA"
        #expect(CoreFactory.detect(rom: try testROM("gba_demo.gba"), fileExtension: "gba") == .gba)
        #expect(CoreFactory.detect(rom: try testROM("demo.nes"), fileExtension: "nes") == .nes)
    }

    // MARK: SNES

    @Test func snesRendersAndReactsToInput() throws {
        let s = try snes()
        #expect(s.system == .snes)
        for _ in 0..<30 { s.runFrame(input: []) }
        #expect(s.videoSize == VideoSize(width: 256, height: 224), "\(s.videoSize)")
        #expect(abs(s.pixelAspect - 8.0 / 7.0) < 0.001)
        #expect(abs(s.frameRate - 60.1) < 0.2, "\(s.frameRate)")
        let idle = centre(s)
        #expect(isBlue(idle), "\(String(idle, radix: 16))")
        #expect(s.framebuffer.allSatisfy { $0 >> 24 == 0xFF })
        for _ in 0..<3 { s.runFrame(input: [.b]) }
        let held = centre(s)
        #expect(isRed(held), "\(String(held, radix: 16))")
        for _ in 0..<3 { s.runFrame(input: []) }
        #expect(centre(s) == idle)
        for _ in 0..<3 { s.runFrame(input: [.r]) }   // R reaches the game ($4218)
        #expect(isRed(centre(s)), "\(String(centre(s), radix: 16))")
        dump(s, "ares_snes_demo")
    }

    @Test func snesAudioIsNotSilent() throws {
        let s = try snes()
        for _ in 0..<30 { s.runFrame(input: []) }
        s.discardAudio()
        var samples: [Float] = []
        for _ in 0..<60 { s.runFrame(input: []); samples += s.drainAudioSamples() }
        #expect(abs(samples.count - 47_920) < 1_000, "\(samples.count) samples for 60 frames")
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.05, "peak \(peak)")
        #expect(peak <= 1)
    }

    @Test func snesSaveStateRoundTrip() throws {
        let s = try snes()
        for _ in 0..<20 { s.runFrame(input: []) }
        let state = s.saveState()
        #expect(!state.isEmpty)
        for _ in 0..<5 { s.runFrame(input: [.a]) }
        #expect(isRed(centre(s)))
        try s.loadState(state)
        s.runFrame(input: [])
        #expect(isBlue(centre(s)))
        let again = s.saveState()
        #expect(again.count == state.count)
        #expect(throws: CoreError.self) { try s.loadState(Data([1, 2, 3])) }
        #expect(s.batteryRAM == nil)   // the demo cartridge has no save RAM
    }

    @Test func snesSpeed() throws {
        let s = try snes()
        let frames = 300
        let start = Date()
        for f in 0..<frames { s.runFrame(input: f % 20 < 10 ? [] : [.b]); s.discardAudio() }
        let fps = Double(frames) / Date().timeIntervalSince(start)
        print("SNES: \(Int(fps)) fps")
        #expect(fps > 60)
    }

    /// Every SNES button reaches the game (the demo turns red while any button is held).
    @Test func snesEveryButtonReachesGame() throws {
        let s = try snes()
        for _ in 0..<30 { s.runFrame(input: []) }
        let all: [InputState] = [.a, .b, .x, .y, .l, .r, .start, .select, .up, .down, .left, .right]
        for b in all {
            for _ in 0..<3 { s.runFrame(input: b) }
            #expect(isRed(centre(s)), "button \(b.rawValue)")
            for _ in 0..<3 { s.runFrame(input: []) }
            #expect(isBlue(centre(s)))
        }
    }

    // MARK: Mega Drive

    @Test func mdRendersAndReactsToInput() throws {
        let m = try md()
        #expect(m.system == .md)
        for _ in 0..<30 { m.runFrame(input: []) }
        #expect(m.videoSize == VideoSize(width: 320, height: 224), "\(m.videoSize)")
        #expect(abs(m.frameRate - 59.92) < 0.2, "\(m.frameRate)")
        let idle = centre(m)
        #expect(isBlue(idle), "\(String(idle, radix: 16))")
        for _ in 0..<3 { m.runFrame(input: [.b]) }    // InputState.b -> pad B
        let held = centre(m)
        #expect(isRed(held), "\(String(held, radix: 16))")
        for _ in 0..<3 { m.runFrame(input: [.a]) }    // InputState.a -> pad C: not B, stays blue
        #expect(centre(m) == idle)
        dump(m, "ares_md_demo")
    }

    @Test func mdAudioIsNotSilent() throws {
        let m = try md()
        for _ in 0..<30 { m.runFrame(input: []) }
        m.discardAudio()
        var samples: [Float] = []
        for _ in 0..<60 { m.runFrame(input: []); samples += m.drainAudioSamples() }
        #expect(abs(samples.count - 48_060) < 1_000, "\(samples.count) samples for 60 frames")
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.05, "peak \(peak)")
        #expect(peak <= 1)
    }

    @Test func mdSaveStateRoundTrip() throws {
        let m = try md()
        for _ in 0..<20 { m.runFrame(input: []) }
        let state = m.saveState()
        #expect(!state.isEmpty)
        for _ in 0..<5 { m.runFrame(input: [.b]) }
        #expect(isRed(centre(m)))
        try m.loadState(state)
        m.runFrame(input: [])
        #expect(isBlue(centre(m)))
        #expect(throws: CoreError.self) { try m.loadState(Data([1, 2, 3])) }
    }

    @Test func mdBatteryRoundTrip() throws {
        var battery: Data
        do {
            let m = try md()
            for _ in 0..<5 { m.runFrame(input: []) }
            battery = try #require(m.batteryRAM)
        }
        #expect(battery.count == 0x2000)
        #expect(battery[0] == 0x42)
        #expect(battery[1] == 1)
        let m = try md(battery: battery)
        for _ in 0..<5 { m.runFrame(input: []) }
        battery = try #require(m.batteryRAM)
        #expect(battery[1] == 2)
    }

    @Test func mdSpeed() throws {
        let m = try md()
        let frames = 300
        let start = Date()
        for f in 0..<frames { m.runFrame(input: f % 20 < 10 ? [] : [.b]); m.discardAudio() }
        let fps = Double(frames) / Date().timeIntervalSince(start)
        print("Mega Drive: \(Int(fps)) fps")
        #expect(fps > 60)
    }

    // MARK: lifecycle

    @Test func oneCoreAtATime() throws {
        let s = try snes()
        _ = withExtendedLifetime(s) {
            #expect(throws: AresError.busy) { _ = try md() }
        }
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { _ = try SNESSystem(rom: Data(count: 100), battery: nil) }
        #expect(throws: (any Error).self) { _ = try MDSystem(rom: Data(count: 100), battery: nil) }
    }

    private func dump(_ core: some EmulatorCore, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DUMP_DIR"] else { return }
        writePNG(core.framebuffer, width: core.videoSize.width, height: core.videoSize.height,
                 to: "\(dir)/\(name).png")
    }
}
