import Foundation

/// The systems the app knows about. Plain-text names only (no logos, no trade dress).
public enum SystemID: String, Codable, Sendable, CaseIterable, Identifiable {
    case nes
    case gb
    case gbc

    public var id: String { rawValue }

    /// The factual, plain-text system name shown in section headers.
    public var displayName: String {
        switch self {
        case .nes: "NES"
        case .gb: "Game Boy"
        case .gbc: "Game Boy Color"
        }
    }

    public var fileExtensions: [String] {
        switch self {
        case .nes: ["nes"]
        case .gb: ["gb"]
        case .gbc: ["gbc"]
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
    /// BGRA8 pixels (as little-endian 0xAARRGGBB words), `videoSize`, owned by the core.
    var framebuffer: UnsafeBufferPointer<UInt32> { get }
    /// Moves every sample produced since the last call into `ring`.
    func drainAudio(into ring: AudioRing)
    /// Battery-backed cartridge RAM, or nil if the cartridge has none.
    var batteryRAM: Data? { get }
    func saveState() -> Data
    func loadState(_ data: Data) throws
}

/// Identifies a file's system. (Building the core is the app's job: it imports each core module.)
public enum CoreFactory {
    /// Detects the system from the file's header, falling back to its extension.
    public static func detect(rom: Data, fileExtension: String) -> SystemID? {
        if rom.count >= 16, rom[rom.startIndex] == 0x4E, rom[rom.startIndex + 1] == 0x45,
           rom[rom.startIndex + 2] == 0x53, rom[rom.startIndex + 3] == 0x1A {
            return .nes
        }
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
        default: return nil
        }
    }
}
