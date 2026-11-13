import CoreKit
import Foundation
import MUPEN64

/// The Nintendo 64, emulated by the vendored mupen64plus core with rsp-hle (both GPL-2.0-or-later,
/// ThirdParty/mupen64), cached interpreter only.
///
/// A thin wrapper over our C glue (`Sources/MUPEN64/glue`). Boots with no Nintendo files: the core's
/// HLE boot stands in for the PIF boot ROM. mupen64plus keeps one machine in process globals, so only
/// one `N64System` can be alive at a time (the initialiser throws while another exists).
///
/// Video: no RDP renderer is linked yet (GLideN64 is GPL-2.0-only; see ThirdParty/mupen64/README.md),
/// so the framebuffer is the VI scan-out of RDRAM: anything the CPU drew is shown, RDP rendering is not.
public final class N64System: EmulatorCore {
    public let system = SystemID.n64
    public let videoSize = VideoSize(width: Int(N64_SCREEN_WIDTH), height: Int(N64_SCREEN_HEIGHT))
    public let pixelAspect = 1.0
    public let frameRate: Double
    public let audioSampleRate = 48_000.0
    /// mupen64plus's own savestate format (gzip, carries its own version); bump with the snapshot.
    public let stateVersion: UInt32 = 1
    public let maxPlayers = 2

    private let handle: OpaquePointer
    private let workDir: URL
    public let romCRC: UInt32
    private var sticks = [AnalogStick](repeating: .centre, count: 4)

    /// - Parameters:
    ///   - rom: the ROM in any of the three byte orders (normalised to big-endian here).
    ///   - battery: a blob from `batteryRAM`.
    public init(rom: Data, battery: Data?) throws {
        guard let z64 = CoreFactory.n64Normalised(rom) else { throw CoreError.unrecognisedFile }
        guard let ini = Bundle.module.url(forResource: "mupen64plus", withExtension: "ini") else {
            throw CoreError.corruptFile("the ROM database is missing")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("n64-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let made: OpaquePointer? = z64.withUnsafeBytes { romBuf in
            let romPtr = romBuf.bindMemory(to: UInt8.self).baseAddress
            let dataDir = ini.deletingLastPathComponent().path
            if let battery, !battery.isEmpty {
                return battery.withUnsafeBytes { saveBuf in
                    n64_create(romPtr, romBuf.count, saveBuf.bindMemory(to: UInt8.self).baseAddress, saveBuf.count,
                               dir.path, dataDir)
                }
            }
            return n64_create(romPtr, romBuf.count, nil, 0, dir.path, dataDir)
        }
        guard let made else {
            try? FileManager.default.removeItem(at: dir)
            throw CoreError.unrecognisedFile
        }
        handle = made
        workDir = dir
        frameRate = n64_frame_rate(made)
        romCRC = CRC32.checksum(z64)
    }

    deinit {
        n64_destroy(handle)
        try? FileManager.default.removeItem(at: workDir)
    }

    public func reset() { n64_reset(handle) }

    public func setAnalog(_ stick: AnalogStick, player: Int) {
        guard (0..<4).contains(player) else { return }
        sticks[player] = stick
    }

    public func runFrame(input: InputState) { runFrame(inputs: [input]) }

    public func runFrame(inputs: [InputState]) {
        for port in 0..<maxPlayers {
            let i = port < inputs.count ? inputs[port].sanitised : []
            let s = sticks[port]
            n64_set_input(handle, Int32(port), Self.buttons(i), Self.axis(s.x), Self.axis(s.y))
        }
        n64_run_frame(handle)
    }

    /// A real controller's stick reaches about ±80 of its ±128 range; scale to that.
    static func axis(_ v: Double) -> Int8 {
        Int8(clamping: Int((max(-1, min(1, v)) * 80).rounded()))
    }

    static func buttons(_ i: InputState) -> UInt32 {
        var b: UInt32 = 0
        if i.contains(.right) { b |= UInt32(N64_BTN_DRIGHT) }
        if i.contains(.left) { b |= UInt32(N64_BTN_DLEFT) }
        if i.contains(.down) { b |= UInt32(N64_BTN_DDOWN) }
        if i.contains(.up) { b |= UInt32(N64_BTN_DUP) }
        if i.contains(.start) { b |= UInt32(N64_BTN_START) }
        if i.contains(.z) { b |= UInt32(N64_BTN_Z) }
        if i.contains(.b) { b |= UInt32(N64_BTN_B) }
        if i.contains(.a) { b |= UInt32(N64_BTN_A) }
        if i.contains(.cRight) { b |= UInt32(N64_BTN_CRIGHT) }
        if i.contains(.cLeft) { b |= UInt32(N64_BTN_CLEFT) }
        if i.contains(.cDown) { b |= UInt32(N64_BTN_CDOWN) }
        if i.contains(.cUp) { b |= UInt32(N64_BTN_CUP) }
        if i.contains(.r) { b |= UInt32(N64_BTN_R) }
        if i.contains(.l) { b |= UInt32(N64_BTN_L) }
        return b
    }

    public var framebuffer: UnsafeBufferPointer<UInt32> {
        UnsafeBufferPointer(start: n64_framebuffer(handle), count: videoSize.width * videoSize.height)
    }

    public func drainAudio(into ring: AudioRing) {
        var out: UnsafePointer<Float>?
        let n = n64_drain_audio(handle, &out)
        if n > 0, let out { ring.write(UnsafeBufferPointer(start: out, count: n)) }
    }

    /// Drains the pending samples into an array (tests).
    func drainAudioSamples() -> [Float] {
        var out: UnsafePointer<Float>?
        let n = n64_drain_audio(handle, &out)
        guard n > 0, let out else { return [] }
        return Array(UnsafeBufferPointer(start: out, count: n))
    }

    public func discardAudio() { n64_discard_audio(handle) }

    /// The rate the game programmed into the audio interface (Hz).
    public var nativeAudioRate: UInt32 { n64_audio_rate(handle) }

    /// EEPROM, SRAM, FlashRAM and Controller Pak contents the game has written, as one blob.
    public var batteryRAM: Data? {
        var ptr: UnsafeMutablePointer<UInt8>?
        let n = n64_battery(handle, &ptr)
        guard n > 0, let ptr else { return nil }
        defer { n64_free(ptr) }
        return Data(bytes: ptr, count: n)
    }

    public func saveState() -> Data {
        var ptr: UnsafeMutablePointer<UInt8>?
        let n = n64_save_state(handle, &ptr)
        guard n > 0, let ptr else { return Data() }
        defer { n64_free(ptr) }
        return Data(bytes: ptr, count: n)
    }

    public func loadState(_ data: Data) throws {
        let ok = data.withUnsafeBytes { buf in
            n64_load_state(handle, buf.bindMemory(to: UInt8.self).baseAddress, buf.count)
        }
        if !ok { throw CoreError.stateMismatch("not a save state for this game") }
    }

    public var frameCounter: UInt32 { n64_frame_counter(handle) }

    /// Tests: a big-endian word of RDRAM.
    public func debugPeekRDRAM(_ address: UInt32) -> UInt32 { n64_peek_rdram(handle, address) }
}
