import ARES
import CoreKit
import Foundation

/// Shared plumbing for the systems emulated by the vendored ares cores (ISC, ThirdParty/ares).
///
/// A thin wrapper over our C glue (`Sources/ARES/glue`). ares keeps each console's hardware in
/// process-wide globals, so only one ares-backed core (SNES or Mega Drive) may exist at a time;
/// creating a second throws `AresError.busy` until the first is released. Confined to one thread
/// like every core; the handle is never shared.
public class AresMachine {
    let handle: OpaquePointer
    public let romCRC: UInt32
    private let defaultSize: VideoSize
    private let blank: UnsafeMutableBufferPointer<UInt32>

    init(kind: AresSystem, rom: Data, battery: Data?, defaultSize: VideoSize) throws {
        var error = [CChar](repeating: 0, count: 32)
        let made: OpaquePointer? = rom.withUnsafeBytes { romBuf in
            let romPtr = romBuf.bindMemory(to: UInt8.self).baseAddress
            return error.withUnsafeMutableBufferPointer { err in
                if let battery, !battery.isEmpty {
                    return battery.withUnsafeBytes { saveBuf in
                        ares_create(kind, romPtr, romBuf.count, saveBuf.bindMemory(to: UInt8.self).baseAddress,
                                    saveBuf.count, 48_000, err.baseAddress, err.count)
                    }
                }
                return ares_create(kind, romPtr, romBuf.count, nil, 0, 48_000, err.baseAddress, err.count)
            }
        }
        guard let made else {
            let reason = String(decoding: error.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            switch reason {
            case "busy": throw AresError.busy
            case "firmware": throw AresError.needsFirmware
            default: throw CoreError.unrecognisedFile
            }
        }
        handle = made
        romCRC = AresMachine.crc32(rom)
        self.defaultSize = defaultSize
        blank = .allocate(capacity: defaultSize.width * defaultSize.height)
        blank.initialize(repeating: 0xFF00_0000)
    }

    deinit {
        ares_destroy(handle)
        blank.deallocate()
    }

    public let audioSampleRate = 48_000.0
    /// ares' own serializer format (it carries its own signature/version); bump with the vendored snapshot.
    public let stateVersion: UInt32 = 1

    /// The current frame's size (it can change between frames: hi-res, H32/H40, interlace).
    public var videoSize: VideoSize {
        var w: UInt32 = 0, h: UInt32 = 0
        _ = ares_framebuffer(handle, &w, &h)
        return w > 0 && h > 0 ? VideoSize(width: Int(w), height: Int(h)) : defaultSize
    }

    public var frameRate: Double { ares_frame_rate(handle) }
    public var isPAL: Bool { ares_is_pal(handle) }
    public var frameCounter: UInt32 { ares_frame_counter(handle) }

    public func reset() { ares_reset(handle) }

    /// Both controller ports are connected (same pad type in each).
    public var maxPlayers: Int { 2 }

    /// Sets ports 1 and 2 (a missing player is released) and runs one frame.
    func run(ports: [UInt32]) {
        ares_set_input(handle, 0, ports.first ?? 0)
        ares_set_input(handle, 1, ports.count > 1 ? ports[1] : 0)
        ares_run_frame_ports(handle)
    }

    /// Tests: button reads the core made from `port` (0 or 1) in the last frame, and the pressed bits it saw.
    func debugPortReads(_ port: UInt32) -> (reads: UInt32, seen: UInt32) {
        var seen: UInt32 = 0
        let reads = ares_debug_port_reads(handle, port, &seen)
        return (reads, seen)
    }

    public var framebuffer: UnsafeBufferPointer<UInt32> {
        var w: UInt32 = 0, h: UInt32 = 0
        let p = ares_framebuffer(handle, &w, &h)
        if let p, w > 0, h > 0 { return UnsafeBufferPointer(start: p, count: Int(w) * Int(h)) }
        return UnsafeBufferPointer(blank)
    }

    public func drainAudio(into ring: AudioRing) {
        var out: UnsafePointer<Float>?
        let n = ares_drain_audio(handle, &out)
        if n > 0, let out { ring.write(UnsafeBufferPointer(start: out, count: n)) }
    }

    /// Drains the pending samples into an array (tests).
    func drainAudioSamples() -> [Float] {
        var out: UnsafePointer<Float>?
        let n = ares_drain_audio(handle, &out)
        guard n > 0, let out else { return [] }
        return Array(UnsafeBufferPointer(start: out, count: n))
    }

    public func discardAudio() { ares_discard_audio(handle) }

    public var batteryRAM: Data? {
        var ptr: UnsafeMutablePointer<UInt8>?
        let n = ares_battery(handle, &ptr)
        guard n > 0, let ptr else { return nil }
        defer { ares_free(ptr) }
        return Data(bytes: ptr, count: n)
    }

    public func saveState() -> Data {
        var ptr: UnsafeMutablePointer<UInt8>?
        let n = ares_save_state(handle, &ptr)
        guard n > 0, let ptr else { return Data() }
        defer { ares_free(ptr) }
        return Data(bytes: ptr, count: n)
    }

    public func loadState(_ data: Data) throws {
        let ok = data.withUnsafeBytes { buf in
            ares_load_state(handle, buf.bindMemory(to: UInt8.self).baseAddress, buf.count)
        }
        if !ok { throw CoreError.stateMismatch("not a save state for this game") }
    }

    /// D-pad, Start and Select/Mode bits shared by both systems (input already sanitised).
    static func directionBits(_ i: InputState) -> UInt32 {
        var b: UInt32 = 0
        if i.contains(.up) { b |= UInt32(ARES_BTN_UP) }
        if i.contains(.down) { b |= UInt32(ARES_BTN_DOWN) }
        if i.contains(.left) { b |= UInt32(ARES_BTN_LEFT) }
        if i.contains(.right) { b |= UInt32(ARES_BTN_RIGHT) }
        if i.contains(.start) { b |= UInt32(ARES_BTN_START) }
        if i.contains(.select) { b |= UInt32(ARES_BTN_SELECT) }
        return b
    }

    static func crc32(_ data: Data) -> UInt32 {
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

public enum AresError: Error, LocalizedError, Equatable {
    /// Another SNES or Mega Drive game is still loaded (ares allows one per process).
    case busy
    /// The cartridge has a coprocessor whose program is chip firmware we don't ship
    /// (DSP-1..4, ST010/011/018, Cx4, Super Game Boy).
    case needsFirmware

    public var errorDescription: String? {
        switch self {
        case .busy: "Another game is still running."
        case .needsFirmware: "This game uses a cartridge chip that isn't supported."
        }
    }
}

/// The SNES, emulated by ares (ISC). Boots with our own SPC700 boot program, never Nintendo's IPL.
public final class SNESSystem: AresMachine, EmulatorCore {
    public let system = SystemID.snes

    public init(rom: Data, battery: Data?) throws {
        try super.init(kind: ARES_SYSTEM_SNES, rom: rom, battery: battery,
                       defaultSize: VideoSize(width: 256, height: 224))
    }

    /// 8:7 for a 256-wide frame; hi-res (512) pixels are half as wide, interlaced lines half as tall.
    public var pixelAspect: Double {
        let size = videoSize
        let base = isPAL ? 55.0 / 43.0 : 8.0 / 7.0
        return base * 256.0 / Double(size.width) * (size.height > 300 ? 2 : 1)
    }

    /// Player 1 only; port 2 is released.
    public func runFrame(input: InputState) {
        run(ports: [Self.bits(input)])
    }

    public func runFrame(inputs: [InputState]) {
        run(ports: inputs.prefix(2).map(Self.bits))
    }

    static func bits(_ input: InputState) -> UInt32 {
        let i = input.sanitised
        var b = AresMachine.directionBits(i)
        if i.contains(.b) { b |= UInt32(ARES_SNES_B) }
        if i.contains(.y) { b |= UInt32(ARES_SNES_Y) }
        if i.contains(.a) { b |= UInt32(ARES_SNES_A) }
        if i.contains(.x) { b |= UInt32(ARES_SNES_X) }
        if i.contains(.l) { b |= UInt32(ARES_SNES_L) }
        if i.contains(.r) { b |= UInt32(ARES_SNES_R) }
        return b
    }
}

/// The Mega Drive / Genesis, emulated by ares (ISC), with a 6-button pad. TMSS is off; no BIOS.
public final class MDSystem: AresMachine, EmulatorCore {
    public let system = SystemID.md

    public init(rom: Data, battery: Data?) throws {
        try super.init(kind: ARES_SYSTEM_MD, rom: rom, battery: battery,
                       defaultSize: VideoSize(width: 320, height: 224))
    }

    /// ares' aspect for a 320-wide (H40) frame is 32:35 (NTSC) / 41:37 (PAL); H32 pixels are 5/4 wider.
    public var pixelAspect: Double {
        let size = videoSize
        let base = isPAL ? 41.0 / 37.0 : 32.0 / 35.0
        return base * 320.0 / Double(size.width) * (size.height > 300 ? 2 : 1)
    }

    /// InputState → 6-button pad: y→A, b→B, a→C (so the bottom row Y/B/A reads A/B/C left to right),
    /// x→X, l→Y, r→Z, select→Mode, start→Start.
    /// Player 1 only; port 2 is released.
    public func runFrame(input: InputState) {
        run(ports: [Self.bits(input)])
    }

    public func runFrame(inputs: [InputState]) {
        run(ports: inputs.prefix(2).map(Self.bits))
    }

    static func bits(_ input: InputState) -> UInt32 {
        let i = input.sanitised
        var b = AresMachine.directionBits(i)
        if i.contains(.y) { b |= UInt32(ARES_MD_A) }
        if i.contains(.b) { b |= UInt32(ARES_MD_B) }
        if i.contains(.a) { b |= UInt32(ARES_MD_C) }
        if i.contains(.x) { b |= UInt32(ARES_MD_X) }
        if i.contains(.l) { b |= UInt32(ARES_MD_Y) }
        if i.contains(.r) { b |= UInt32(ARES_MD_Z) }
        return b
    }
}
