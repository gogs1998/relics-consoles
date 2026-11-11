import CoreKit
import Foundation
import MELONDS

/// The Nintendo DS (DS mode only), emulated by the vendored melonDS core (GPL-3.0-or-later,
/// ThirdParty/melonds), interpreter only.
///
/// A thin wrapper over our C glue (`Sources/MELONDS/glue`). Boots with no Nintendo files at all:
/// melonDS's FreeBIOS (BSD-2-Clause, an independent BIOS replacement), a generated firmware image and
/// a direct boot of the cartridge. The framebuffer stacks the two 256x192 screens (top screen above
/// the touch screen); `screens` describes them. melonDS's own resampler delivers mono audio at
/// `audioSampleRate` (the Decimator only downsamples per-clock levels, and the DS mixes at ~32.7 kHz).
/// Confined to one thread like every core; the handle is never shared.
public final class DSSystem: EmulatorCore {
    public let system = SystemID.ds
    public static let screenWidth = Int(MELONDS_SCREEN_WIDTH)
    public static let screenHeight = Int(MELONDS_SCREEN_HEIGHT)
    public let videoSize = VideoSize(width: DSSystem.screenWidth, height: DSSystem.screenHeight * 2)
    public let pixelAspect = 1.0
    /// 33.513982 MHz / (6 x 355 dots x 263 lines).
    public let frameRate = 33_513_982.0 / 560_190.0
    public let audioSampleRate = 48_000.0
    /// melonDS's own savestate format (it carries its own version); bump with the vendored snapshot.
    public let stateVersion: UInt32 = 1

    public let screens = [
        ScreenRegion(x: 0, y: 0, width: DSSystem.screenWidth, height: DSSystem.screenHeight),
        ScreenRegion(x: 0, y: DSSystem.screenHeight, width: DSSystem.screenWidth, height: DSSystem.screenHeight,
                     isTouch: true),
    ]

    private let handle: OpaquePointer
    public let romCRC: UInt32
    private var touch: TouchPoint?

    /// - Parameter threaded3D: run the software 3D rasteriser on a second thread (faster on
    ///   multi-core devices; the 2D engines always run on the emulation thread).
    public init(rom: Data, battery: Data?, threaded3D: Bool = true) throws {
        guard rom.count >= 0x1000 else { throw CoreError.unrecognisedFile }
        let made: OpaquePointer? = rom.withUnsafeBytes { romBuf in
            let romPtr = romBuf.bindMemory(to: UInt8.self).baseAddress
            if let battery, !battery.isEmpty {
                return battery.withUnsafeBytes { saveBuf in
                    melonds_create(romPtr, romBuf.count, saveBuf.bindMemory(to: UInt8.self).baseAddress,
                                   saveBuf.count, 48_000, threaded3D)
                }
            }
            return melonds_create(romPtr, romBuf.count, nil, 0, 48_000, threaded3D)
        }
        guard let made else { throw CoreError.unrecognisedFile }
        handle = made
        romCRC = DSSystem.crc32(rom)
    }

    deinit { melonds_destroy(handle) }

    public func reset() { melonds_reset(handle) }

    public func setTouch(_ point: TouchPoint?) {
        guard let point else { touch = nil; return }
        touch = TouchPoint(x: min(max(point.x, 0), Self.screenWidth - 1),
                           y: min(max(point.y, 0), Self.screenHeight - 1))
    }

    public func runFrame(input: InputState) {
        let i = input.sanitised
        var keys: UInt32 = 0
        if i.contains(.a) { keys |= UInt32(MELONDS_KEY_A) }
        if i.contains(.b) { keys |= UInt32(MELONDS_KEY_B) }
        if i.contains(.x) { keys |= UInt32(MELONDS_KEY_X) }
        if i.contains(.y) { keys |= UInt32(MELONDS_KEY_Y) }
        if i.contains(.select) { keys |= UInt32(MELONDS_KEY_SELECT) }
        if i.contains(.start) { keys |= UInt32(MELONDS_KEY_START) }
        if i.contains(.right) { keys |= UInt32(MELONDS_KEY_RIGHT) }
        if i.contains(.left) { keys |= UInt32(MELONDS_KEY_LEFT) }
        if i.contains(.up) { keys |= UInt32(MELONDS_KEY_UP) }
        if i.contains(.down) { keys |= UInt32(MELONDS_KEY_DOWN) }
        if i.contains(.r) { keys |= UInt32(MELONDS_KEY_R) }
        if i.contains(.l) { keys |= UInt32(MELONDS_KEY_L) }
        if let touch {
            melonds_run_frame(handle, keys, true, UInt16(touch.x), UInt16(touch.y))
        } else {
            melonds_run_frame(handle, keys, false, 0, 0)
        }
    }

    public var framebuffer: UnsafeBufferPointer<UInt32> {
        UnsafeBufferPointer(start: melonds_framebuffer(handle), count: videoSize.width * videoSize.height)
    }

    public func drainAudio(into ring: AudioRing) {
        var out: UnsafePointer<Float>?
        let n = melonds_drain_audio(handle, &out)
        if n > 0, let out { ring.write(UnsafeBufferPointer(start: out, count: n)) }
    }

    /// Drains the pending samples into an array (tests).
    func drainAudioSamples() -> [Float] {
        var out: UnsafePointer<Float>?
        let n = melonds_drain_audio(handle, &out)
        guard n > 0, let out else { return [] }
        return Array(UnsafeBufferPointer(start: out, count: n))
    }

    public func discardAudio() { melonds_discard_audio(handle) }

    public var batteryRAM: Data? {
        var ptr: UnsafeMutablePointer<UInt8>?
        let n = melonds_savedata(handle, &ptr)
        guard n > 0, let ptr else { return nil }
        defer { melonds_free(ptr) }
        return Data(bytes: ptr, count: n)
    }

    public func saveState() -> Data {
        var ptr: UnsafeMutablePointer<UInt8>?
        let n = melonds_save_state(handle, &ptr)
        guard n > 0, let ptr else { return Data() }
        defer { melonds_free(ptr) }
        return Data(bytes: ptr, count: n)
    }

    public func loadState(_ data: Data) throws {
        let ok = data.withUnsafeBytes { buf in
            melonds_load_state(handle, buf.bindMemory(to: UInt8.self).baseAddress, buf.count)
        }
        if !ok { throw CoreError.stateMismatch("not a save state for this game") }
    }

    public var frameCounter: UInt32 { melonds_frame_counter(handle) }

    /// Tests: a word of main RAM, read without side effects.
    public func debugPeekMainRAM(_ address: UInt32) -> UInt32 { melonds_peek_main_ram(handle, address) }

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
