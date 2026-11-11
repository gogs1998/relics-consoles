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

        private enum Owner { case dpad, buttons, pill(InputState), menu, fastForward, rewind, none }
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

        private func owner(at p: CGPoint) -> Owner {
            // Exact frames first, then the generous hit areas.
            for pass in 0..<2 {
                for c in controls {
                    let r = pass == 0 ? c.frame : c.hitFrame
                    guard r.contains(p) else { continue }
                    switch c.kind {
                    case .dpad: return .dpad
                    case .face: return .buttons
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
            for (id, owner) in owners {
                guard let p = points[id] else { continue }
                switch owner {
                case .dpad:
                    guard let pad = controls.first(where: { $0.kind == .dpad }) else { break }
                    let (bits, v) = Self.dpad(p, in: pad.frame)
                    pressed.formUnion(bits)
                    vector = v
                case .buttons:
                    for c in controls {
                        guard case .face(let s, _, _) = c.kind else { continue }
                        let centre = CGPoint(x: c.frame.midX, y: c.frame.midY)
                        let r = c.frame.width * 0.5 * 1.3
                        if hypot(p.x - centre.x, p.y - centre.y) <= r { pressed.insert(s) }
                    }
                case .pill(let s):
                    if let c = controls.first(where: { if case .pill(s, _) = $0.kind { true } else { false } }),
                       c.hitFrame.insetBy(dx: -20, dy: -20).contains(p) {
                        pressed.insert(s)
                    }
                case .menu: menu = true
                case .fastForward: ff = true
                case .rewind: rewind = true
                case .none: break
                }
            }
            MainActor.assumeIsolated {
                model?.update(pressed: pressed, dpad: vector, menu: menu, fastForward: ff, rewind: rewind)
            }
        }

        /// Eight-way with an 18 % dead zone. Each cardinal zone spans 105 degrees, so the 30-degree
        /// overlaps centred on the diagonals press two directions.
        static func dpad(_ p: CGPoint, in frame: CGRect) -> (InputState, CGVector) {
            let dx = p.x - frame.midX, dy = p.y - frame.midY
            let dist = hypot(dx, dy)
            guard dist > frame.width * 0.5 * 0.18 else { return ([], .zero) }
            var angle = atan2(-dy, dx) * 180 / .pi   // 0 = right, 90 = up
            if angle < 0 { angle += 360 }
            var s: InputState = []
            func within(_ centre: Double, _ half: Double) -> Bool {
                var d = abs(angle - centre).truncatingRemainder(dividingBy: 360)
                if d > 180 { d = 360 - d }
                return d <= half
            }
            if within(0, 52.5) { s.insert(.right) }
            if within(90, 52.5) { s.insert(.up) }
            if within(180, 52.5) { s.insert(.left) }
            if within(270, 52.5) { s.insert(.down) }
            let v = CGVector(dx: dx / dist, dy: dy / dist)
            return (s, v)
        }
    }
}
