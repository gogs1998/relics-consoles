import CoreKit
import Foundation
import MGBA

/// The Game Boy Advance, emulated by the vendored mGBA core (MPL-2.0, ThirdParty/mgba).
///
/// A thin wrapper over our C glue (`Sources/MGBA/glue`): mGBA's software renderer, its built-in
/// HLE BIOS (no BIOS file is ever read) and its sinc resampler, which turns the game's native audio
/// rate (32-262 kHz, set by SOUNDBIAS) into mono at `audioSampleRate`.
/// Confined to one thread like every core; the handle is never shared.
public final class GBASystem: EmulatorCore {
    public let system = SystemID.gba
    public let videoSize = VideoSize(width: Int(MGBA_WIDTH), height: Int(MGBA_HEIGHT))
    public let pixelAspect = 1.0
    public let frameRate = 16_777_216.0 / 280_896.0
    public let audioSampleRate = 48_000.0
    /// mGBA's own state format (it carries its own version and ROM checks); bump with the vendored snapshot.
    public let stateVersion: UInt32 = 1

    private let handle: OpaquePointer
    public let romCRC: UInt32

    public init(rom: Data, battery: Data?) throws {
        guard rom.count >= 0xC0 else { throw CoreError.unrecognisedFile }
        let made: OpaquePointer? = rom.withUnsafeBytes { romBuf in
            let romPtr = romBuf.bindMemory(to: UInt8.self).baseAddress
            if let battery, !battery.isEmpty {
                return battery.withUnsafeBytes { saveBuf in
                    mgba_create(romPtr, romBuf.count, saveBuf.bindMemory(to: UInt8.self).baseAddress,
                                saveBuf.count, 48_000)
                }
            }
            return mgba_create(romPtr, romBuf.count, nil, 0, 48_000)
        }
        guard let made else { throw CoreError.unrecognisedFile }
        handle = made
        romCRC = GBASystem.crc32(rom)
    }

    deinit { mgba_destroy(handle) }

    public func reset() { mgba_reset(handle) }

    public func runFrame(input: InputState) {
        let i = input.sanitised
        var keys: UInt32 = 0
        if i.contains(.a) { keys |= UInt32(MGBA_KEY_A) }
        if i.contains(.b) { keys |= UInt32(MGBA_KEY_B) }
        if i.contains(.select) { keys |= UInt32(MGBA_KEY_SELECT) }
        if i.contains(.start) { keys |= UInt32(MGBA_KEY_START) }
        if i.contains(.right) { keys |= UInt32(MGBA_KEY_RIGHT) }
        if i.contains(.left) { keys |= UInt32(MGBA_KEY_LEFT) }
        if i.contains(.up) { keys |= UInt32(MGBA_KEY_UP) }
        if i.contains(.down) { keys |= UInt32(MGBA_KEY_DOWN) }
        if i.contains(.r) { keys |= UInt32(MGBA_KEY_R) }
        if i.contains(.l) { keys |= UInt32(MGBA_KEY_L) }
        mgba_run_frame(handle, keys)
    }

    public var framebuffer: UnsafeBufferPointer<UInt32> {
        UnsafeBufferPointer(start: mgba_framebuffer(handle), count: videoSize.width * videoSize.height)
    }

    public func drainAudio(into ring: AudioRing) {
        var out: UnsafePointer<Float>?
        let n = mgba_drain_audio(handle, &out)
        if n > 0, let out { ring.write(UnsafeBufferPointer(start: out, count: n)) }
    }

    /// Drains the pending samples into an array (tests).
    func drainAudioSamples() -> [Float] {
        var out: UnsafePointer<Float>?
        let n = mgba_drain_audio(handle, &out)
        guard n > 0, let out else { return [] }
        return Array(UnsafeBufferPointer(start: out, count: n))
    }

    public func discardAudio() { mgba_discard_audio(handle) }

    public var batteryRAM: Data? {
        var ptr: UnsafeMutablePointer<UInt8>?
        let n = mgba_savedata(handle, &ptr)
        guard n > 0, let ptr else { return nil }
        defer { mgba_free(ptr) }
        return Data(bytes: ptr, count: n)
    }

    public func saveState() -> Data {
        var ptr: UnsafeMutablePointer<UInt8>?
        let n = mgba_save_state(handle, &ptr)
        guard n > 0, let ptr else { return Data() }
        defer { mgba_free(ptr) }
        return Data(bytes: ptr, count: n)
    }

    public func loadState(_ data: Data) throws {
        let ok = data.withUnsafeBytes { buf in
            mgba_load_state(handle, buf.bindMemory(to: UInt8.self).baseAddress, buf.count)
        }
        if !ok { throw CoreError.stateMismatch("not a save state for this game") }
    }

    /// Side-effect-free bus read (tests, debugging).
    public func debugPeek(_ address: UInt32) -> UInt8 { mgba_peek(handle, address) }

    public var frameCounter: UInt32 { mgba_frame_counter(handle) }
    /// The game's current native audio rate before resampling.
    public var nativeAudioRate: UInt32 { mgba_native_audio_rate(handle) }

    private static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}
