import CoreKit
import CoreGraphics

/// The DS standard layouts. The DS uses the SNES-style diamond (Y X B A) and L / R; its touch
/// screen is never covered: in Duo table pose the controls live in three areas around the screen,
/// and in every other pose the controller areas sit beside or below the screens.
extension ControllerLayout {
    /// Duo table, the column left of the touch screen: L on top, the D-pad, Select below.
    static func dsTableLeft(_ size: CGSize, preset: LayoutPreset = .standard) -> [Control] {
        let w = size.width, h = size.height
        let tw = min(w - 12, 120), th: CGFloat = 30
        let dpad = min(w * 0.94, h * 0.5)
        let pillW = min(58, w * 0.7), pillH: CGFloat = 30
        return [
            Control(kind: .shoulder(.l, "L"), frame: CGRect(x: (w - tw) / 2, y: 4, width: tw, height: th)),
            Control(kind: .dpad, frame: CGRect(x: w / 2 - dpad / 2, y: h * 0.48 - dpad / 2, width: dpad, height: dpad)),
            Control(kind: .pill(.select, "SELECT"), frame: CGRect(x: w / 2 - pillW / 2, y: h - pillH - 10, width: pillW, height: pillH)),
        ]
    }

    /// Duo table, the column right of the touch screen: R on top, the face diamond, Start below.
    static func dsTableRight(_ size: CGSize, preset: LayoutPreset = .standard) -> [Control] {
        let w = size.width, h = size.height
        let tw = min(w - 12, 120), th: CGFloat = 30
        // The diamond spans about 2.42 button diameters.
        let d = min(w * 0.96 / 2.42, h * 0.5 / 2.42)
        let pillW = min(58, w * 0.7), pillH: CGFloat = 30
        var c = [Control(kind: .shoulder(.r, "R"), frame: CGRect(x: (w - tw) / 2, y: 4, width: tw, height: th))]
        c += faceCluster(.ds, centre: CGPoint(x: w / 2, y: h * 0.48), diameter: d, sixButton: false)
        c.append(Control(kind: .pill(.start, "START"), frame: CGRect(x: w / 2 - pillW / 2, y: h - pillH - 10, width: pillW, height: pillH)))
        return c
    }

    /// Duo table, the strip under the touch screen: rewind, menu, fast-forward.
    static func dsTableBelow(_ size: CGSize, preset: LayoutPreset = .standard) -> [Control] {
        let w = size.width, h = size.height
        let key = max(28, min(38, h - 8))
        let y = (h - key) / 2
        return [
            Control(kind: .rewind, frame: CGRect(x: w / 2 - key * 1.9, y: y, width: key, height: key)),
            Control(kind: .menu, frame: CGRect(x: w / 2 - key / 2, y: y, width: key, height: key)),
            Control(kind: .fastForward, frame: CGRect(x: w / 2 + key * 0.9, y: y, width: key, height: key)),
        ]
    }

    /// Duo book, right page under the touch screen: the usual right-page controls plus the app keys
    /// (the DS has no companion page: both pages show a screen).
    static func dsBookRight(_ size: CGSize, preset: LayoutPreset = .standard) -> [Control] {
        let h = size.height
        var c = bookRight(size, system: .ds, preset: preset)
        // A row of keys in the top-left corner, left of the face buttons; Start moves under them.
        let faceLeft = c.filter { if case .face = $0.kind { return true } else { return false } }.map(\.frame.minX).min() ?? size.width
        let key = max(24, min(34, h * 0.24, (faceLeft - 20) / 3.6))
        c.append(Control(kind: .rewind, frame: CGRect(x: 12, y: 6, width: key, height: key)))
        c.append(Control(kind: .menu, frame: CGRect(x: 12 + key * 1.3, y: 6, width: key, height: key)))
        c.append(Control(kind: .fastForward, frame: CGRect(x: 12 + key * 2.6, y: 6, width: key, height: key)))
        if let i = c.firstIndex(where: { $0.id == Control(kind: .pill(.start, "START"), frame: .zero).id }) {
            c[i].frame.origin.y = max(c[i].frame.minY, 6 + key + 14)
        }
        // Keep R clear of the diamond's top button.
        let faceRight = c.filter { if case .face = $0.kind { return true } else { return false } }.map(\.frame.maxX).max() ?? 0
        if let i = c.firstIndex(where: { if case .shoulder = $0.kind { return true } else { return false } }),
           c[i].frame.minX < faceRight + 6 {
            let maxX = c[i].frame.maxX
            c[i].frame.origin.x = faceRight + 6
            c[i].frame.size.width = max(44, maxX - c[i].frame.minX)
        }
        return c
    }
}
