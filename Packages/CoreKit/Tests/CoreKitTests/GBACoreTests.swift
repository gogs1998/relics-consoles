import CoreKit
import Foundation
@testable import GBACore
import Testing

/// Tests for the GBA core (vendored mGBA), using only our own ROM (Tools/build_gba_roms.py).
@Suite struct GBACoreTests {
    private func demo(battery: Data? = nil) throws -> GBASystem {
        try GBASystem(rom: try testROM("gba_demo.gba"), battery: battery)
    }

    /// Pixel in the middle of the demo's key-driven square.
    private func centre(_ gba: GBASystem) -> UInt32 { gba.framebuffer[80 * 240 + 120] }

    @Test func loadsAndRendersGradient() throws {
        let gba = try demo()
        #expect(gba.system == .gba)
        #expect(gba.videoSize == VideoSize(width: 240, height: 160))
        for _ in 0..<30 { gba.runFrame(input: []) }
        let colours = Set(gba.framebuffer)
        #expect(colours.count >= 2, "only \(colours.count) colour(s)")
        #expect(colours.count > 100)                       // the gradient
        #expect(gba.framebuffer.allSatisfy { $0 >> 24 == 0xFF })  // opaque
        // red = x / 8, green = y / 8 (BGR555 -> 0xAARRGGBB, mGBA expands 5 to 8 bits)
        #expect(gba.framebuffer[0] == 0xFF00_0000)
        let corner = gba.framebuffer[159 * 240 + 239]
        #expect((corner >> 16) & 0xFF > 0xE0)              // red
        #expect((corner >> 8) & 0xFF > 0x90)               // green
        #expect(corner & 0xFF == 0)                        // blue
        #expect(centre(gba) == 0xFFFF_FFFF)                // white square, no key held
        dump(gba, "gba_demo")
    }

    @Test func keysChangePicture() throws {
        let gba = try demo()
        for _ in 0..<30 { gba.runFrame(input: []) }
        #expect(centre(gba) == 0xFFFF_FFFF)
        for _ in 0..<3 { gba.runFrame(input: [.a]) }
        #expect(centre(gba) == 0xFFFF_0000)                // red
        for _ in 0..<3 { gba.runFrame(input: [.b]) }
        #expect(centre(gba) == 0xFF00_FF00)                // green
        for _ in 0..<3 { gba.runFrame(input: [.l]) }
        #expect(centre(gba) == 0xFF00_00FF)                // blue: L reaches the game
        for _ in 0..<3 { gba.runFrame(input: []) }
        #expect(centre(gba) == 0xFFFF_FFFF)
    }

    @Test func audioIsNotSilent() throws {
        let gba = try demo()
        for _ in 0..<30 { gba.runFrame(input: []) }   // undrained: the core drops stale output
        _ = gba.drainAudioSamples()
        gba.runFrame(input: [])
        #expect(gba.drainAudioSamples().count < 1_000)  // no backlog afterwards
        var samples: [Float] = []
        for _ in 0..<60 { gba.runFrame(input: []); samples += gba.drainAudioSamples() }
        // ~48000 samples a second at 59.73 frames a second
        #expect(abs(samples.count - 48_222) < 1_000, "\(samples.count) samples for 60 frames")
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.05, "peak \(peak)")
        #expect(peak <= 1)
        // a square tone: lots of zero crossings around its mean, about 440 a second
        let mean = samples.reduce(0, +) / Float(samples.count)
        var crossings = 0
        for i in 1..<samples.count where (samples[i - 1] - mean) * (samples[i] - mean) < 0 { crossings += 1 }
        let seconds = Double(samples.count) / 48_000
        let hz = Double(crossings) / 2 / seconds
        #expect(abs(hz - 440) < 40, "tone \(hz) Hz")
        // R raises it an octave
        _ = gba.drainAudioSamples()
        var highAll: [Float] = []
        for _ in 0..<30 { gba.runFrame(input: [.r]); highAll += gba.drainAudioSamples() }
        let high = highAll.dropFirst(2_000)
        let hMean = high.reduce(0, +) / Float(high.count)
        var hCross = 0
        var prev = high.first!
        for s in high.dropFirst() { if (prev - hMean) * (s - hMean) < 0 { hCross += 1 }; prev = s }
        let hHz = Double(hCross) / 2 / (Double(high.count) / 48_000)
        #expect(abs(hHz - 880) < 80, "high tone \(hHz) Hz")
        // discard empties the buffer
        gba.runFrame(input: [])
        gba.discardAudio()
        #expect(gba.drainAudioSamples().isEmpty)
        // drainAudio feeds the ring
        let ring = AudioRing()
        gba.runFrame(input: [])
        gba.drainAudio(into: ring)
        #expect(ring.fill > 700)
    }

    @Test func saveStateRoundTripIsDeterministic() throws {
        let gba = try demo()
        for _ in 0..<40 { gba.runFrame(input: []) }
        let state = gba.saveState()
        #expect(!state.isEmpty)
        let script: [InputState] = (0..<60).map { $0 % 20 < 7 ? [.a] : ($0 % 20 < 12 ? [.b, .r] : []) }
        var first: [[UInt32]] = []
        for i in script { gba.runFrame(input: i); first.append(Array(gba.framebuffer)) }
        try gba.loadState(state)
        var second: [[UInt32]] = []
        for i in script { gba.runFrame(input: i); second.append(Array(gba.framebuffer)) }
        #expect(first == second)
        // replaying from the loaded state twice gives byte-identical states (the very first run can
        // differ only in mGBA's lazy timestamps for idle sound channels)
        let after = gba.saveState()
        try gba.loadState(state)
        for i in script { gba.runFrame(input: i) }
        #expect(gba.saveState() == after)
        // a fresh core accepts the state too
        let other = try demo()
        try other.loadState(state)
        for i in script { other.runFrame(input: i) }
        #expect(Array(other.framebuffer) == first.last!)
        // junk is rejected and leaves the core running
        #expect(throws: CoreError.self) { try gba.loadState(Data([1, 2, 3])) }
        #expect(throws: CoreError.self) { try gba.loadState(Data(count: state.count)) }
        gba.runFrame(input: [.a])
        #expect(centre(gba) == 0xFFFF_0000)
    }

    @Test func batterySaveRoundTrip() throws {
        let gba = try demo()
        for _ in 0..<10 { gba.runFrame(input: []) }
        let save = try #require(gba.batteryRAM)
        #expect(save.count == 32 * 1024)                    // detected as SRAM
        #expect(save[0] == 0x42)
        #expect(save[1] == 0x00)                            // 0xFF + 1: first boot
        #expect(gba.debugPeek(0x0E00_0000) == 0x42)
        let again = try demo(battery: save)
        for _ in 0..<10 { again.runFrame(input: []) }
        #expect(again.batteryRAM?[1] == 0x01)               // second boot
    }

    @Test func detectsGBA() throws {
        let rom = try testROM("gba_demo.gba")
        #expect(CoreFactory.detect(rom: rom, fileExtension: "bin") == .gba)
        #expect(CoreFactory.detect(rom: rom, fileExtension: "gba") == .gba)
        #expect(CoreFactory.detect(rom: Data(count: 64), fileExtension: "GBA") == .gba)
        // the other systems' ROMs are not mistaken for GBA
        #expect(CoreFactory.detect(rom: try testROM("gb_demo.gbc"), fileExtension: "gbc") == .gbc)
        #expect(CoreFactory.detect(rom: try testROM("demo.nes"), fileExtension: "nes") == .nes)
        #expect(SystemID.gba.displayName == "Game Boy Advance")
        #expect(SystemID.gba.fileExtensions == ["gba"])
        // a GBA core refuses a non-GBA file
        #expect(throws: CoreError.self) { try GBASystem(rom: try testROM("gb_demo.gbc"), battery: nil) }
    }

    @Test func resetRestartsTheGame() throws {
        let gba = try demo()
        for _ in 0..<30 { gba.runFrame(input: [.a]) }
        #expect(centre(gba) == 0xFFFF_0000)
        gba.reset()
        for _ in 0..<30 { gba.runFrame(input: []) }
        #expect(centre(gba) == 0xFFFF_FFFF)
    }

    @Test func speed() throws {
        let gba = try demo()
        let start = Date()
        for f in 0..<600 { gba.runFrame(input: f % 30 < 10 ? [.a] : []); gba.discardAudio() }
        let fps = 600 / Date().timeIntervalSince(start)
        print("GBA demo: \(Int(fps)) frames per second")
        #expect(fps > 120)
    }
}

private func dump(_ gba: GBASystem, _ name: String) {
    guard let dir = ProcessInfo.processInfo.environment["DUMP_DIR"] else { return }
    writePNG(gba.framebuffer, width: 240, height: 160, to: "\(dir)/\(name).png")
}
