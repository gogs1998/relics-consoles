import CoreKit
import Observation
import UIKit

/// One control on the touch controller, in the controller view's coordinate space.
struct Control: Identifiable, Hashable {
    enum Kind: Hashable {
        case dpad
        case face(InputState, String, Tone)
        case pill(InputState, String)
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
enum ControllerLayout {
    /// The full handheld controller (Duo table pose bottom half, or below the game in portrait).
    static func deck(_ size: CGSize, system: SystemID) -> [Control] {
        let w = size.width, h = size.height
        let unit = min(w / 2.6, h * 0.62)
        let dpad = unit * 0.92
        let face = unit * 0.40
        let midY = h * 0.50
        var c: [Control] = []
        c.append(Control(kind: .dpad, frame: CGRect(x: w * 0.23 - dpad / 2, y: midY - dpad / 2, width: dpad, height: dpad)))
        let bx = w * 0.70, by = midY + face * 0.42
        let ax = bx + face * 1.22, ay = midY - face * 0.42
        c.append(Control(kind: .face(.b, "B", .sand), frame: CGRect(x: bx - face / 2, y: by - face / 2, width: face, height: face)))
        c.append(Control(kind: .face(.a, "A", .ember), frame: CGRect(x: ax - face / 2, y: ay - face / 2, width: face, height: face)))
        let pillW = min(58, w * 0.13), pillH: CGFloat = 34
        let pillY = min(h - pillH - 22, midY + dpad * 0.5)
        c.append(Control(kind: .pill(.select, "SELECT"), frame: CGRect(x: w * 0.5 - pillW - 10, y: pillY, width: pillW, height: pillH)))
        c.append(Control(kind: .pill(.start, "START"), frame: CGRect(x: w * 0.5 + 10, y: pillY, width: pillW, height: pillH)))
        let key: CGFloat = min(38, h * 0.14)
        let keyY = max(12, midY - dpad * 0.5 - 4)
        c.append(Control(kind: .rewind, frame: CGRect(x: w * 0.5 - key * 1.9, y: keyY, width: key, height: key)))
        c.append(Control(kind: .menu, frame: CGRect(x: w * 0.5 - key / 2, y: keyY, width: key, height: key)))
        c.append(Control(kind: .fastForward, frame: CGRect(x: w * 0.5 + key * 0.9, y: keyY, width: key, height: key)))
        return c
    }

    /// Book pose, left page: the D-pad under the game.
    static func bookLeft(_ size: CGSize) -> [Control] {
        let w = size.width, h = size.height
        let dpad = min(w * 0.52, h * 0.85)
        let pillW: CGFloat = 60
        return [
            Control(kind: .dpad, frame: CGRect(x: w * 0.42 - dpad / 2, y: h * 0.5 - dpad / 2, width: dpad, height: dpad)),
            Control(kind: .pill(.select, "SELECT"), frame: CGRect(x: w - pillW - 18, y: h * 0.5 - 10, width: pillW, height: 20)),
        ]
    }

    /// Book pose, right page: face buttons and Start.
    static func bookRight(_ size: CGSize) -> [Control] {
        let w = size.width, h = size.height
        let face = min(w * 0.22, h * 0.36)
        let bx = w * 0.50, by = h * 0.5 + face * 0.42
        let ax = bx + face * 1.22, ay = h * 0.5 - face * 0.42
        return [
            Control(kind: .pill(.start, "START"), frame: CGRect(x: 18, y: h * 0.5 - 10, width: 60, height: 20)),
            Control(kind: .face(.b, "B", .sand), frame: CGRect(x: bx - face / 2, y: by - face / 2, width: face, height: face)),
            Control(kind: .face(.a, "A", .ember), frame: CGRect(x: ax - face / 2, y: ay - face / 2, width: face, height: face)),
        ]
    }

    /// Landscape phone: controls in the margins either side of the game.
    static func overlay(_ size: CGSize, gameRect: CGRect) -> [Control] {
        let w = size.width, h = size.height
        let side = max(120, gameRect.minX)
        let dpad = min(side * 0.82, h * 0.42)
        let face = dpad * 0.42
        var c: [Control] = []
        c.append(Control(kind: .dpad, frame: CGRect(x: side * 0.5 - dpad / 2, y: h * 0.58 - dpad / 2, width: dpad, height: dpad)))
        let rx = w - side * 0.5
        c.append(Control(kind: .face(.b, "B", .sand), frame: CGRect(x: rx - face * 1.1, y: h * 0.62 - face * 0.1, width: face, height: face)))
        c.append(Control(kind: .face(.a, "A", .ember), frame: CGRect(x: rx + face * 0.1, y: h * 0.62 - face * 0.95, width: face, height: face)))
        c.append(Control(kind: .pill(.select, "SELECT"), frame: CGRect(x: side * 0.5 - 30, y: h - 40, width: 60, height: 20)))
        c.append(Control(kind: .pill(.start, "START"), frame: CGRect(x: rx - 30, y: h - 40, width: 60, height: 20)))
        c.append(Control(kind: .menu, frame: CGRect(x: side * 0.5 - 17, y: 18, width: 34, height: 34)))
        c.append(Control(kind: .fastForward, frame: CGRect(x: rx + 4, y: 18, width: 34, height: 34)))
        c.append(Control(kind: .rewind, frame: CGRect(x: rx - 38, y: 18, width: 34, height: 34)))
        return c
    }
}
