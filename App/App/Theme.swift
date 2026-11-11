import CoreKit
import SwiftUI

/// "Graphite and Ember": the app's own industrial palette. No console colours.
enum Theme {
    static let graphiteTop = Color(red: 0.145, green: 0.157, blue: 0.180)
    static let graphite = Color(red: 0.110, green: 0.118, blue: 0.137)
    static let graphiteDeep = Color(red: 0.067, green: 0.071, blue: 0.082)
    static let rim = Color.white.opacity(0.07)
    static let ink = Color(red: 0.93, green: 0.91, blue: 0.87)
    static let inkDim = Color(red: 0.93, green: 0.91, blue: 0.87).opacity(0.55)

    static let ember = Color(red: 1.0, green: 0.42, blue: 0.24)
    static let emberDeep = Color(red: 0.80, green: 0.25, blue: 0.11)
    static let sand = Color(red: 0.91, green: 0.85, blue: 0.72)
    static let sandDeep = Color(red: 0.73, green: 0.65, blue: 0.50)

    static let screenGlass = Color(red: 0.035, green: 0.039, blue: 0.047)

    /// Library card tints, one per system, from the app's own palette.
    static func tint(_ system: SystemID) -> Color {
        switch system {
        case .nes: Color(red: 0.88, green: 0.64, blue: 0.23)    // saffron
        case .gb: Color(red: 0.36, green: 0.48, blue: 0.60)     // slate
        case .gbc: Color(red: 0.91, green: 0.43, blue: 0.35)    // coral
        case .gba: Color(red: 0.42, green: 0.62, blue: 0.52)    // sage
        case .snes: Color(red: 0.80, green: 0.55, blue: 0.70)   // heather
        case .md: Color(red: 0.30, green: 0.36, blue: 0.48)     // ink blue
        case .ds: Color(red: 0.55, green: 0.50, blue: 0.70)     // lavender slate
        }
    }

    static var bodyGradient: LinearGradient {
        LinearGradient(colors: [graphiteTop, graphite, graphiteDeep], startPoint: .top, endPoint: .bottom)
    }
}

/// The device body: graphite with a faint brushed grain. Drawn once, behind everything.
struct BodySurface: View {
    var body: some View {
        ZStack {
            Theme.bodyGradient
            Canvas { ctx, size in
                // Brushed grain: fine vertical hairlines of varying opacity.
                var seed: UInt32 = 0x9E3779B9
                var x: CGFloat = 0
                while x < size.width {
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    let a = Double(seed >> 24) / 255.0 * 0.035
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)),
                             with: .color(.white.opacity(a)))
                    x += 1.5
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

extension Font {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}
