import CoreKit
@testable import DSCore
import Foundation
import Testing

/// Tests for the DS core (vendored melonDS, interpreter, FreeBIOS + generated firmware, direct boot),
/// using only our own cartridge (Tools/build_ds_roms.py). No BIOS or firmware file exists anywhere.
@Suite struct DSCoreTests {
    private func demo(battery: Data? = nil, threaded: Bool = true) throws -> DSSystem {
        try DSSystem(rom: try testROM("ds_demo.nds"), battery: battery, threaded3D: threaded)
    }

    private static let w = 256
    /// Pixel in the middle of the top screen's key-driven square.
    private func centre(_ ds: DSSystem) -> UInt32 { ds.framebuffer[(80 + 16) * Self.w + 112 + 16] }
    /// A pixel of the touch screen (its backdrop colour).
    private func touchPixel(_ ds: DSSystem) -> UInt32 { ds.framebuffer[(192 + 100) * Self.w + 128] }

    private func r(_ c: UInt32) -> UInt32 { (c >> 16) & 0xFF }
    private func g(_ c: UInt32) -> UInt32 { (c >> 8) & 0xFF }
    private func b(_ c: UInt32) -> UInt32 { c & 0xFF }
    /// melonDS expands 5-bit colour through 6 bits, so full white is 0xFFFBFBFB.
    private func isWhite(_ c: UInt32) -> Bool { r(c) > 0xF0 && g(c) > 0xF0 && b(c) > 0xF0 }

    @Test func bootsWithoutBIOSAndRendersBothScreens() throws {
        let ds = try demo()
        #expect(ds.system == .ds)
        #expect(ds.videoSize == VideoSize(width: 256, height: 384))
        #expect(ds.screens.count == 2)
        #expect(ds.screens[0] == ScreenRegion(x: 0, y: 0, width: 256, height: 192))
        #expect(ds.touchScreen == ScreenRegion(x: 0, y: 192, width: 256, height: 192, isTouch: true))
        for _ in 0..<30 { ds.runFrame(input: []) }
        let fb = Array(ds.framebuffer)
        #expect(fb.allSatisfy { $0 >> 24 == 0xFF })                  // opaque
        let top = Set(fb[0..<(256 * 192)])
        #expect(top.count > 100, "top screen has \(top.count) colours")   // the gradient
        #expect(fb[0] == 0xFF00_0000)                                 // gradient origin: black
        let corner = fb[191 * 256 + 255]
        #expect(r(corner) > 0xE0 && g(corner) > 0xA0 && b(corner) == 0, "\(String(corner, radix: 16))")
        #expect(isWhite(centre(ds)))                            // white square, no key held
        let bottom = touchPixel(ds)
        #expect(bottom != 0xFF00_0000, "touch screen is black")       // blue ramp backdrop
        #expect(b(bottom) > 0 && r(bottom) == 0 && g(bottom) == 0, "\(String(bottom, radix: 16))")
        #expect(ds.debugPeekMainRAM(0x027F_F104) > 20)                // the ARM9 counts frames
        dump(ds, "ds_demo")
    }

    @Test func keysAndTouchChangePicture() throws {
        let ds = try demo()
        for _ in 0..<30 { ds.runFrame(input: []) }
        #expect(isWhite(centre(ds)))
        for _ in 0..<3 { ds.runFrame(input: [.a]) }
        #expect(r(centre(ds)) > 0xF0 && g(centre(ds)) == 0 && b(centre(ds)) == 0)
        for _ in 0..<3 { ds.runFrame(input: [.b]) }
        #expect(g(centre(ds)) > 0xF0 && r(centre(ds)) == 0)
        for _ in 0..<3 { ds.runFrame(input: [.l]) }
        #expect(b(centre(ds)) > 0xF0 && r(centre(ds)) == 0)
        // touch: the ARM7 sees the pen down in EXTKEYIN, the ARM9 paints the touch screen green
        ds.setTouch(TouchPoint(x: 128, y: 96))
        for _ in 0..<4 { ds.runFrame(input: []) }
        #expect(g(touchPixel(ds)) > 0xF0 && b(touchPixel(ds)) == 0, "\(String(touchPixel(ds), radix: 16))")
        #expect(ds.debugPeekMainRAM(0x027F_F100) & 0x40 == 0)
        // X and Y reach the ARM7 too (EXTKEYIN bits 0 and 1, active low)
        for _ in 0..<3 { ds.runFrame(input: [.x, .y]) }
        #expect(ds.debugPeekMainRAM(0x027F_F100) & 0x3 == 0)
        ds.setTouch(nil)
        for _ in 0..<4 { ds.runFrame(input: []) }
        #expect(g(touchPixel(ds)) == 0)
        #expect(ds.debugPeekMainRAM(0x027F_F100) & 0x43 == 0x43)
        // out-of-range points are clamped onto the screen
        ds.setTouch(TouchPoint(x: 999, y: -5))
        for _ in 0..<4 { ds.runFrame(input: []) }
        #expect(g(touchPixel(ds)) > 0xF0)
    }

    @Test func audioIsNotSilent() throws {
        let ds = try demo()
        for _ in 0..<10 { ds.runFrame(input: []) }
        _ = ds.drainAudioSamples()
        var samples: [Float] = []
        for _ in 0..<60 { ds.runFrame(input: []); samples += ds.drainAudioSamples() }
        // ~48000 samples a second at 59.83 frames a second
        #expect(abs(samples.count - 48_140) < 1_500, "\(samples.count) samples for 60 frames")
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.02, "peak \(peak)")
        #expect(peak <= 1)
        let mean = samples.reduce(0, +) / Float(samples.count)
        var crossings = 0
        for i in 1..<samples.count where (samples[i - 1] - mean) * (samples[i] - mean) < 0 { crossings += 1 }
        let hz = Double(crossings) / 2 / (Double(samples.count) / 48_000)
        #expect(abs(hz - 440) < 40, "tone \(hz) Hz")
        ds.runFrame(input: [])
        ds.discardAudio()
        #expect(ds.drainAudioSamples().isEmpty)
        let ring = AudioRing()
        ds.runFrame(input: [])
        ds.drainAudio(into: ring)
        #expect(ring.fill > 700)
    }

    @Test func saveStateRoundTripIsDeterministic() throws {
        let ds = try demo()
        for _ in 0..<40 { ds.runFrame(input: []) }
        let state = ds.saveState()
        #expect(state.count > 4_000_000)                              // main RAM alone is 4 MiB
        let script: [InputState] = (0..<60).map { $0 % 20 < 7 ? [.a] : ($0 % 20 < 12 ? [.b] : []) }
        func play(_ core: DSSystem) -> [[UInt32]] {
            script.enumerated().map { i, input in
                core.setTouch(i % 15 < 5 ? TouchPoint(x: i * 3, y: 100) : nil)
                core.runFrame(input: input)
                return Array(core.framebuffer)
            }
        }
        let first = play(ds)
        #expect(Set(first.map { $0[(192 + 100) * 256 + 128] }).count > 2)  // the frames really change
        try ds.loadState(state)
        let second = play(ds)
        #expect(first == second)
        let after = ds.saveState()
        try ds.loadState(state)
        _ = play(ds)
        #expect(ds.saveState() == after)                              // byte-identical replay
        // a fresh core accepts the state too
        let other = try demo()
        try other.loadState(state)
        #expect(play(other).last! == first.last!)
        // a state goes through our StateContainer like every other system's
        let wrapped = StateContainer(system: .ds, coreStateVersion: ds.stateVersion, romCRC: ds.romCRC,
                                     payload: state).encoded()
        let unwrapped = try StateContainer.decode(wrapped)
        #expect(unwrapped.system == .ds && unwrapped.payload == state)
        // junk is rejected and leaves the core running
        #expect(throws: CoreError.self) { try ds.loadState(Data([1, 2, 3])) }
        #expect(throws: CoreError.self) { try ds.loadState(Data(count: state.count)) }
        #expect(throws: CoreError.self) { try ds.loadState(state.prefix(state.count / 2)) }  // truncated
        ds.setTouch(nil)
        for _ in 0..<3 { ds.runFrame(input: [.a]) }
        #expect(r(centre(ds)) > 0xF0 && g(centre(ds)) == 0)
    }

    @Test func batterySaveRoundTrip() throws {
        let ds = try demo()
        for _ in 0..<10 { ds.runFrame(input: []) }
        let save = try #require(ds.batteryRAM)
        #expect(save.count == 8 * 1024)                               // unknown title: 64 kbit EEPROM
        #expect(save[0] == 0x42)
        #expect(save[1] == 0x01)                                      // first boot
        #expect(ds.debugPeekMainRAM(0x027F_F108) == 1)
        let again = try demo(battery: save)
        for _ in 0..<10 { again.runFrame(input: []) }
        #expect(again.batteryRAM?[1] == 0x02)                         // second boot
        // reset keeps the save memory and boots the cartridge again
        again.reset()
        for _ in 0..<10 { again.runFrame(input: []) }
        #expect(again.batteryRAM?[1] == 0x03)
    }

    @Test func detectsDS() throws {
        let rom = try testROM("ds_demo.nds")
        #expect(CoreFactory.detect(rom: rom, fileExtension: "nds") == .ds)
        #expect(CoreFactory.detect(rom: rom, fileExtension: "bin") == .ds)   // by header
        #expect(CoreFactory.detect(rom: Data(count: 64), fileExtension: "NDS") == .ds)
        #expect(SystemID.ds.displayName == "Nintendo DS")
        #expect(SystemID.ds.fileExtensions == ["nds"])
        // the other systems' ROMs are not mistaken for DS ones
        for (name, system) in [("gba_demo.gba", SystemID.gba), ("gb_demo.gbc", .gbc), ("demo.nes", .nes),
                               ("ares_snes_demo.sfc", .snes), ("ares_md_demo.md", .md)] {
            #expect(CoreFactory.detect(rom: try testROM(name), fileExtension: "x") == system, "\(name)")
        }
        // a DS core refuses a non-DS file; other systems' cores have one plain screen
        #expect(throws: CoreError.self) { try DSSystem(rom: try testROM("gba_demo.gba"), battery: nil) }
        var dsiOnly = rom
        dsiOnly[0x12] = 3
        #expect(throws: CoreError.self) { try DSSystem(rom: dsiOnly, battery: nil) }
    }

    /// Interpreter speed on this Mac (both CPUs busy-loop, so this is a worst case for 2D games).
    @Test func speed() throws {
        for threaded in [true, false] {
            let ds = try demo(threaded: threaded)
            let start = Date()
            for f in 0..<600 { ds.runFrame(input: f % 30 < 10 ? [.a] : []); ds.discardAudio() }
            let fps = 600 / Date().timeIntervalSince(start)
            print("DS demo (threaded 3D \(threaded)): \(Int(fps)) frames per second")
            #expect(fps > 60)
        }
    }
}

private func dump(_ ds: DSSystem, _ name: String) {
    guard let dir = ProcessInfo.processInfo.environment["DUMP_DIR"] else { return }
    writePNG(ds.framebuffer, width: 256, height: 384, to: "\(dir)/\(name).png")
}
