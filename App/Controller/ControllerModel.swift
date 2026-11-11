import CoreKit
import Observation
import UIKit


/// One control on the touch controller, in the controller view's coordinate space.
/// Codable so layouts can be saved, exported and shared (frames are stored in unit space).
struct Control: Identifiable, Hashable, Codable {
    enum Kind: Hashable, Codable {
        case dpad
        case face(InputState, String, Tone)
        case pill(InputState, String)
        case shoulder(InputState, String)
        /// A zone that presses several buttons at once (A+B, a whole row on the arcade layout).
        case combo(InputState, String)
        case menu
        case fastForward
        case rewind
    }

    enum Tone: Hashable, Codable { case ember, sand }

    var kind: Kind
    var frame: CGRect
    var opacity: Double = 1
    /// Haptic strength on press, 0 = off.
    var haptic: Double = 0.6
    /// Auto-fire: while held, the button is pulsed at the layout's auto-fire rate.
    var autoFire = false
    /// Hidden by the player in the editor (e.g. a combo zone they don't want). nil = shown.
    var hidden: Bool?
    var isHidden: Bool { hidden ?? false }

    init(kind: Kind, frame: CGRect, opacity: Double = 1, haptic: Double? = nil, autoFire: Bool = false) {
        self.kind = kind
        self.frame = frame
        self.opacity = opacity
        if let haptic {
            self.haptic = haptic
        } else {
            switch kind {
            case .dpad: self.haptic = 0.4
            case .menu, .fastForward, .rewind, .pill: self.haptic = 0.45
            default: self.haptic = 0.6
            }
        }
        self.autoFire = autoFire
    }

    /// The buttons this control presses (empty for the D-pad and the app keys).
    var buttons: InputState {
        switch kind {
        case .face(let s, _, _), .pill(let s, _), .shoulder(let s, _), .combo(let s, _): s
        default: []
        }
    }

    var id: String {
        switch kind {
        case .dpad: "dpad"
        case .face(let s, _, _): "face\(s.rawValue)"
        case .pill(let s, _): "pill\(s.rawValue)"
        case .shoulder(let s, _): "shoulder\(s.rawValue)"
        case .combo(let s, _): "combo\(s.rawValue)"
        case .menu: "menu"
        case .fastForward: "ff"
        case .rewind: "rewind"
        }
    }

    /// The area that accepts a touch: generous, because thumbs miss, and never under 44 x 44 pt.
    var hitFrame: CGRect {
        var r: CGRect
        switch kind {
        case .dpad: r = frame.insetBy(dx: -frame.width * 0.3, dy: -frame.height * 0.3)
        case .face: r = frame.insetBy(dx: -frame.width * 0.28, dy: -frame.height * 0.28)
        case .combo: return frame   // sits between buttons: no expansion into them
        case .pill: r = frame.insetBy(dx: -8, dy: -12)
        case .shoulder, .menu, .fastForward, .rewind: r = frame.insetBy(dx: -10, dy: -10)
        }
        if r.width < 44 { r = r.insetBy(dx: (r.width - 44) / 2, dy: 0) }
        if r.height < 44 { r = r.insetBy(dx: 0, dy: (r.height - 44) / 2) }
        return r
    }

    /// The control with its frame mapped from points in `size` to unit space, or back.
    func toUnit(_ size: CGSize) -> Control {
        var c = self
        c.frame = CGRect(x: frame.minX / size.width, y: frame.minY / size.height,
                         width: frame.width / size.width, height: frame.height / size.height)
        return c
    }

    func fromUnit(_ size: CGSize) -> Control {
        var c = self
        c.frame = CGRect(x: frame.minX * size.width, y: frame.minY * size.height,
                         width: frame.width * size.width, height: frame.height * size.height)
        return c
    }
}

/// What the touch controller is pressing right now. Drives both the drawing and the latch.
@MainActor
@Observable
final class ControllerModel {
    private(set) var pressed: InputState = []
    /// Unit vector of the D-pad press (for the tilt), zero when released.
    private(set) var dpadVector: CGVector = .zero
    private(set) var menuDown = false
    private(set) var fastForwardDown = false
    private(set) var rewindDown = false
    var hapticsEnabled = true
    /// From the layout in use: diagonal sector width, D-pad dead zone, per-button haptics.
    private(set) var settings = ControlSettings()
    @ObservationIgnored private var hapticByButton: [UInt32: Double] = [:]
    @ObservationIgnored private var dpadHaptic = 0.4
    @ObservationIgnored private var keyHaptic = 0.45
    @ObservationIgnored private var appliedSignature = ""
    #if DEBUG
    /// Every button the touch layer has pressed this session (UI tests read it).
    private(set) var everPressed: InputState = []
    #endif

    @ObservationIgnored weak var latch: InputLatch?
    @ObservationIgnored var onMenu: (() -> Void)?
    @ObservationIgnored var onFastForward: ((Bool) -> Void)?
    @ObservationIgnored var onRewind: ((Bool) -> Void)?
    @ObservationIgnored private let impact = UIImpactFeedbackGenerator(style: .rigid)
    @ObservationIgnored private let soft = UIImpactFeedbackGenerator(style: .soft)

    /// Takes on a layout's settings: haptic strengths, auto-fire buttons and rate, D-pad tuning.
    func apply(controls: [Control], settings newSettings: ControlSettings) {
        let signature = "\(newSettings)" + controls.map { "\($0.id):\($0.haptic):\($0.autoFire)" }.joined()
        guard signature != appliedSignature else { return }
        appliedSignature = signature
        let newSettings = newSettings.sanitised
        if settings != newSettings { settings = newSettings }
        var table: [UInt32: Double] = [:]
        var fire: InputState = []
        for c in controls where !c.isHidden {
            switch c.kind {
            case .dpad: dpadHaptic = c.haptic
            case .menu, .fastForward, .rewind: keyHaptic = c.haptic
            default:
                for bit in 0..<12 where c.buttons.contains(InputState(rawValue: 1 << bit)) {
                    table[1 << UInt32(bit)] = max(table[1 << UInt32(bit)] ?? 0, c.haptic)
                }
                if c.autoFire { fire.formUnion(c.buttons) }
            }
        }
        hapticByButton = table
        latch?.autoFire.store(fire.rawValue, ordering: .relaxed)
        latch?.autoFireHalfPeriod.store(max(1, Int((60 / (2 * newSettings.autoFireHz)).rounded())), ordering: .relaxed)
    }

    func update(pressed newPressed: InputState, dpad: CGVector, menu: Bool, fastForward: Bool, rewind: Bool) {
        let added = newPressed.subtracting(pressed)
        let dpadBits: InputState = [.up, .down, .left, .right]
        if hapticsEnabled && settings.hapticLevel > 0 {
            let buttons = added.subtracting(dpadBits)
            var strength = 0.0
            for bit in 0..<12 where buttons.contains(InputState(rawValue: 1 << bit)) {
                strength = max(strength, hapticByButton[1 << UInt32(bit)] ?? 0.6)
            }
            if strength > 0 {
                impact.impactOccurred(intensity: min(1, strength * settings.hapticLevel))
            } else if !added.intersection(dpadBits).isEmpty && dpadHaptic > 0 {
                soft.impactOccurred(intensity: min(1, dpadHaptic * settings.hapticLevel))
            }
            if (menu && !menuDown || fastForward && !fastForwardDown || rewind && !rewindDown) && keyHaptic > 0 {
                soft.impactOccurred(intensity: min(1, keyHaptic * settings.hapticLevel))
            }
        }
        if newPressed != pressed { pressed = newPressed }
        #if DEBUG
        if !newPressed.isSubset(of: everPressed) { everPressed.formUnion(newPressed) }
        #endif
        if dpad != dpadVector { dpadVector = dpad }
        latch?.touch.store(newPressed.rawValue, ordering: .relaxed)
        if menuDown && !menu { onMenu?() }   // fires on release
        if fastForward != fastForwardDown { onFastForward?(fastForward) }
        if rewind != rewindDown { onRewind?(rewind) }
        menuDown = menu
        fastForwardDown = fastForward
        rewindDown = rewind
    }

    /// Nothing pressed: pose changes, backgrounding, a controller connecting.
    func releaseAll() {
        if fastForwardDown { onFastForward?(false) }
        if rewindDown { onRewind?(false) }
        pressed = []
        dpadVector = .zero
        menuDown = false
        fastForwardDown = false
        rewindDown = false
        latch?.touch.store(0, ordering: .relaxed)
    }
}

/// Tuning that belongs to a layout (saved with it).
struct ControlSettings: Codable, Hashable {
    /// Width of each diagonal sector in degrees: 0 = four-way only.
    var diagonalDegrees: Double = 36
    /// Fraction of the D-pad radius that does nothing.
    var deadZone: Double = 0.15
    var autoFireHz: Double = 10
    /// Master haptic strength multiplier (0 = off).
    var hapticLevel: Double = 1

    /// Values from a file are clamped before use (a shared layout can't crash or break the pad).
    var sanitised: ControlSettings {
        var s = self
        s.diagonalDegrees = diagonalDegrees.isFinite ? min(60, max(0, diagonalDegrees)) : 36
        s.deadZone = deadZone.isFinite ? min(0.5, max(0.05, deadZone)) : 0.15
        s.autoFireHz = autoFireHz.isFinite ? min(30, max(2, autoFireHz)) : 10
        s.hapticLevel = hapticLevel.isFinite ? min(1, max(0, hapticLevel)) : 1
        return s
    }
}

/// Places the controls for each surface. Sizes come from the space actually available.
///
/// Face buttons follow the system: two for NES and Game Boy (B A), two plus shoulders for GBA,
/// a four-button diamond plus shoulders for SNES (Y X B A, in our own ember and sand, never the
/// console's colours), and a row of three (A B C), or two rows of three when the six-button pad
/// is chosen, for the Mega Drive.
/// Built-in starting points for a layout.
enum LayoutPreset: String, Codable, CaseIterable, Identifiable {
    case standard
    /// Two rows of three (light / medium / heavy over the same), for fighting games.
    case arcade

    var id: String { rawValue }
    var title: String { self == .standard ? "Standard" : "6-Button Arcade" }

    static func available(for system: SystemID) -> [LayoutPreset] {
        system == .snes || system == .md ? [.standard, .arcade] : [.standard]
    }
}

enum ControllerLayout {
    static func hasShoulders(_ system: SystemID, preset: LayoutPreset = .standard) -> Bool {
        preset == .standard && (system == .gba || system == .snes)
    }

    /// The arcade panel: two staggered, gently arched rows of three, plus a "whole row" zone at
    /// the end of each row. SNES: Y X L over B A R. Mega Drive six-button: X Y Z over A B C.
    static func arcadeCluster(_ system: SystemID, centre c: CGPoint, diameter d: CGFloat) -> [Control] {
        let top: [(InputState, String)] = system == .md ? [(.x, "X"), (.l, "Y"), (.r, "Z")] : [(.y, "Y"), (.x, "X"), (.l, "L")]
        let low: [(InputState, String)] = system == .md ? [(.y, "A"), (.b, "B"), (.a, "C")] : [(.b, "B"), (.a, "A"), (.r, "R")]
        let spacing = d * 1.12
        var list: [Control] = []
        func row(_ items: [(InputState, String)], y: CGFloat, dx: CGFloat, tone: Control.Tone) {
            for (i, item) in items.enumerated() {
                let x = c.x + dx + CGFloat(i - 1) * spacing
                // Arched: the middle button sits a little higher; the row rises to the right.
                let yy = y - (i == 1 ? d * 0.14 : 0) - CGFloat(i) * d * 0.1
                list.append(Control(kind: .face(item.0, item.1, tone),
                                    frame: CGRect(x: x - d / 2, y: yy - d / 2, width: d, height: d)))
            }
            let all = items.reduce(InputState()) { $0.union($1.0) }
            let zx = c.x + dx + spacing * 1.62, zy = y - d * 0.3
            list.append(Control(kind: .combo(all, "x3"), frame: CGRect(x: zx - d * 0.24, y: zy - d * 0.42, width: d * 0.48, height: d * 0.84)))
        }
        row(top, y: c.y - d * 0.58, dx: d * 0.1, tone: .sand)
        row(low, y: c.y + d * 0.62, dx: -d * 0.18, tone: .ember)
        return list
    }

    /// A small zone between B and A that presses both (two-button systems).
    static func comboAB(between b: Control, and a: Control) -> Control {
        let mid = CGPoint(x: (b.frame.midX + a.frame.midX) / 2, y: (b.frame.midY + a.frame.midY) / 2)
        let w = b.frame.width * 0.42
        return Control(kind: .combo([.a, .b], "AB"), frame: CGRect(x: mid.x - w / 2, y: mid.y - w / 2, width: w, height: w))
    }

    /// Face buttons centred on `c`, button diameter `d`.
    static func faceCluster(_ system: SystemID, centre c: CGPoint, diameter d: CGFloat, sixButton: Bool) -> [Control] {
        func button(_ s: InputState, _ label: String, _ tone: Control.Tone, _ x: CGFloat, _ y: CGFloat, scale: CGFloat = 1) -> Control {
            let dd = d * scale
            return Control(kind: .face(s, label, tone), frame: CGRect(x: x - dd / 2, y: y - dd / 2, width: dd, height: dd))
        }
        switch system {
        case .snes:
            let r = d * 0.78
            return [
                button(.x, "X", .sand, c.x, c.y - r, scale: 0.86),
                button(.y, "Y", .sand, c.x - r, c.y, scale: 0.86),
                button(.a, "A", .ember, c.x + r, c.y, scale: 0.86),
                button(.b, "B", .ember, c.x, c.y + r, scale: 0.86),
            ]
        case .md:
            let gap = d * (sixButton ? 0.98 : 1.08)
            var list = [
                button(.y, "A", .sand, c.x - gap, c.y + d * 0.28, scale: 0.84),
                button(.b, "B", .ember, c.x, c.y + d * 0.06, scale: 0.84),
                button(.a, "C", .ember, c.x + gap, c.y - d * 0.16, scale: 0.84),
            ]
            if sixButton {
                list = list.map { var b = $0; b.frame = b.frame.offsetBy(dx: 0, dy: d * 0.42); return b }
                list += [
                    button(.x, "X", .sand, c.x - gap, c.y - d * 0.58, scale: 0.62),
                    button(.l, "Y", .sand, c.x, c.y - d * 0.8, scale: 0.62),
                    button(.r, "Z", .sand, c.x + gap, c.y - d * 1.02, scale: 0.62),
                ]
            }
            return list
        default:
            let b = button(.b, "B", .sand, c.x - d * 0.61, c.y + d * 0.42)
            let a = button(.a, "A", .ember, c.x + d * 0.61, c.y - d * 0.42)
            return [b, a, comboAB(between: b, and: a)]
        }
    }

    static func shoulders(_ system: SystemID, width w: CGFloat, top: CGFloat, inset: CGFloat = 12) -> [Control] {
        guard hasShoulders(system) else { return [] }
        let tw = min(132, w * 0.28), th: CGFloat = 30
        return [
            Control(kind: .shoulder(.l, "L"), frame: CGRect(x: inset, y: top, width: tw, height: th)),
            Control(kind: .shoulder(.r, "R"), frame: CGRect(x: w - inset - tw, y: top, width: tw, height: th)),
        ]
    }

    /// The full handheld controller (Duo table pose bottom half, or below the game in portrait).
    static func deck(_ size: CGSize, system: SystemID, sixButton: Bool = false, preset: LayoutPreset = .standard) -> [Control] {
        let w = size.width, h = size.height
        let shoulderSpace: CGFloat = hasShoulders(system, preset: preset) ? 40 : 0
        let usableH = h - shoulderSpace
        let unit = min(w / 2.6, usableH * 0.62)
        let dpad = unit * 0.92
        let face = unit * (system == .snes || system == .md ? 0.36 : 0.40)
        let midY = shoulderSpace + usableH * 0.50
        var c: [Control] = hasShoulders(system, preset: preset) ? shoulders(system, width: w, top: 4) : []
        c.append(Control(kind: .dpad, frame: CGRect(x: w * 0.23 - dpad / 2, y: midY - dpad / 2, width: dpad, height: dpad)))
        if preset == .arcade {
            let d = min(unit * 0.34, w * 0.11)
            c += arcadeCluster(system, centre: CGPoint(x: w * 0.74, y: midY + d * 0.25), diameter: d)
        } else {
            let cx = system == .md ? w * 0.80 : (system == .snes ? w * 0.78 : w * 0.77)
            // The six-button pad's top row needs room above the cluster: push it down a little.
            let cy = system == .md && sixButton ? midY + face * 0.12 : midY
            c += faceCluster(system, centre: CGPoint(x: cx, y: cy), diameter: face, sixButton: sixButton)
        }
        let pillW = min(58, w * 0.13), pillH: CGFloat = 34
        let pillY = min(h - pillH - 22, midY + dpad * 0.5)
        let selectLabel = system == .md ? "MODE" : "SELECT"
        if system != .md || sixButton || preset == .arcade {
            c.append(Control(kind: .pill(.select, selectLabel), frame: CGRect(x: w * 0.5 - pillW - 10, y: pillY, width: pillW, height: pillH)))
        }
        c.append(Control(kind: .pill(.start, "START"), frame: CGRect(x: w * 0.5 + 10, y: pillY, width: pillW, height: pillH)))
        let key: CGFloat = min(38, h * 0.14)
        let keyY = max(shoulderSpace + 8, midY - dpad * 0.5 - 4)
        c.append(Control(kind: .rewind, frame: CGRect(x: w * 0.5 - key * 1.9, y: keyY, width: key, height: key)))
        c.append(Control(kind: .menu, frame: CGRect(x: w * 0.5 - key / 2, y: keyY, width: key, height: key)))
        c.append(Control(kind: .fastForward, frame: CGRect(x: w * 0.5 + key * 0.9, y: keyY, width: key, height: key)))
        return c
    }

    /// Book pose, left page: the D-pad under the game (and L).
    static func bookLeft(_ size: CGSize, system: SystemID, sixButton: Bool = false, preset: LayoutPreset = .standard) -> [Control] {
        let w = size.width, h = size.height
        let dpad = min(w * 0.52, h * 0.85)
        let pillW: CGFloat = 60
        var c = [Control(kind: .dpad, frame: CGRect(x: w * 0.42 - dpad / 2, y: h * 0.5 - dpad / 2, width: dpad, height: dpad))]
        if system != .md || sixButton {
            c.append(Control(kind: .pill(.select, system == .md ? "MODE" : "SELECT"),
                             frame: CGRect(x: w - pillW - 18, y: h * 0.5 - 10, width: pillW, height: 20)))
        }
        if hasShoulders(system, preset: preset) {
            c.append(Control(kind: .shoulder(.l, "L"), frame: CGRect(x: 10, y: 4, width: min(120, w * 0.3), height: 28)))
        }
        return c
    }

    /// Book pose, right page: face buttons and Start (and R).
    static func bookRight(_ size: CGSize, system: SystemID, sixButton: Bool = false, preset: LayoutPreset = .standard) -> [Control] {
        let w = size.width, h = size.height
        let face = min(w * 0.2, h * 0.34)
        var c = [Control(kind: .pill(.start, "START"), frame: CGRect(x: 18, y: h * 0.5 - 10, width: 60, height: 20))]
        if preset == .arcade {
            c += arcadeCluster(system, centre: CGPoint(x: w * 0.56, y: h * 0.52), diameter: min(w * 0.17, h * 0.3))
        } else {
            c += faceCluster(system, centre: CGPoint(x: w * 0.62, y: h * 0.52), diameter: face, sixButton: sixButton)
        }
        if hasShoulders(system, preset: preset) {
            let tw = min(120, w * 0.3)
            c.append(Control(kind: .shoulder(.r, "R"), frame: CGRect(x: w - tw - 10, y: 4, width: tw, height: 28)))
        }
        return c
    }

    /// Landscape phone: controls in the margins either side of the game.
    static func overlay(_ size: CGSize, gameRect: CGRect, system: SystemID, sixButton: Bool = false,
                        preset: LayoutPreset = .standard) -> [Control] {
        let w = size.width, h = size.height
        let side = max(120, gameRect.minX)
        let dpad = min(side * 0.82, h * 0.42)
        let face = dpad * (system == .snes || system == .md ? 0.36 : 0.42)
        var c: [Control] = []
        c.append(Control(kind: .dpad, frame: CGRect(x: side * 0.5 - dpad / 2, y: h * 0.58 - dpad / 2, width: dpad, height: dpad)))
        let rx = w - side * 0.5
        if preset == .arcade {
            c += arcadeCluster(system, centre: CGPoint(x: rx - side * 0.04, y: h * 0.58), diameter: min(side * 0.24, h * 0.16))
        } else {
            c += faceCluster(system, centre: CGPoint(x: rx, y: h * 0.6), diameter: face, sixButton: sixButton)
        }
        if system != .md || sixButton {
            c.append(Control(kind: .pill(.select, system == .md ? "MODE" : "SELECT"),
                             frame: CGRect(x: side * 0.5 - 30, y: h - 40, width: 60, height: 20)))
        }
        c.append(Control(kind: .pill(.start, "START"), frame: CGRect(x: rx - 30, y: h - 40, width: 60, height: 20)))
        if hasShoulders(system, preset: preset) {
            let tw = min(110, side * 0.8)
            c.append(Control(kind: .shoulder(.l, "L"), frame: CGRect(x: side * 0.5 - tw / 2, y: 60, width: tw, height: 28)))
            c.append(Control(kind: .shoulder(.r, "R"), frame: CGRect(x: rx - tw / 2, y: 60, width: tw, height: 28)))
        }
        c.append(Control(kind: .menu, frame: CGRect(x: side * 0.5 - 17, y: 18, width: 34, height: 34)))
        c.append(Control(kind: .fastForward, frame: CGRect(x: rx + 4, y: 18, width: 34, height: 34)))
        c.append(Control(kind: .rewind, frame: CGRect(x: rx - 38, y: 18, width: 34, height: 34)))
        return c
    }
}
