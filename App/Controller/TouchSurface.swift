import CoreKit
import SwiftUI
import UIKit

/// A transparent multi-touch layer over the drawn controls.
///
/// SwiftUI gestures can't follow several fingers on independent controls reliably, so touches are
/// tracked here by identity: the D-pad keeps a thumb that slides off it, face buttons follow a thumb
/// rolling between them (a press between A and B holds both), and Start/Select only count a touch
/// that *began* on them, which stops the accidental slide-on presses players complain about.
struct TouchSurface: UIViewRepresentable {
    var controls: [Control]
    let model: ControllerModel

    func makeUIView(context: Context) -> SurfaceView {
        let v = SurfaceView()
        v.model = model
        v.controls = controls
        return v
    }

    func updateUIView(_ view: SurfaceView, context: Context) {
        view.controls = controls
        view.model = model
    }

    static func dismantleUIView(_ view: SurfaceView, coordinator: ()) {
        view.releaseAll()
    }

    final class SurfaceView: UIView {
        var controls: [Control] = []
        weak var model: ControllerModel?

        private enum Owner { case dpad, buttons, pill(InputState), menu, fastForward, rewind, stick(CGPoint), none }
        private var owners: [ObjectIdentifier: Owner] = [:]
        private var points: [ObjectIdentifier: CGPoint] = [:]

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches {
                let p = t.location(in: self)
                let id = ObjectIdentifier(t)
                points[id] = p
                owners[id] = owner(at: p)
                if case .stick = owners[id] {
                    // One thumb on the stick at a time; a second touch there does nothing.
                    let taken = owners.contains { key, o in if case .stick = o, key != id { true } else { false } }
                    owners[id] = taken ? Owner.none : .stick(stickOrigin(for: p))
                }
            }
            recompute()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { points[ObjectIdentifier(t)] = t.location(in: self) }
            recompute()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches {
                owners.removeValue(forKey: ObjectIdentifier(t))
                points.removeValue(forKey: ObjectIdentifier(t))
            }
            recompute()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            touchesEnded(touches, with: event)
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            if newWindow == nil { releaseAll() }
        }

        func releaseAll() {
            owners.removeAll()
            points.removeAll()
            MainActor.assumeIsolated { model?.releaseAll() }
        }

        private var stickControl: Control? { controls.first { $0.kind == .stick } }
        private var stickSettings: ControlSettings { MainActor.assumeIsolated { model?.settings ?? ControlSettings() } }

        /// Where the stick's centre is for a thumb landing at `p`: the control's centre, or the
        /// thumb itself when re-centring is on (except on the outer ring, which is always measured
        /// from the real centre so it gives full deflection).
        private func stickOrigin(for p: CGPoint) -> CGPoint {
            guard let c = stickControl else { return p }
            let centre = CGPoint(x: c.frame.midX, y: c.frame.midY)
            let onBase = hypot(p.x - centre.x, p.y - centre.y) <= c.frame.width / 2
            return stickSettings.stickRecentre && onBase ? p : centre
        }

        /// The stick's touch area: its frame plus a little; out to the outer ring when that's on.
        private func stickHit(_ c: Control, _ p: CGPoint) -> Bool {
            let ring = stickSettings.stickOuterRing ? StickMath.ringScale : 1.12
            return hypot(p.x - c.frame.midX, p.y - c.frame.midY) <= c.frame.width / 2 * ring
        }

        private func owner(at p: CGPoint) -> Owner {
            // Exact frames first, then the generous hit areas.
            for pass in 0..<2 {
                for c in controls {
                    if c.kind == .stick {
                        if pass == 1 && stickHit(c, p) || pass == 0 && c.frame.contains(p) { return .stick(.zero) }
                        continue
                    }
                    let r = pass == 0 ? c.frame : c.hitFrame
                    guard r.contains(p) else { continue }
                    switch c.kind {
                    case .stick: return .stick(.zero)
                    case .dpad: return .dpad
                    case .face, .shoulder, .combo: return .buttons
                    case .pill(let s, _): return .pill(s)
                    case .menu: return .menu
                    case .fastForward: return .fastForward
                    case .rewind: return .rewind
                    }
                }
            }
            return .none
        }

        private func recompute() {
            var pressed: InputState = []
            var vector = CGVector.zero
            var menu = false, ff = false, rewind = false
            var stick = AnalogStick.centre, knob = CGVector.zero, base = CGVector.zero
            for (id, owner) in owners {
                guard let p = points[id] else { continue }
                switch owner {
                case .dpad:
                    guard let pad = controls.first(where: { $0.kind == .dpad }) else { break }
                    let st = model?.settings ?? ControlSettings()
                    let (bits, v) = Self.dpad(p, in: pad.frame, diagonal: st.diagonalDegrees, deadZone: st.deadZone)
                    pressed.formUnion(bits)
                    vector = v
                case .buttons:
                    for c in controls {
                        switch c.kind {
                        case .face(let s, _, _):
                            let centre = CGPoint(x: c.frame.midX, y: c.frame.midY)
                            // Generous for two buttons; tighter for crowded clusters so a thumb
                            // between three or four buttons doesn't press them all.
                            let reach = controls.filter { if case .face = $0.kind { true } else { false } }.count > 2 ? 1.1 : 1.3
                            let r = c.frame.width * 0.5 * reach
                            if hypot(p.x - centre.x, p.y - centre.y) <= r { pressed.insert(s) }
                        case .shoulder(let s, _), .combo(let s, _):
                            if c.hitFrame.contains(p) { pressed.insert(s) }
                        default: break
                        }
                    }
                case .pill(let s):
                    if let c = controls.first(where: { if case .pill(s, _) = $0.kind { true } else { false } }),
                       c.hitFrame.insetBy(dx: -20, dy: -20).contains(p) {
                        pressed.insert(s)
                    }
                case .stick(let origin):
                    guard let c = stickControl else { break }
                    let st = stickSettings
                    let centre = CGPoint(x: c.frame.midX, y: c.frame.midY)
                    let radius = c.frame.width / 2
                    stick = StickMath.value(thumb: p, origin: origin, radius: radius, range: st.stickRange,
                                            deadZone: st.stickDeadZone)
                    base = CGVector(dx: origin.x - centre.x, dy: origin.y - centre.y)
                    knob = StickMath.knob(thumb: p, origin: origin, radius: radius)
                case .menu: menu = true
                case .fastForward: ff = true
                case .rewind: rewind = true
                case .none: break
                }
            }
            MainActor.assumeIsolated {
                model?.updateStick(stick, knob: knob, base: base)
                model?.update(pressed: pressed, dpad: vector, menu: menu, fastForward: ff, rewind: rewind)
            }
        }

        /// Eight-way with a dead zone (default 15 % of the radius). Each cardinal zone spans
        /// 90 + `diagonal` degrees, so the overlaps (`diagonal` degrees wide, centred on the
        /// diagonals) press two directions; `diagonal` 0 makes the pad four-way.
        static func dpad(_ p: CGPoint, in frame: CGRect, diagonal: Double = 36, deadZone: Double = 0.15) -> (InputState, CGVector) {
            let dx = p.x - frame.midX, dy = p.y - frame.midY
            let dist = hypot(dx, dy)
            guard dist > frame.width * 0.5 * deadZone else { return ([], .zero) }
            if diagonal <= 0 {
                // Four-way: the dominant axis wins.
                let v = CGVector(dx: dx / dist, dy: dy / dist)
                if abs(dx) >= abs(dy) { return (dx > 0 ? .right : .left, v) }
                return (dy > 0 ? .down : .up, v)
            }
            let half = 45 + min(60, diagonal) / 2
            var angle = atan2(-dy, dx) * 180 / .pi   // 0 = right, 90 = up
            if angle < 0 { angle += 360 }
            var s: InputState = []
            func within(_ centre: Double, _ half: Double) -> Bool {
                var d = abs(angle - centre).truncatingRemainder(dividingBy: 360)
                if d > 180 { d = 360 - d }
                return d <= half
            }
            if within(0, half) { s.insert(.right) }
            if within(90, half) { s.insert(.up) }
            if within(180, half) { s.insert(.left) }
            if within(270, half) { s.insert(.down) }
            let v = CGVector(dx: dx / dist, dy: dy / dist)
            return (s, v)
        }
    }
}

/// The touch stick's maths (pure, so it can be unit-tested).
///
/// True analog: the output points exactly at the thumb, never snapped to 8 or 45 degrees. Its
/// magnitude reaches 1 at `range` x the stick's radius (lower = more sensitive) and is 0 inside the
/// dead zone, rescaled so it rises smoothly from the dead zone's edge.
enum StickMath {
    /// The outer ring's radius as a multiple of the stick's.
    static let ringScale: CGFloat = 1.45

    static func value(thumb p: CGPoint, origin: CGPoint, radius: CGFloat, range: Double, deadZone: Double) -> AnalogStick {
        let dx = Double(p.x - origin.x), dy = Double(origin.y - p.y)   // up is positive
        let dist = (dx * dx + dy * dy).squareRoot()
        let full = Double(radius) * min(1, max(0.2, range))
        guard dist > 0, full > 0 else { return .centre }
        let m = min(1, dist / full)
        let zone = min(0.9, max(0, deadZone))
        guard m > zone else { return .centre }
        let shaped = (m - zone) / (1 - zone)
        return AnalogStick(x: dx / dist * shaped, y: dy / dist * shaped)
    }

    /// Where to draw the knob: under the thumb, held inside the base.
    static func knob(thumb p: CGPoint, origin: CGPoint, radius: CGFloat) -> CGVector {
        let dx = p.x - origin.x, dy = p.y - origin.y
        let dist = hypot(dx, dy)
        let limit = radius * 0.62
        guard dist > limit, dist > 0 else { return CGVector(dx: dx, dy: dy) }
        return CGVector(dx: dx / dist * limit, dy: dy / dist * limit)
    }
}
