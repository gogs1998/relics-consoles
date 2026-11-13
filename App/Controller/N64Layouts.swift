import CoreKit
import CoreGraphics

/// Default touch layouts for the Nintendo 64 controller: analog stick, D-pad, A / B, the four C
/// buttons, Z, L / R and Start, in our own Graphite and Ember (never the console's colours).
///
/// The left thumb gets the stick (with the small D-pad under it), the right thumb A / B with the
/// C cluster above, and the shoulders L, Z and R run along the top edge. Every layout keeps to its
/// area, so nothing covers the game: the deck sits below it, book pose uses the page under it,
/// landscape uses only the margins either side of it.
enum N64Layout {
    static let cUp = "\u{25B2}\u{FE0E}", cDown = "\u{25BC}\u{FE0E}", cLeft = "\u{25C0}\u{FE0E}", cRight = "\u{25B6}\u{FE0E}"

    static func circle(_ kind: Control.Kind, _ c: CGPoint, _ d: CGFloat) -> Control {
        Control(kind: kind, frame: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
    }

    /// The four C buttons in a diamond around `c`, each `d` across.
    static func cCluster(_ c: CGPoint, d: CGFloat) -> [Control] {
        let r = d * 0.98
        return [
            circle(.face(.cUp, cUp, .sand), CGPoint(x: c.x, y: c.y - r), d),
            circle(.face(.cLeft, cLeft, .sand), CGPoint(x: c.x - r, y: c.y), d),
            circle(.face(.cRight, cRight, .sand), CGPoint(x: c.x + r, y: c.y), d),
            circle(.face(.cDown, cDown, .sand), CGPoint(x: c.x, y: c.y + r), d),
        ]
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

    /// The full controller below the game (portrait) or on the Duo's bottom half (table).
    static func deck(_ size: CGSize) -> [Control] {
        let w = size.width, h = size.height
        let top: CGFloat = 40, body = max(120, h - top)
        let key = min(30, h * 0.11)
        var c: [Control] = [
            shoulder(.l, "L", x: w * 0.02, y: 4, w: w * 0.22),
            shoulder(.z, "Z", x: w * 0.54, y: 4, w: w * 0.20),
            shoulder(.r, "R", x: w * 0.76, y: 4, w: w * 0.22),
        ]
        c += keys(centreX: w * 0.39, y: 4, size: key)
        let stick = min(w * 0.42, body * 0.52)
        c.append(circle(.stick, CGPoint(x: w * 0.25, y: top + body * 0.40), stick))
        let pad = min(stick * 0.55, body * 0.3)
        c.append(Control(kind: .dpad, frame: CGRect(x: 8, y: h - pad - 6, width: pad, height: pad)))
        let face = min(w * 0.15, body * 0.24)
        c += cCluster(CGPoint(x: w * 0.82, y: top + body * 0.33), d: face * 0.68)
        c += abPair(a: CGPoint(x: w * 0.75, y: top + body * 0.73), d: face)
        let pillW = min(58, w * 0.14), pillH: CGFloat = 34
        c.append(Control(kind: .pill(.start, "START"), frame: CGRect(x: w * 0.5 - pillW / 2, y: h - pillH - 4, width: pillW, height: pillH)))
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
        let cx = cd * 1.48 + 10
        let a = CGPoint(x: w - face / 2 - 10, y: h * 0.66)
        let bLeft = a.x - face * 1.18 - face * 0.45
        let gapMid = (cx + cd * 1.48 + bLeft) / 2
        var c = [shoulder(.r, "R", x: w - min(110, w * 0.3) - 10, y: 2, w: min(110, w * 0.3), h: 26)]
        // its name is stamped below the key, so it sits low in the gap between the clusters
        c.append(Control(kind: .pill(.start, "START"), frame: CGRect(x: gapMid - 28, y: h - 38, width: 56, height: 20)))
        c += cCluster(CGPoint(x: cx, y: h * 0.54), d: cd)
        c += abPair(a: a, d: face)
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
        c += cCluster(CGPoint(x: rx + right * 0.12, y: h * 0.42), d: face * 0.66)
        c += abPair(a: CGPoint(x: rx + right * 0.2, y: h * 0.72), d: face)
        c.append(Control(kind: .pill(.start, "START"), frame: CGRect(x: rx - right * 0.36, y: h - 36, width: 56, height: 20)))
        // keep everything in its margin
        return c.map { ctl in
            var ctl = ctl
            if ctl.frame.midX < gameRect.midX {
                ctl.frame.origin.x = min(ctl.frame.minX, gameRect.minX - ctl.frame.width - 2)
            } else {
                ctl.frame.origin.x = max(ctl.frame.minX, gameRect.maxX + 2)
            }
            ctl.frame.origin.x = min(max(2, ctl.frame.minX), w - ctl.frame.width - 2)
            return ctl
        }
    }
}
