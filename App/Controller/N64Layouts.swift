import CoreKit
import CoreGraphics

/// Default touch layouts for the Nintendo 64 controller: analog stick, D-pad, A / B, the four C
/// buttons, Z, L / R and Start, in our own Graphite and Ember (never the console's colours).
///
/// The left thumb gets the stick (with the small D-pad under it), the right thumb A / B with the
/// C cluster above, and the shoulders L, Z and R run along the top edge. Every layout keeps to its
/// area, so nothing covers the game: the deck sits below it, book pose uses the page under it,
/// landscape uses only the margins either side of it.
///
/// Every layout carries both camera controls: the four C buttons and the C stick in the same place.
/// `camera(_:cStick:)` shows one of them, from the player's "Camera" choice (`LayoutOptions`).
/// The C buttons aim for 44 pt (Apple's minimum target) and shrink only where the area can't fit
/// them without touching A / B, Start, the shoulders or the game.
enum N64Layout {
    /// The smallest a C button should be when there is room (Apple's minimum touch target).
    static let cTarget: CGFloat = 44
    static let cButtons: InputState = [.cUp, .cDown, .cLeft, .cRight]

    static let cUp = "\u{25B2}\u{FE0E}", cDown = "\u{25BC}\u{FE0E}", cLeft = "\u{25C0}\u{FE0E}", cRight = "\u{25B6}\u{FE0E}"

    static func circle(_ kind: Control.Kind, _ c: CGPoint, _ d: CGFloat) -> Control {
        Control(kind: kind, frame: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
    }

    /// The four C buttons in a diamond around `c`, each `d` across (it spans `clusterSpan * d`).
    static let clusterSpan: CGFloat = 2.96
    /// `spread` is each button's distance from the centre in diameters (0.75 is a tight diamond
    /// whose neighbours still don't touch: they sit 1.06 diameters apart).
    static func cCluster(_ c: CGPoint, d: CGFloat, spread: CGFloat = 0.98) -> [Control] {
        let r = d * spread
        return [
            circle(.face(.cUp, cUp, .sand), CGPoint(x: c.x, y: c.y - r), d),
            circle(.face(.cLeft, cLeft, .sand), CGPoint(x: c.x - r, y: c.y), d),
            circle(.face(.cRight, cRight, .sand), CGPoint(x: c.x + r, y: c.y), d),
            circle(.face(.cDown, cDown, .sand), CGPoint(x: c.x, y: c.y + r), d),
        ]
    }


    // MARK: camera (C buttons or C stick)

    static func isCButton(_ c: Control) -> Bool {
        if case .face(let s, _, _) = c.kind { return cButtons.contains(s) }
        return false
    }

    /// The controls to show for the player's camera choice: the C stick instead of the four C
    /// buttons, or the other way round. Layouts saved before the C stick existed get one made
    /// where their C buttons are.
    static func camera(_ controls: [Control], cStick: Bool) -> [Control] {
        let all = withCStick(controls)
        return all.filter { cStick ? !isCButton($0) : $0.kind != .cStick }
    }

    /// `controls` with a C stick added over the C buttons' place when it has none (the editor keeps
    /// both, so moving one never loses the other's place).
    static func withCStick(_ controls: [Control]) -> [Control] {
        guard !controls.contains(where: { $0.kind == .cStick }) else { return controls }
        let cluster = controls.filter(isCButton)
        guard let first = cluster.first else { return controls }
        let box = cluster.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        let d = min(box.width, box.height) * 0.86
        var stick = Control(kind: .cStick, frame: CGRect(x: box.midX - d / 2, y: box.midY - d / 2, width: d, height: d))
        // Old layouts: carry over the cluster's look.
        stick.opacity = first.opacity
        stick.hidden = first.hidden
        return controls + [stick]
    }

    private static func isRound(_ c: Control) -> Bool {
        switch c.kind { case .face, .stick, .cStick: true; default: false }
    }

    /// A circle of diameter `d` at `p` stays inside `bounds`, off `keepOut` and at least `gap` from
    /// every control in `others` (circle to circle for round controls, its square for the rest).
    static func clears(_ p: CGPoint, d: CGFloat, others: [Control], bounds: CGRect, keepOut: CGRect?, gap: CGFloat = 2) -> Bool {
        let r = d / 2
        guard p.x - r >= bounds.minX - 0.01, p.x + r <= bounds.maxX + 0.01,
              p.y - r >= bounds.minY - 0.01, p.y + r <= bounds.maxY + 0.01 else { return false }
        // Square controls and the game are kept clear of the circle's whole square (conservative).
        let square = CGRect(x: p.x - r, y: p.y - r, width: d, height: d).insetBy(dx: -gap, dy: -gap)
        func clearOf(_ f: CGRect) -> Bool { !square.intersects(f) }
        if let keepOut, !clearOf(keepOut) { return false }
        for o in others {
            if isRound(o) {
                if hypot(p.x - o.frame.midX, p.y - o.frame.midY) < r + o.frame.width / 2 + gap { return false }
            } else if !clearOf(o.frame) {
                return false
            }
        }
        return true
    }

    /// Small nudges tried around a preferred centre, nearest first.
    private static let nudges: [CGPoint] = {
        var list = [CGPoint.zero]
        for k in 1...5 {
            let s = CGFloat(k) * 5
            list += [CGPoint(x: 0, y: -s), CGPoint(x: 0, y: s), CGPoint(x: -s, y: 0), CGPoint(x: s, y: 0),
                     CGPoint(x: -s, y: -s), CGPoint(x: s, y: -s), CGPoint(x: -s, y: s), CGPoint(x: s, y: s)]
        }
        return list
    }()

    /// The biggest C cluster from `maxD` down to `minD` that fits near `preferred` without touching
    /// anything; nil when even `minD` doesn't (the caller then keeps its old placement).
    static func fitCluster(near preferred: CGPoint, maxD: CGFloat, minD: CGFloat, others: [Control],
                           bounds: CGRect, keepOut: CGRect? = nil) -> (centre: CGPoint, d: CGFloat)? {
        var d = maxD
        while d >= minD - 0.001 {
            let r = d * 0.98
            for n in nudges {
                let c = CGPoint(x: preferred.x + n.x, y: preferred.y + n.y)
                let spots = [CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x - r, y: c.y),
                             CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x, y: c.y + r)]
                if spots.allSatisfy({ clears($0, d: d, others: others, bounds: bounds, keepOut: keepOut) }) { return (c, d) }
            }
            d -= 1
        }
        return nil
    }

    /// The C cluster (as big as fits, aiming for 44 pt) and a C stick over the same place.
    /// `fallback` is the old size, used as is when nothing bigger fits.
    static func cameraControls(near preferred: CGPoint, fallback: CGFloat, others: [Control],
                               bounds: CGRect, keepOut: CGRect? = nil) -> [Control] {
        let maxD = max(cTarget, fallback)
        let fit = fitCluster(near: preferred, maxD: maxD, minD: fallback, others: others, bounds: bounds, keepOut: keepOut)
        let centre = fit?.centre ?? preferred, d = fit?.d ?? fallback
        var list = cCluster(centre, d: d)
        // The stick: as wide as the cluster where that fits, shrinking (and nudging) until it clears.
        var sd = d * clusterSpan, at = centre
        search: while sd > d * 1.2 {
            for n in nudges {
                let p = CGPoint(x: centre.x + n.x, y: centre.y + n.y)
                if clears(p, d: sd, others: others, bounds: bounds, keepOut: keepOut) { at = p; break search }
            }
            sd -= 1
        }
        list.append(Control(kind: .cStick, frame: CGRect(x: at.x - sd / 2, y: at.y - sd / 2, width: sd, height: sd)))
        return list
    }

    /// A, with B up and to its left (where the thumb rolls to).
    static func abPair(a: CGPoint, d: CGFloat) -> [Control] {
        [
            circle(.face(.a, "A", .ember), a, d),
            circle(.face(.b, "B", .ember), CGPoint(x: a.x - d * 1.18, y: a.y - d * 0.58), d * 0.9),
        ]
    }

    static func shoulder(_ s: InputState, _ label: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat = 30) -> Control {
        Control(kind: .shoulder(s, label), frame: CGRect(x: x, y: y, width: w, height: h))
    }

    static func keys(centreX x: CGFloat, y: CGFloat, size k: CGFloat, gap: CGFloat = 6) -> [Control] {
        [
            Control(kind: .rewind, frame: CGRect(x: x - k * 1.5 - gap, y: y, width: k, height: k)),
            Control(kind: .menu, frame: CGRect(x: x - k / 2, y: y, width: k, height: k)),
            Control(kind: .fastForward, frame: CGRect(x: x + k / 2 + gap, y: y, width: k, height: k)),
        ]
    }

    /// The full controller below the game (portrait) or on the Duo's bottom half (table): big and
    /// roomy, in four quarters. L and R are wide tabs in the top corners with the menu, rewind and
    /// fast-forward keys between them; the stick is top left with the D-pad, as big, under it;
    /// A, B and Z are three large face buttons in a triangle top right (Z top, B left, A lower
    /// right); the C buttons are a large diamond bottom right (or the C stick, as big as the
    /// D-pad, in its place); Start sits small in the middle.
    static func deck(_ size: CGSize) -> [Control] {
        let w = size.width, h = size.height
        let top: CGFloat = 44, body = max(160, h - top)
        let upper = top + body * 0.25, lower = top + body * 0.76
        let tabW = min(140, w * 0.28)
        var c: [Control] = [
            shoulder(.l, "L", x: 8, y: 4, w: tabW, h: 34),
            shoulder(.r, "R", x: w - 8 - tabW, y: 4, w: tabW, h: 34),
        ]
        c += keys(centreX: w * 0.5, y: 4, size: min(32, max(26, (w - 2 * tabW - 16 - 24) / 3 - 8)))
        // left half: the stick over the D-pad
        let stick = min(w * 0.36, body * 0.47)
        let lx = max(w * 0.23, stick / 2 + 8)
        c.append(circle(.stick, CGPoint(x: lx, y: upper), stick))
        let pad = stick * 0.95
        c.append(Control(kind: .dpad, frame: CGRect(x: lx - pad / 2, y: lower - pad / 2, width: pad, height: pad)))
        // right half: A / B / Z triangle over the C diamond
        let rx = min(w * 0.75, w - 8 - body * 0.2)
        let f = min(64, body * 0.2, w * 0.16)
        c += [
            circle(.face(.z, "Z", .ember), CGPoint(x: rx + f * 0.1, y: upper - f * 0.7), f),
            circle(.face(.b, "B", .ember), CGPoint(x: rx - f * 0.75, y: upper + f * 0.15), f),
            circle(.face(.a, "A", .ember), CGPoint(x: rx + f * 0.55, y: upper + f * 0.55), f),
        ]
        // Start, small, in the middle
        let pillW = min(52, w * 0.13), pillH: CGFloat = 26
        c.append(Control(kind: .pill(.start, "START"),
                         frame: CGRect(x: w * 0.5 - pillW / 2, y: top + body * 0.5 - pillH / 2, width: pillW, height: pillH)))
        let cd = min(60, body * 0.5 / 2.5, w * 0.42 / 2.5)
        let cx = min(rx, w - 6 - cd * 1.25)
        let cy = min(lower, h - 4 - cd * 1.25)
        c += cCluster(CGPoint(x: cx, y: cy), d: cd, spread: 0.75)
        c.append(circle(.cStick, CGPoint(x: cx, y: cy), min(pad, cd * 2.5)))
        return c
    }

    /// Duo book pose, left page (under the game): stick, D-pad, L and Z.
    static func bookLeft(_ size: CGSize) -> [Control] {
        let w = size.width, h = size.height
        let stick = min(h * 0.72, w * 0.34, h - 32)   // below the shoulders (2...28)
        let pad = min(h * 0.52, w * 0.2)
        return [
            circle(.stick, CGPoint(x: max(w * 0.32, stick / 2 + 8), y: 30 + (h - 30) / 2), stick),
            Control(kind: .dpad, frame: CGRect(x: w * 0.70 - pad / 2, y: h * 0.62 - pad / 2, width: pad, height: pad)),
            shoulder(.l, "L", x: 10, y: 2, w: min(110, w * 0.24), h: 26),
            shoulder(.z, "Z", x: w - min(110, w * 0.24) - 10, y: 2, w: min(110, w * 0.24), h: 26),
        ]
    }

    /// Duo book pose, right page (under the companion): C buttons on the left, A / B on the right,
    /// Start between them and R along the top. Sized from the page, which is narrow on a real Duo.
    static func bookRight(_ size: CGSize) -> [Control] {
        let w = size.width, h = size.height
        let face = min(h * 0.34, w * 0.15)
        let cd = face * 0.62
        let a = CGPoint(x: w - face / 2 - 10, y: h * 0.66)
        let bLeft = a.x - face * 1.18 - face * 0.45
        var c = [shoulder(.r, "R", x: w - min(110, w * 0.3) - 10, y: 2, w: min(110, w * 0.3), h: 26)]
        c += abPair(a: a, d: face)
        // Start's name is stamped below the key, so it sits low, just left of B; the C cluster
        // takes what's left of the page (as big as fits, from the old size up to 44 pt).
        c.append(Control(kind: .pill(.start, "START"), frame: CGRect(x: bLeft - 62, y: h - 38, width: 56, height: 20)))
        let room = CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: 4, dy: 2)
        let big = min(cTarget, (h - 4) / clusterSpan)
        c += cameraControls(near: CGPoint(x: big * 1.48 + 10, y: h * 0.5), fallback: cd, others: c, bounds: room)
        return c
    }

    /// Landscape phone: the left margin has L, the stick and the D-pad; the right margin Z and R,
    /// the C cluster, A / B and Start. Nothing enters the game's rect.
    static func overlay(_ size: CGSize, gameRect: CGRect) -> [Control] {
        let w = size.width, h = size.height
        let left = max(110, gameRect.minX)
        let rightStart = min(w - 110, gameRect.maxX)
        let right = w - rightStart
        let lx = left / 2, rx = rightStart + right / 2
        var c: [Control] = []
        // left margin
        c.append(Control(kind: .menu, frame: CGRect(x: lx - 17, y: 10, width: 34, height: 34)))
        c.append(shoulder(.l, "L", x: lx - min(left * 0.8, 120) / 2, y: 52, w: min(left * 0.8, 120), h: 28))
        let stick = min(left * 0.8, h * 0.38)
        c.append(circle(.stick, CGPoint(x: lx, y: h * 0.50), stick))
        let pad = min(stick * 0.52, h * 0.2)
        c.append(Control(kind: .dpad, frame: CGRect(x: lx - pad / 2, y: h - pad - 8, width: pad, height: pad)))
        // right margin
        c.append(Control(kind: .rewind, frame: CGRect(x: rx - 38, y: 10, width: 34, height: 34)))
        c.append(Control(kind: .fastForward, frame: CGRect(x: rx + 4, y: 10, width: 34, height: 34)))
        let tw = min(right * 0.44, 72)
        c.append(shoulder(.z, "Z", x: rx - tw - 3, y: 52, w: tw, h: 28))
        c.append(shoulder(.r, "R", x: rx + 3, y: 52, w: tw, h: 28))
        let face = min(right * 0.29, h * 0.13)
        c += abPair(a: CGPoint(x: rx + right * 0.2, y: h * 0.74), d: face)
        c.append(Control(kind: .pill(.start, "START"), frame: CGRect(x: rx - right * 0.36, y: h - 36, width: 56, height: 20)))
        // keep everything in its margin
        let placed = c.map { ctl in
            var ctl = ctl
            if ctl.frame.midX < gameRect.midX {
                ctl.frame.origin.x = min(ctl.frame.minX, gameRect.minX - ctl.frame.width - 2)
            } else {
                ctl.frame.origin.x = max(ctl.frame.minX, gameRect.maxX + 2)
            }
            ctl.frame.origin.x = min(max(2, ctl.frame.minX), w - ctl.frame.width - 2)
            return ctl
        }
        // The C cluster last, so it can grow into whatever the right margin has left.
        return placed + cameraControls(near: CGPoint(x: rx + right * 0.08, y: h * 0.42), fallback: face * 0.66, others: placed,
                                       bounds: CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: 2, dy: 2),
                                       keepOut: gameRect.insetBy(dx: -2, dy: 0))
    }
}
