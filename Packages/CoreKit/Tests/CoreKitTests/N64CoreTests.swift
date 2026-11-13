import CoreKit
import Foundation
import MUPEN64
@testable import N64Core
import Testing

/// Tests for the Nintendo 64 core (vendored mupen64plus + rsp-hle, cached interpreter, HLE boot),
/// using only our own cartridge (Tools/build_n64_roms.py). No PIF ROM or IPL3 exists anywhere.
/// Serialized: mupen64plus allows one live machine per process.
@Suite(.serialized) struct N64CoreTests {
    private func demo(battery: Data? = nil) throws -> N64System {
        try N64System(rom: try testROM("n64_demo.z64"), battery: battery)
    }

    private static let w = 320
    /// Middle of the 64x64 square (at 128,88 with the stick centred; the output is 237 → 240 rows).
    private func centre(_ n: N64System) -> UInt32 { n.framebuffer[121 * Self.w + 160] }
    private func corner(_ n: N64System) -> UInt32 { n.framebuffer[10 * Self.w + 10] }
    private func r(_ c: UInt32) -> UInt32 { (c >> 16) & 0xFF }
    private func g(_ c: UInt32) -> UInt32 { (c >> 8) & 0xFF }
    private func b(_ c: UInt32) -> UInt32 { c & 0xFF }
    private func hex(_ c: UInt32) -> String { String(c, radix: 16) }

    @Test func detectsAndNormalisesByteOrders() throws {
        let z64 = try testROM("n64_demo.z64")
        #expect(CoreFactory.detect(rom: z64, fileExtension: "z64") == .n64)
        #expect(CoreFactory.detect(rom: z64, fileExtension: "") == .n64)
        var v64 = Data(z64), n64 = Data(z64)
        v64.withUnsafeMutableBytes { p in
            for i in stride(from: 0, to: p.count, by: 2) { p.swapAt(i, i + 1) }
        }
        n64.withUnsafeMutableBytes { p in
            for i in stride(from: 0, to: p.count, by: 4) { p.swapAt(i, i + 3); p.swapAt(i + 1, i + 2) }
        }
        #expect(CoreFactory.n64ByteOrder(v64) == .byteSwapped)
        #expect(CoreFactory.n64ByteOrder(n64) == .littleEndian)
        #expect(CoreFactory.detect(rom: v64, fileExtension: "v64") == .n64)
        #expect(CoreFactory.n64Normalised(v64) == z64)
        #expect(CoreFactory.n64Normalised(n64) == z64)
        #expect(CoreFactory.n64Normalised(Data(count: 0x2000)) == nil)
        #expect(CoreFactory.detect(rom: try testROM("demo.nes"), fileExtension: "nes") == .nes)
    }

    @Test func bootsWithHLEAndDrawsAFrame() throws {
        let n = try demo()
        #expect(n.system == .n64)
        #expect(n.videoSize == VideoSize(width: 320, height: 240))
        #expect(n.frameRate == 60)
        for _ in 0..<30 { n.runFrame(input: []) }
        let fb = Array(n.framebuffer)
        #expect(fb.allSatisfy { $0 >> 24 == 0xFF })
        #expect(fb.contains { $0 & 0xFFFFFF != 0 }, "the frame is black")
        #expect(b(corner(n)) > 0x40 && r(corner(n)) == 0, "background \(hex(corner(n)))")   // dark blue
        #expect(r(centre(n)) > 0xF0 && g(centre(n)) > 0xF0 && b(centre(n)) > 0xF0, "square \(hex(centre(n)))")
        #expect(n.debugPeekRDRAM(0x300) > 20, "the game counted \(n.debugPeekRDRAM(0x300)) frames")
        #expect(n.frameCounter == 30)
        dump(n, "n64_demo")
    }

    @Test func inputReachesTheGame() throws {
        let n = try demo()
        for _ in 0..<10 { n.runFrame(input: []) }
        for _ in 0..<3 { n.runFrame(input: [.a]) }
        #expect(r(centre(n)) > 0xF0 && g(centre(n)) < 0x10, "A: \(hex(centre(n)))")
        #expect(n.debugPeekRDRAM(0x304) >> 16 == 0x8000)
        for _ in 0..<3 { n.runFrame(input: [.b]) }
        #expect(g(centre(n)) > 0xF0 && r(centre(n)) < 0x10, "B: \(hex(centre(n)))")
        for _ in 0..<3 { n.runFrame(input: [.z]) }
        #expect(b(centre(n)) > 0xF0 && r(centre(n)) < 0x10, "Z: \(hex(centre(n)))")
        for _ in 0..<3 { n.runFrame(input: [.cUp]) }
        #expect(r(centre(n)) > 0xF0 && g(centre(n)) > 0xF0 && b(centre(n)) < 0x10, "C: \(hex(centre(n)))")
        for _ in 0..<3 { n.runFrame(input: [.l, .r, .start, .up]) }
        #expect(n.debugPeekRDRAM(0x304) >> 16 == 0x1830)   // Start, d-up, L, R
        // the analog stick: full right and up moves the square right and up
        n.setAnalog(AnalogStick(x: 1, y: 1), player: 0)
        for _ in 0..<3 { n.runFrame(input: []) }
        let word = n.debugPeekRDRAM(0x304)
        #expect(Int8(truncatingIfNeeded: word >> 8) == 80 && Int8(truncatingIfNeeded: word) == 80, "\(hex(word))")
        let left = n.framebuffer[121 * Self.w + 135]     // inside the centred square, outside the moved one
        #expect(r(left) < 0x10 && b(left) > 0x40, "\(hex(left))")
        let moved = n.framebuffer[100 * Self.w + 205]    // outside the centred square, inside the moved one
        #expect(r(moved) > 0xF0 && g(moved) > 0xF0, "\(hex(moved))")
        n.setAnalog(AnalogStick(x: -0.5, y: 0), player: 0)
        for _ in 0..<2 { n.runFrame(input: []) }
        #expect(Int8(truncatingIfNeeded: n.debugPeekRDRAM(0x304) >> 8) == -40)
    }

    @Test func audioIsNotSilent() throws {
        let n = try demo()
        for _ in 0..<10 { n.runFrame(input: []) }
        _ = n.drainAudioSamples()
        var samples: [Float] = []
        for _ in 0..<60 {
            n.runFrame(input: [])
            samples += n.drainAudioSamples()
        }
        #expect(n.nativeAudioRate == 32_025 || (31_900...32_100).contains(n.nativeAudioRate), "\(n.nativeAudioRate)")
        // one second of 48 kHz audio, give or take the AI FIFO's buffering
        #expect((44_000...52_000).contains(samples.count), "\(samples.count) samples")
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.2, "peak \(peak)")
        // a ~400 Hz square: count sign changes
        var crossings = 0
        for i in 1..<samples.count where (samples[i - 1] < 0) != (samples[i] < 0) { crossings += 1 }
        let hz = Double(crossings) / 2 / (Double(samples.count) / 48_000)
        #expect((380...420).contains(hz), "\(hz) Hz")
    }

    @Test func saveStateRoundTrip() throws {
        let n = try demo()
        for _ in 0..<20 { n.runFrame(input: []) }
        let start = Date()
        let state = n.saveState()
        let saveMS = Date().timeIntervalSince(start) * 1000
        #expect(state.count > 1000, "\(state.count) bytes")
        // play on with input, remember where it ends up
        let script: [InputState] = [[.a], [.a], [], [.b], [.z], [], [], [.cUp], [], []]
        for i in script { n.runFrame(input: i) }
        let frameA = Array(n.framebuffer)
        let counterA = n.debugPeekRDRAM(0x300)
        // back to the state, same input → same result
        try n.loadState(state)
        for i in script { n.runFrame(input: i) }
        #expect(n.debugPeekRDRAM(0x300) == counterA)
        #expect(Array(n.framebuffer) == frameA)
        // saving again right after loading gives the same machine
        try n.loadState(state)
        let again = n.saveState()
        try n.loadState(again)
        for i in script { n.runFrame(input: i) }
        #expect(Array(n.framebuffer) == frameA)
        // wrapped in our container, and junk is refused with the machine untouched
        let box = StateContainer(system: .n64, coreStateVersion: n.stateVersion, romCRC: n.romCRC, payload: state)
        let decoded = try StateContainer.decode(box.encoded())
        #expect(decoded.payload == state)
        let before = n.debugPeekRDRAM(0x300)
        #expect(throws: CoreError.self) { try n.loadState(Data("not a state".utf8)) }
        var truncated = state
        truncated.removeLast(state.count / 2)
        #expect(throws: CoreError.self) { try n.loadState(truncated) }
        #expect(n.debugPeekRDRAM(0x300) == before)
        n.runFrame(input: [])
        #expect(n.debugPeekRDRAM(0x300) == before + 1)
        print("N64 save state: \(state.count) bytes in \(Int(saveMS)) ms")
    }

    @Test func batterySavesRoundTrip() throws {
        var battery: Data?
        do {
            let n = try demo()
            for _ in 0..<10 { n.runFrame(input: []) }
            #expect(n.debugPeekRDRAM(0x308) == 0 && n.debugPeekRDRAM(0x30C) == 0)
            #expect(n.batteryRAM == nil)
            for _ in 0..<3 { n.runFrame(input: [.start]) }
            for _ in 0..<5 { n.runFrame(input: []) }
            #expect(n.debugPeekRDRAM(0x310) == 1)
            battery = n.batteryRAM
        }
        let blob = try #require(battery)
        #expect(blob.prefix(4) == Data("N64B".utf8))
        #expect(blob.range(of: Data("FB64OK!!".utf8)) != nil, "EEPROM in the blob")
        #expect(blob.range(of: Data("PAK!".utf8)) != nil, "Controller Pak in the blob")
        // a fresh machine with that battery sees both markers (EEPROM turns the background green)
        let n = try demo(battery: blob)
        for _ in 0..<10 { n.runFrame(input: []) }
        #expect(n.debugPeekRDRAM(0x308) == 1, "EEPROM restored")
        #expect(n.debugPeekRDRAM(0x30C) == 1, "Controller Pak restored")
        #expect(g(corner(n)) > 0x40 && b(corner(n)) < 0x10, "\(hex(corner(n)))")
        #expect(n.batteryRAM != nil)
    }

    @Test func resetRebootsAndOnlyOneMachineAtATime() throws {
        let n = try demo()
        #expect(throws: CoreError.self) { try N64System(rom: try testROM("n64_demo.z64"), battery: nil) }
        for _ in 0..<30 { n.runFrame(input: []) }
        #expect(n.debugPeekRDRAM(0x300) > 20)
        n.reset()
        for _ in 0..<5 { n.runFrame(input: []) }
        #expect(n.debugPeekRDRAM(0x300) < 10, "\(n.debugPeekRDRAM(0x300))")
        #expect(throws: CoreError.self) { try N64System(rom: Data(count: 0x2000), battery: nil) }
    }

    @Test func speed() throws {
        let n = try demo()
        for _ in 0..<10 { n.runFrame(input: []) }
        let frames = 600
        let start = Date()
        for _ in 0..<frames { n.runFrame(input: []) }
        let fps = Double(frames) / Date().timeIntervalSince(start)
        print("N64 cached interpreter: \(Int(fps)) fps (\(String(format: "%.1f", fps / 60))x real time)")
        #expect(fps > 60)
    }

    /// No Vulkan on the Mac test host: the VI scan-out is the expected fallback (no notice for the player), the
    /// command stream is still consumed, and rewind is off for N64.
    @Test func rendererFallsBackToVIScanOutWithoutVulkan() throws {
        let n = try demo()
        for _ in 0..<5 { n.runFrame(input: []) }
        #expect(n.renderer == .viUnavailable, "\(n.renderer) \(n.rendererInfo)")
        #expect(n.statusNotice == nil)
        #expect(n.supportsRewind == false)
        #expect(n.videoSize == VideoSize(width: 320, height: 240))
        n.prepareForSuspend()   // no renderer: a no-op, must not crash
    }

    // MARK: pipeline cache file (N64PipelineCache.h)

    private func cacheID(vendor: UInt32 = 0x106B, device: UInt32 = 0x1234, uuidByte: UInt8 = 7) -> N64PipelineCacheID {
        var id = N64PipelineCacheID()
        id.vendorID = vendor
        id.deviceID = device
        id.driverVersion = 0x0001_0402
        withUnsafeMutableBytes(of: &id.uuid) { p in for i in 0..<16 { p[i] = uuidByte &+ UInt8(i) } }
        return id
    }

    /// Granite's blob for `id`: UUID, an 8-byte hash, then a Vulkan cache with a VkPipelineCacheHeaderVersionOne.
    private func payload(_ id: N64PipelineCacheID, body: Int = 100) -> [UInt8] {
        var uuid = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: id.uuid) { p in for i in 0..<16 { uuid[i] = p[i] } }
        func le(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        var p = uuid + [UInt8](repeating: 0xAB, count: 8)
        p += le(32) + le(1) + le(id.vendorID) + le(id.deviceID) + uuid
        p += (0..<body).map { UInt8(truncatingIfNeeded: $0 * 31) }
        return p
    }

    private func file(_ id: N64PipelineCacheID, _ payload: [UInt8]) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: Int(N64_PIPELINE_CACHE_HEADER_SIZE))
        var id = id
        header.withUnsafeMutableBufferPointer { h in
            payload.withUnsafeBufferPointer { p in n64pc_make_header(h.baseAddress, &id, p.baseAddress, p.count) }
        }
        return header + payload
    }

    private func validate(_ f: [UInt8], _ id: N64PipelineCacheID) -> (ok: Bool, offset: Int, size: Int) {
        var id = id
        var off = 0, size = 0
        let ok = f.withUnsafeBufferPointer { n64pc_validate($0.baseAddress, $0.count, &id, &off, &size) }
        return (ok, off, size)
    }

    @Test func pipelineCacheFileRoundTrip() {
        let id = cacheID()
        let p = payload(id)
        let f = file(id, p)
        let r = validate(f, id)
        #expect(r.ok)
        #expect(r.offset == Int(N64_PIPELINE_CACHE_HEADER_SIZE) && r.size == p.count)
        #expect(Array(f[r.offset..<(r.offset + r.size)]) == p)
    }

    @Test func pipelineCacheFileRejectsCorruptOrForeignData() {
        let id = cacheID()
        let good = file(id, payload(id))
        // every single-byte flip anywhere in the file is caught (header fields, checksum, payload)
        for i in stride(from: 0, to: good.count, by: 3) {
            var bad = good
            bad[i] ^= 0x5A
            #expect(!validate(bad, id).ok, "flip at \(i)")
        }
        // truncated, extended, empty, nothing
        #expect(!validate(Array(good.dropLast()), id).ok)
        #expect(!validate(good + [0], id).ok)
        #expect(!validate(Array(good.prefix(Int(N64_PIPELINE_CACHE_HEADER_SIZE))), id).ok)
        #expect(!validate([], id).ok)
        var idCopy = id
        #expect(!n64pc_validate(nil, 0, &idCopy, nil, nil))
        // another GPU, driver or MoltenVK build (UUID)
        #expect(!validate(good, cacheID(device: 0x9999)).ok)
        #expect(!validate(good, cacheID(vendor: 0x10DE)).ok)
        #expect(!validate(good, cacheID(uuidByte: 8)).ok)
        var otherDriver = id
        otherDriver.driverVersion += 1
        #expect(!validate(good, otherDriver).ok)
        // a well-formed file whose Vulkan header names another device / version / impossible length
        for patch in [(24 + 8, UInt8(0x99)), (24 + 4, UInt8(2)), (24 + 0, UInt8(0xFF)), (24 + 0, UInt8(8))] {
            var p = payload(id)
            p[patch.0] = patch.1
            #expect(!validate(file(id, p), id).ok, "vk header patch at \(patch.0)")
        }
        // too short to hold Granite's prefix and a Vulkan header
        #expect(!validate(file(id, Array(payload(id).prefix(40))), id).ok)
    }

    private func dump(_ n: N64System, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DUMP_DIR"] else { return }
        writePNG(n.framebuffer, width: 320, height: 240, to: "\(dir)/\(name).png")
    }
}
