import CoreKit
import Observation
import UIKit

/// One control on the touch controller, in the controller view's coordinate space.
struct Control: Identifiable, Hashable {
    enum Kind: Hashable {
        case dpad
        case face(InputState, String, Tone)
        case pill(InputState, String)
        case shoulder(InputState, String)
        case menu
        case fastForward
        case rewind
    }

    enum Tone: Hashable { case ember, sand }

    var kind: Kind
    var frame: CGRect

    var id: String {
        switch kind {
        case .dpad: "dpad"
        case .face(let s, _, _): "face\(s.rawValue)"
        case .pill(let s, _): "pill\(s.rawValue)"
        case .shoulder(let s, _): "shoulder\(s.rawValue)"
        case .menu: "menu"
        case .fastForward: "ff"
        case .rewind: "rewind"
        }
    }

    /// The area that accepts a touch: generous, because thumbs miss.
    var hitFrame: CGRect {
        switch kind {
        case .dpad: frame.insetBy(dx: -frame.width * 0.3, dy: -frame.height * 0.3)
        case .face: frame.insetBy(dx: -frame.width * 0.28, dy: -frame.height * 0.28)
        case .pill: frame.insetBy(dx: -8, dy: -12)
        case .shoulder: frame.insetBy(dx: -10, dy: -10)
        case .menu, .fastForward, .rewind: frame.insetBy(dx: -10, dy: -10)
        }
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

    func update(pressed newPressed: InputState, dpad: CGVector, menu: Bool, fastForward: Bool, rewind: Bool) {
        let added = newPressed.subtracting(pressed)
        let dpadBits: InputState = [.up, .down, .left, .right]
        if hapticsEnabled {
            if !added.subtracting(dpadBits).isEmpty { impact.impactOccurred(intensity: 0.75) }
            else if !added.intersection(dpadBits).isEmpty { soft.impactOccurred(intensity: 0.55) }
            if menu && !menuDown || fastForward && !fastForwardDown || rewind && !rewindDown {
                soft.impactOccurred(intensity: 0.5)
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

/// Places the controls for each surface. Sizes come from the space actually available.
///
/// Face buttons follow the system: two for NES and Game Boy (B A), two plus shoulders for GBA,
/// a four-button diamond plus shoulders for SNES (Y X B A, in our own ember and sand, never the
/// console's colours), and a row of three (A B C), or two rows of three when the six-button pad
/// is chosen, for the Mega Drive.
enum ControllerLayout {
    static func hasShoulders(_ system: SystemID) -> Bool { system == .gba || system == .snes }

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
            let gap = d * 1.08
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
            return [
                button(.b, "B", .sand, c.x - d * 0.61, c.y + d * 0.42),
                button(.a, "A", .ember, c.x + d * 0.61, c.y - d * 0.42),
            ]
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
    static func deck(_ size: CGSize, system: SystemID, sixButton: Bool = false) -> [Control] {
        let w = size.width, h = size.height
        let shoulderSpace: CGFloat = hasShoulders(system) ? 40 : 0
        let usableH = h - shoulderSpace
        let unit = min(w / 2.6, usableH * 0.62)
        let dpad = unit * 0.92
        let face = unit * (system == .snes || system == .md ? 0.36 : 0.40)
        let midY = shoulderSpace + usableH * 0.50
        var c: [Control] = shoulders(system, width: w, top: 4)
        c.append(Control(kind: .dpad, frame: CGRect(x: w * 0.23 - dpad / 2, y: midY - dpad / 2, width: dpad, height: dpad)))
        let cx = system == .snes || system == .md ? w * 0.78 : w * 0.77
        c += faceCluster(system, centre: CGPoint(x: cx, y: midY), diameter: face, sixButton: sixButton)
        let pillW = min(58, w * 0.13), pillH: CGFloat = 34
        let pillY = min(h - pillH - 22, midY + dpad * 0.5)
        let selectLabel = system == .md ? "MODE" : "SELECT"
        if system != .md || sixButton {
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
    static func bookLeft(_ size: CGSize, system: SystemID, sixButton: Bool = false) -> [Control] {
        let w = size.width, h = size.height
        let dpad = min(w * 0.52, h * 0.85)
        let pillW: CGFloat = 60
        var c = [Control(kind: .dpad, frame: CGRect(x: w * 0.42 - dpad / 2, y: h * 0.5 - dpad / 2, width: dpad, height: dpad))]
        if system != .md || sixButton {
            c.append(Control(kind: .pill(.select, system == .md ? "MODE" : "SELECT"),
                             frame: CGRect(x: w - pillW - 18, y: h * 0.5 - 10, width: pillW, height: 20)))
        }
        if hasShoulders(system) {
            c.append(Control(kind: .shoulder(.l, "L"), frame: CGRect(x: 10, y: 4, width: min(120, w * 0.3), height: 28)))
        }
        return c
    }

    /// Book pose, right page: face buttons and Start (and R).
    static func bookRight(_ size: CGSize, system: SystemID, sixButton: Bool = false) -> [Control] {
        let w = size.width, h = size.height
        let face = min(w * 0.2, h * 0.34)
        var c = [Control(kind: .pill(.start, "START"), frame: CGRect(x: 18, y: h * 0.5 - 10, width: 60, height: 20))]
        c += faceCluster(system, centre: CGPoint(x: w * 0.62, y: h * 0.52), diameter: face, sixButton: sixButton)
        if hasShoulders(system) {
            let tw = min(120, w * 0.3)
            c.append(Control(kind: .shoulder(.r, "R"), frame: CGRect(x: w - tw - 10, y: 4, width: tw, height: 28)))
        }
        return c
    }

    /// Landscape phone: controls in the margins either side of the game.
    static func overlay(_ size: CGSize, gameRect: CGRect, system: SystemID, sixButton: Bool = false) -> [Control] {
        let w = size.width, h = size.height
        let side = max(120, gameRect.minX)
        let dpad = min(side * 0.82, h * 0.42)
        let face = dpad * (system == .snes || system == .md ? 0.36 : 0.42)
        var c: [Control] = []
        c.append(Control(kind: .dpad, frame: CGRect(x: side * 0.5 - dpad / 2, y: h * 0.58 - dpad / 2, width: dpad, height: dpad)))
        let rx = w - side * 0.5
        c += faceCluster(system, centre: CGPoint(x: rx, y: h * 0.6), diameter: face, sixButton: sixButton)
        if system != .md || sixButton {
            c.append(Control(kind: .pill(.select, system == .md ? "MODE" : "SELECT"),
                             frame: CGRect(x: side * 0.5 - 30, y: h - 40, width: 60, height: 20)))
        }
        c.append(Control(kind: .pill(.start, "START"), frame: CGRect(x: rx - 30, y: h - 40, width: 60, height: 20)))
        if hasShoulders(system) {
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
