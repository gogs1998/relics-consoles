import Foundation

// Pure input mapping: physical controller / keyboard state → emulated buttons + app hotkeys.
// No GameController import; the app feeds in what GCExtendedGamepad / GCKeyboard report.

extension InputState: Codable {}

/// The digital inputs of an extended gamepad. Thumbstick directions arrive separately, as an
/// analog vector (see `InputMapper.resolve`).
public enum PhysicalInput: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case buttonA, buttonB, buttonX, buttonY
    case leftShoulder, rightShoulder, leftTrigger, rightTrigger
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case leftThumbstickButton, rightThumbstickButton
    case buttonMenu, buttonOptions, buttonHome
}

/// App actions a controller or keyboard can trigger.
public enum Hotkey: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case menu, saveState, loadState, fastForward, rewind
}

/// `trigger` (optionally with `modifier` held) fires `hotkey`.
public struct HotkeyBinding: Codable, Hashable, Sendable {
    /// Must be held for the binding to fire; nil = the trigger alone.
    public var modifier: PhysicalInput?
    public var trigger: PhysicalInput
    public var hotkey: Hotkey

    public init(modifier: PhysicalInput? = nil, trigger: PhysicalInput, hotkey: Hotkey) {
        self.modifier = modifier
        self.trigger = trigger
        self.hotkey = hotkey
    }
}

/// One controller's mapping for one system.
public struct ControllerMapping: Codable, Hashable, Sendable {
    /// Each physical input → zero or more emulated buttons (absent = unmapped).
    public var buttons: [PhysicalInput: InputState]
    /// Hotkeys take precedence: while a binding is active its trigger (and modifier) press no buttons.
    public var hotkeys: [HotkeyBinding]
    /// The left thumbstick also drives the d-pad directions.
    public var stickAsDpad: Bool
    /// Stick magnitude below this is ignored. Clamped to 0...0.9 when used.
    public var stickDeadZone: Double
    /// Angular width of each diagonal sector (0 = 4-way only, 45 = eight equal sectors, 90 = all
    /// diagonal except the exact axes). Clamped to 0...90 when used.
    public var stickDiagonalDegrees: Double

    public static let defaultDeadZone = 0.35
    public static let defaultDiagonalDegrees = 45.0

    public init(buttons: [PhysicalInput: InputState], hotkeys: [HotkeyBinding], stickAsDpad: Bool = true,
                stickDeadZone: Double = ControllerMapping.defaultDeadZone,
                stickDiagonalDegrees: Double = ControllerMapping.defaultDiagonalDegrees) {
        self.buttons = buttons
        self.hotkeys = hotkeys
        self.stickAsDpad = stickAsDpad
        self.stickDeadZone = stickDeadZone
        self.stickDiagonalDegrees = stickDiagonalDegrees
    }

    // Tolerant decoding: a mapping saved by an older build (missing stick fields) still loads.
    private enum CodingKeys: String, CodingKey {
        case buttons, hotkeys, stickAsDpad, stickDeadZone, stickDiagonalDegrees
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        buttons = try c.decodeIfPresent([PhysicalInput: InputState].self, forKey: .buttons) ?? [:]
        hotkeys = try c.decodeIfPresent([HotkeyBinding].self, forKey: .hotkeys) ?? []
        stickAsDpad = try c.decodeIfPresent(Bool.self, forKey: .stickAsDpad) ?? true
        stickDeadZone = try c.decodeIfPresent(Double.self, forKey: .stickDeadZone) ?? Self.defaultDeadZone
        stickDiagonalDegrees = try c.decodeIfPresent(Double.self, forKey: .stickDiagonalDegrees)
            ?? Self.defaultDiagonalDegrees
    }

    /// Maps `input` to `emulated` (empty = unmap it).
    public mutating func bind(_ input: PhysicalInput, to emulated: InputState) {
        buttons[input] = emulated.isEmpty ? nil : emulated
    }

    /// The physical inputs that press any of `emulated` (for labels in a remapping UI).
    public func inputs(pressing emulated: InputState) -> [PhysicalInput] {
        PhysicalInput.allCases.filter { !(buttons[$0] ?? []).isDisjoint(with: emulated) }
    }

    /// Positional defaults (face buttons by position, not by printed letter):
    /// - NES, GB, GBC: south (buttonA) = B, east (buttonB) = A, like the original pads' layout.
    /// - GBA: as above, shoulders = L / R.
    /// - SNES and DS: south = B, east = A, west (buttonX) = Y, north (buttonY) = X, shoulders = L / R.
    /// - Mega Drive 6-button: the three main buttons on the three easiest face buttons, west/south/east
    ///   = A/B/C (left to right, as on the pad's bottom row); the top row X/Y/Z on left shoulder /
    ///   north / right shoulder. In InputState terms (AresCore's MD mapping): A = .y, B = .b, C = .a,
    ///   X = .x, Y = .l, Z = .r.
    /// - Every system: d-pad = directions, menu = Start, options = Select (Mode on the Mega Drive).
    /// - Hotkeys: home alone = menu; options held + left/right shoulder = load/save state,
    ///   options + left/right trigger = rewind/fast-forward; triggers alone = rewind/fast-forward
    ///   (no default mapping uses the triggers for buttons).
    public static func defaults(for system: SystemID) -> ControllerMapping {
        var b: [PhysicalInput: InputState] = [
            .dpadUp: .up, .dpadDown: .down, .dpadLeft: .left, .dpadRight: .right,
            .buttonMenu: .start, .buttonOptions: .select,
        ]
        switch system {
        case .nes, .gb, .gbc:
            b[.buttonA] = .b; b[.buttonB] = .a
        case .gba:
            b[.buttonA] = .b; b[.buttonB] = .a
            b[.leftShoulder] = .l; b[.rightShoulder] = .r
        case .snes, .ds:
            b[.buttonA] = .b; b[.buttonB] = .a; b[.buttonX] = .y; b[.buttonY] = .x
            b[.leftShoulder] = .l; b[.rightShoulder] = .r
        case .md:
            b[.buttonX] = .y            // A
            b[.buttonA] = .b            // B
            b[.buttonB] = .a            // C
            b[.leftShoulder] = .x       // X
            b[.buttonY] = .l            // Y
            b[.rightShoulder] = .r      // Z
        }
        return ControllerMapping(buttons: b, hotkeys: defaultHotkeys(usesTriggers: b[.leftTrigger] != nil
                                                                        || b[.rightTrigger] != nil))
    }

    static func defaultHotkeys(usesTriggers: Bool) -> [HotkeyBinding] {
        var h: [HotkeyBinding] = [
            HotkeyBinding(trigger: .buttonHome, hotkey: .menu),
            // Home is often taken by the system on iOS, so Options + Menu also opens the menu.
            HotkeyBinding(modifier: .buttonOptions, trigger: .buttonMenu, hotkey: .menu),
            HotkeyBinding(modifier: .buttonOptions, trigger: .leftShoulder, hotkey: .loadState),
            HotkeyBinding(modifier: .buttonOptions, trigger: .rightShoulder, hotkey: .saveState),
            HotkeyBinding(modifier: .buttonOptions, trigger: .leftTrigger, hotkey: .rewind),
            HotkeyBinding(modifier: .buttonOptions, trigger: .rightTrigger, hotkey: .fastForward),
        ]
        if !usesTriggers {
            h.append(HotkeyBinding(trigger: .leftTrigger, hotkey: .rewind))
            h.append(HotkeyBinding(trigger: .rightTrigger, hotkey: .fastForward))
        }
        return h
    }
}

/// HID usage values (GCKeyCode raw values) for the keys the default keyboard mappings use.
public enum KeyCode {
    public static let a = 0x04, c = 0x06, d = 0x07, e = 0x08, q = 0x14, s = 0x16, v = 0x19, w = 0x1A
    public static let x = 0x1B, z = 0x1D
    public static let returnKey = 0x28, escape = 0x29, backspace = 0x2A, tab = 0x2B, space = 0x2C
    public static let f1 = 0x3A, f2 = 0x3B, f3 = 0x3C, f4 = 0x3D
    public static let rightArrow = 0x4F, leftArrow = 0x50, downArrow = 0x51, upArrow = 0x52
    public static let rightShift = 0xE5
}

/// A keyboard's mapping for one system: key code (HID usage) → emulated buttons or a hotkey.
public struct KeyboardMapping: Codable, Hashable, Sendable {
    public var buttons: [Int: InputState]
    /// Takes precedence over `buttons` for the same key.
    public var hotkeys: [Int: Hotkey]

    public init(buttons: [Int: InputState], hotkeys: [Int: Hotkey]) {
        self.buttons = buttons
        self.hotkeys = hotkeys
    }

    /// Maps `key` to `emulated` (empty = unmap it) and removes any hotkey on that key.
    public mutating func bind(key: Int, to emulated: InputState) {
        buttons[key] = emulated.isEmpty ? nil : emulated
        if !emulated.isEmpty { hotkeys[key] = nil }
    }

    /// Puts `hotkey` on `key` alone: clears the key's buttons and the hotkey's previous key(s).
    public mutating func bind(key: Int, to hotkey: Hotkey) {
        for (k, h) in hotkeys where h == hotkey { hotkeys[k] = nil }
        hotkeys[key] = hotkey
        buttons[key] = nil
    }

    /// Defaults: arrow keys = directions, Return = Start, right Shift = Select (Mode).
    /// Face buttons on the left hand, laid out like the pad:
    /// - NES, GB, GBC: Z = B, X = A.  GBA: plus Q / E = L / R.
    /// - SNES and DS: Z = B, X = A, A = Y, S = X, Q / E = L / R.
    /// - Mega Drive: Z X C = A B C, A S D = X Y Z (bottom and top rows).
    /// WASD is not a direction cluster by default: A and S (and D on the Mega Drive) are face buttons.
    /// Hotkeys: F1 save state, F4 load state, Tab fast-forward, Backspace rewind, Escape menu.
    public static func defaults(for system: SystemID) -> KeyboardMapping {
        var b: [Int: InputState] = [
            KeyCode.upArrow: .up, KeyCode.downArrow: .down, KeyCode.leftArrow: .left, KeyCode.rightArrow: .right,
            KeyCode.returnKey: .start, KeyCode.rightShift: .select,
        ]
        switch system {
        case .nes, .gb, .gbc:
            b[KeyCode.z] = .b; b[KeyCode.x] = .a
        case .gba:
            b[KeyCode.z] = .b; b[KeyCode.x] = .a; b[KeyCode.q] = .l; b[KeyCode.e] = .r
        case .snes, .ds:
            b[KeyCode.z] = .b; b[KeyCode.x] = .a; b[KeyCode.a] = .y; b[KeyCode.s] = .x
            b[KeyCode.q] = .l; b[KeyCode.e] = .r
        case .md:
            b[KeyCode.z] = .y; b[KeyCode.x] = .b; b[KeyCode.c] = .a      // A B C
            b[KeyCode.a] = .x; b[KeyCode.s] = .l; b[KeyCode.d] = .r      // X Y Z
        }
        let h: [Int: Hotkey] = [
            KeyCode.f1: .saveState, KeyCode.f4: .loadState, KeyCode.tab: .fastForward,
            KeyCode.backspace: .rewind, KeyCode.escape: .menu,
        ]
        return KeyboardMapping(buttons: b, hotkeys: h)
    }
}

public enum InputMapper {
    /// Resolves one controller's state.
    /// - Hotkeys: a binding is active while its trigger and (if any) modifier are held. A modifier
    ///   binding beats a trigger-alone binding on the same trigger. Every input used by an active
    ///   binding presses no emulated buttons while it stays active.
    /// - Stick (`x` right, `y` up, each -1...1): ignored when `stickAsDpad` is off or inside the dead
    ///   zone; otherwise one of eight directions, diagonals spanning `stickDiagonalDegrees`.
    /// - Opposite directions cancel (`InputState.sanitised`).
    public static func resolve(pressed: Set<PhysicalInput>, stick: (x: Double, y: Double),
                               mapping: ControllerMapping) -> (buttons: InputState, hotkeys: Set<Hotkey>) {
        var hotkeys = Set<Hotkey>()
        var consumed = Set<PhysicalInput>()
        // Triggers claimed by an active modifier combo; their trigger-alone bindings stay quiet.
        var comboTriggers = Set<PhysicalInput>()
        for binding in mapping.hotkeys {
            guard let modifier = binding.modifier, modifier != binding.trigger,
                  pressed.contains(binding.trigger), pressed.contains(modifier) else { continue }
            hotkeys.insert(binding.hotkey)
            consumed.insert(modifier)
            consumed.insert(binding.trigger)
            comboTriggers.insert(binding.trigger)
        }
        for binding in mapping.hotkeys where binding.modifier == nil || binding.modifier == binding.trigger {
            guard pressed.contains(binding.trigger), !comboTriggers.contains(binding.trigger) else { continue }
            hotkeys.insert(binding.hotkey)
            consumed.insert(binding.trigger)
        }

        var buttons: InputState = []
        for input in pressed where !consumed.contains(input) {
            if let mapped = mapping.buttons[input] { buttons.formUnion(mapped) }
        }
        if mapping.stickAsDpad {
            buttons.formUnion(stickDirections(x: stick.x, y: stick.y, deadZone: mapping.stickDeadZone,
                                              diagonalDegrees: mapping.stickDiagonalDegrees))
        }
        return (buttons.sanitised, hotkeys)
    }

    /// Resolves a keyboard's held keys (HID usages). A key with a hotkey presses no buttons.
    public static func resolve(keys: Set<Int>, mapping: KeyboardMapping) -> (buttons: InputState, hotkeys: Set<Hotkey>) {
        var hotkeys = Set<Hotkey>()
        var buttons: InputState = []
        for key in keys {
            if let hotkey = mapping.hotkeys[key] {
                hotkeys.insert(hotkey)
            } else if let mapped = mapping.buttons[key] {
                buttons.formUnion(mapped)
            }
        }
        return (buttons.sanitised, hotkeys)
    }

    /// An analog vector → up to two directions.
    public static func stickDirections(x: Double, y: Double, deadZone: Double, diagonalDegrees: Double) -> InputState {
        guard x.isFinite, y.isFinite else { return [] }
        let zone = min(max(deadZone, 0), 0.9)
        let magnitude = (x * x + y * y).squareRoot()
        guard magnitude > 0, magnitude >= zone else { return [] }
        var angle = atan2(y, x) * 180 / .pi           // 0 = right, 90 = up
        if angle < 0 { angle += 360 }
        let half = min(max(diagonalDegrees, 0), 90) / 2
        // Nearest diagonal centre (45, 135, 225, 315) and the distance to it.
        let diagonal = (angle / 90).rounded(.down) * 90 + 45
        if half > 0, abs(angle - diagonal) <= half {
            switch diagonal {
            case 45: return [.up, .right]
            case 135: return [.up, .left]
            case 225: return [.down, .left]
            default: return [.down, .right]
            }
        }
        switch ((angle + 45) / 90).rounded(.down).truncatingRemainder(dividingBy: 4) {
        case 0: return .right
        case 1: return .up
        case 2: return .left
        default: return .down
        }
    }
}
