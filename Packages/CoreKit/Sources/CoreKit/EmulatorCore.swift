import Foundation

/// The systems the app knows about. Plain-text names only (no logos, no trade dress).
public enum SystemID: String, Codable, Sendable, CaseIterable, Identifiable {
    case nes
    case gb
    case gbc
    case gba
    case snes
    case md
    case ds

    public var id: String { rawValue }

    /// The factual, plain-text system name shown in section headers.
    public var displayName: String {
        switch self {
        case .nes: "NES"
        case .gb: "Game Boy"
        case .gbc: "Game Boy Color"
        case .gba: "Game Boy Advance"
        case .snes: "SNES"
        case .md: "Mega Drive / Genesis"
        case .ds: "Nintendo DS"
        }
    }

    public var fileExtensions: [String] {
        switch self {
        case .nes: ["nes"]
        case .gb: ["gb"]
        case .gbc: ["gbc"]
        case .gba: ["gba"]
        case .snes: ["sfc", "smc"]
        case .md: ["md", "gen", "bin", "smd"]
        case .ds: ["nds"]
        }
    }

    /// Which buttons the touch controller should draw.
    public var faceButtons: [InputState] {
        [.b, .a]
    }
}

/// One player's buttons, system-neutral. Each core maps what it has.
public struct InputState: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let up     = InputState(rawValue: 1 << 0)
    public static let down   = InputState(rawValue: 1 << 1)
    public static let left   = InputState(rawValue: 1 << 2)
    public static let right  = InputState(rawValue: 1 << 3)
    public static let a      = InputState(rawValue: 1 << 4)
    public static let b      = InputState(rawValue: 1 << 5)
    public static let x      = InputState(rawValue: 1 << 6)
    public static let y      = InputState(rawValue: 1 << 7)
    public static let l      = InputState(rawValue: 1 << 8)
    public static let r      = InputState(rawValue: 1 << 9)
    public static let start  = InputState(rawValue: 1 << 10)
    public static let select = InputState(rawValue: 1 << 11)

    /// Real pads cannot press opposite directions; some games crash if they see it.
    public var sanitised: InputState {
        var s = self
        if s.contains([.left, .right]) { s.remove([.left, .right]) }
        if s.contains([.up, .down]) { s.remove([.up, .down]) }
        return s
    }
}

public struct VideoSize: Sendable, Equatable, Hashable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
}

/// One physical screen inside a core's framebuffer (most systems have one covering the whole frame).
public struct ScreenRegion: Sendable, Equatable, Hashable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    /// The player can touch this screen (the DS's lower screen).
    public var isTouch: Bool
    public init(x: Int, y: Int, width: Int, height: Int, isTouch: Bool = false) {
        self.x = x; self.y = y; self.width = width; self.height = height; self.isTouch = isTouch
    }
}

/// A stylus position on a touch screen, in that screen's own pixels (0..<width, 0..<height).
public struct TouchPoint: Sendable, Equatable, Hashable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

public enum CoreError: Error, LocalizedError, Equatable {
    case unrecognisedFile
    case unsupportedMapper(Int)
    case corruptFile(String)
    case stateMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .unrecognisedFile: "This file isn't a game this app can play."
        case .unsupportedMapper(let m): "This game uses cartridge hardware (mapper \(m)) that isn't supported yet."
        case .corruptFile(let why): "The file looks damaged: \(why)."
        case .stateMismatch(let why): "That save state can't be loaded: \(why)."
        }
    }
}

/// A console core. Confined to one thread (the emulation thread); never shared.
///
/// Everything that crosses threads is a value (`InputState`), the frame copy, or the audio ring.
public protocol EmulatorCore: AnyObject {
    var system: SystemID { get }
    var videoSize: VideoSize { get }
    /// Width / height of one pixel when "correct aspect" is on (8/7 for NES).
    var pixelAspect: Double { get }
    var frameRate: Double { get }
    /// The rate `drainAudio` delivers mono samples at.
    var audioSampleRate: Double { get }
    /// Bumped whenever the core's state layout changes.
    var stateVersion: UInt32 { get }

    func reset()
    /// The only hot call: emulate one video frame with the given input held.
    func runFrame(input: InputState)
    /// How many controllers the core can read (1 unless it wires up more ports).
    var maxPlayers: Int { get }
    /// Emulate one frame with one `InputState` per player (index 0 = player 1). Missing players
    /// are released; extras beyond `maxPlayers` are ignored.
    func runFrame(inputs: [InputState])
    /// BGRA8 pixels (as little-endian 0xAARRGGBB words), `videoSize`, owned by the core.
    var framebuffer: UnsafeBufferPointer<UInt32> { get }
    /// Moves every sample produced since the last call into `ring`.
    func drainAudio(into ring: AudioRing)
    /// Throws away pending samples (fast-forward, rewind).
    func discardAudio()
    /// Battery-backed cartridge RAM, or nil if the cartridge has none.
    var batteryRAM: Data? { get }
    func saveState() -> Data
    func loadState(_ data: Data) throws

    /// The physical screens inside `framebuffer`, in display order (top screen first).
    /// Defaults to one screen covering the whole frame.
    var screens: [ScreenRegion] { get }
    /// Sets (or lifts, with nil) the stylus on the touch screen for the following frames.
    /// Ignored by cores without one.
    func setTouch(_ point: TouchPoint?)
}

public extension EmulatorCore {
    var maxPlayers: Int { 1 }
    func runFrame(inputs: [InputState]) { runFrame(input: inputs.first ?? []) }
    var screens: [ScreenRegion] { [ScreenRegion(x: 0, y: 0, width: videoSize.width, height: videoSize.height)] }
    func setTouch(_ point: TouchPoint?) {}
    /// The touch screen, if the system has one.
    var touchScreen: ScreenRegion? { screens.first { $0.isTouch } }
}

/// Identifies a file's system. (Building the core is the app's job: it imports each core module.)
public enum CoreFactory {
    /// Detects the system from the file's header, falling back to its extension.
    public static func detect(rom: Data, fileExtension: String) -> SystemID? {
        if rom.count >= 16, rom[rom.startIndex] == 0x4E, rom[rom.startIndex + 1] == 0x45,
           rom[rom.startIndex + 2] == 0x53, rom[rom.startIndex + 3] == 0x1A {
            return .nes
        }
        if dsHeaderValid(rom) { return .ds }
        if rom.count >= 0xC0 {
            // Game Boy Advance header: a branch at 0 (byte 3 = $EA), the fixed $96 at $B2 and a
            // valid complement check at $BD. Checked before the GB header, which a GBA ROM can pass by chance.
            let b = rom.startIndex
            if rom[b + 3] == 0xEA, rom[b + 0xB2] == 0x96 {
                var chk: UInt8 = 0
                for i in 0xA0...0xBC { chk = chk &- rom[b + i] }
                if chk &- 0x19 == rom[b + 0xBD] { return .gba }
            }
        }
        // Mega Drive: "SEGA" at $100 (the console's own cartridge check string).
        if rom.count >= 0x200, rom[rom.startIndex + 0x100] == 0x53, rom[rom.startIndex + 0x101] == 0x45,
           rom[rom.startIndex + 0x102] == 0x47, rom[rom.startIndex + 0x103] == 0x41 {
            return .md
        }
        if snesHeaderValid(rom) { return .snes }
        if rom.count >= 0x150 {
            // Game Boy cartridge header: check the header checksum at $14D.
            var sum: UInt8 = 0
            for i in 0x134...0x14C { sum = sum &- rom[rom.startIndex + i] &- 1 }
            if sum == rom[rom.startIndex + 0x14D] {
                let cgb = rom[rom.startIndex + 0x143]
                return (cgb & 0x80) != 0 ? .gbc : .gb
            }
        }
        switch fileExtension.lowercased() {
        case "nes": return .nes
        case "gb": return .gb
        case "gbc": return .gbc
        case "gba": return .gba
        case "sfc", "smc": return .snes
        // ".bin" is ambiguous (many systems use it): only claimed above, by the "SEGA" header.
        case "md", "gen", "smd": return .md
        case "nds": return .ds
        default: return nil
        }
    }

    /// Nintendo DS cartridge header: ARM9 and ARM7 binaries (offset >= 0x200, non-empty) inside the
    /// file, plausible load addresses and a correct header CRC-16 at 0x15E.
    static func dsHeaderValid(_ rom: Data) -> Bool {
        guard rom.count >= 0x1000 else { return false }
        let b = rom.startIndex
        func u32(_ o: Int) -> UInt32 {
            UInt32(rom[b + o]) | UInt32(rom[b + o + 1]) << 8 | UInt32(rom[b + o + 2]) << 16 | UInt32(rom[b + o + 3]) << 24
        }
        let arm9Off = u32(0x20), arm9RAM = u32(0x28), arm9Size = u32(0x2C)
        let arm7Off = u32(0x30), arm7RAM = u32(0x38), arm7Size = u32(0x3C)
        guard arm9Off >= 0x200, arm7Off >= 0x200, arm9Size > 0, arm7Size > 0,
              UInt64(arm9Off) + UInt64(arm9Size) <= UInt64(rom.count),
              UInt64(arm7Off) + UInt64(arm7Size) <= UInt64(rom.count),
              (0x0200_0000..<0x0300_0000).contains(arm9RAM),
              (0x0200_0000..<0x0400_0000).contains(arm7RAM) else { return false }
        var crc: UInt16 = 0xFFFF
        for i in 0..<0x15E {
            crc ^= UInt16(rom[b + i])
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        }
        return crc == UInt16(rom[b + 0x15E]) | UInt16(rom[b + 0x15F]) << 8
    }

    /// SNES internal header: checksum + complement == $FFFF at $7FDC (LoROM) or $FFDC (HiROM),
    /// with or without a 512-byte copier header, plus a plausible map mode byte.
    static func snesHeaderValid(_ rom: Data) -> Bool {
        let skip = rom.count % 0x8000 == 512 ? 512 : 0
        for header in [0x7FB0, 0xFFB0] {
            let base = rom.startIndex + skip + header
            guard rom.count >= skip + header + 0x50 else { continue }
            let complement = UInt16(rom[base + 0x2C]) | UInt16(rom[base + 0x2D]) << 8
            let checksum = UInt16(rom[base + 0x2E]) | UInt16(rom[base + 0x2F]) << 8
            let mapMode = rom[base + 0x25] & 0xEF
            let reset = UInt16(rom[base + 0x4C]) | UInt16(rom[base + 0x4D]) << 8
            if checksum ^ complement == 0xFFFF, (0x20...0x2A).contains(mapMode), reset >= 0x8000 { return true }
        }
        return false
    }
}
