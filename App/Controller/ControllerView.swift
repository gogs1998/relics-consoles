import CoreKit
import SwiftUI

/// Draws a set of controls and lays the multi-touch surface over them.
struct ControllerView: View {
    var controls: [Control]
    let model: ControllerModel
    /// Translucent controls over a game (landscape).
    var floating = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(controls) { control in
                controlView(control)
                    .frame(width: control.frame.width, height: control.frame.height)
                    .position(x: control.frame.midX, y: control.frame.midY)
            }
            TouchSurface(controls: controls, model: model)
                .accessibilityHidden(true)
        }
        .opacity(floating ? 0.62 : 1)
    }

    @ViewBuilder
    private func controlView(_ c: Control) -> some View {
        switch c.kind {
        case .dpad:
            DPadView(pressed: model.pressed, vector: model.dpadVector)
        case .face(let s, let label, let tone):
            FaceButtonView(label: label, tone: tone, pressed: model.pressed.contains(s))
        case .pill(let s, let label):
            PillKeyView(label: label, pressed: model.pressed.contains(s))
        case .menu:
            RoundKeyView(symbol: "ellipsis", label: "Menu", pressed: model.menuDown)
        case .fastForward:
            RoundKeyView(symbol: "forward.fill", label: "Fast forward (hold)", pressed: model.fastForwardDown)
        case .rewind:
            RoundKeyView(symbol: "backward.fill", label: "Rewind (hold)", pressed: model.rewindDown)
        }
    }
}

// MARK: - D-pad

/// One-piece cross with a dished centre. Tilts a few degrees toward the pressed direction.
struct DPadView: View {
    var pressed: InputState
    var vector: CGVector

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let arm = s * 0.34
            ZStack {
                // Recessed well the pad sits in.
                Circle()
                    .fill(RadialGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.15), .clear],
                                         center: .center, startRadius: s * 0.25, endRadius: s * 0.52))
                    .frame(width: s * 1.04, height: s * 1.04)
                Circle()
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    .frame(width: s * 0.98, height: s * 0.98)

                ZStack {
                    CrossShape(arm: arm)
                        .fill(LinearGradient(colors: [Color(white: 0.27), Color(white: 0.16), Color(white: 0.11)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: .black.opacity(0.65), radius: s * 0.03, x: 0, y: s * 0.03)
                    CrossShape(arm: arm)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.02)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
                    // Pressed arm darkens.
                    ForEach(Arm.allCases, id: \.self) { a in
                        ArmShape(arm: arm, which: a)
                            .fill(Color.black.opacity(pressed.contains(a.input) ? 0.38 : 0))
                    }
                    // Engraved arrows.
                    ForEach(Arm.allCases, id: \.self) { a in
                        Triangle()
                            .fill(Color.white.opacity(pressed.contains(a.input) ? 0.12 : 0.22))
                            .frame(width: s * 0.075, height: s * 0.06)
                            .rotationEffect(.degrees(a.rotation))
                            .offset(a.offset(s * 0.37))
                    }
                    // Dished centre.
                    Circle()
                        .fill(RadialGradient(colors: [Color(white: 0.09), Color(white: 0.19)],
                                             center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: s * 0.13))
                        .frame(width: s * 0.22, height: s * 0.22)
                        .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))
                }
                .frame(width: s, height: s)
                .rotation3DEffect(.degrees(vector == .zero ? 0 : 7),
                                  axis: (x: -vector.dy, y: vector.dx, z: 0), perspective: 0.6)
                .animation(.spring(response: 0.12, dampingFraction: 0.7), value: vector)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement()
        .accessibilityLabel("Direction pad")
    }

    enum Arm: CaseIterable {
        case up, down, left, right
        var input: InputState {
            switch self { case .up: .up; case .down: .down; case .left: .left; case .right: .right }
        }
        var rotation: Double {
            switch self { case .up: 0; case .right: 90; case .down: 180; case .left: 270 }
        }
        func offset(_ d: CGFloat) -> CGSize {
            switch self {
            case .up: CGSize(width: 0, height: -d)
            case .down: CGSize(width: 0, height: d)
            case .left: CGSize(width: -d, height: 0)
            case .right: CGSize(width: d, height: 0)
            }
        }
    }
}

struct CrossShape: Shape {
    var arm: CGFloat
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let half = arm / 2
        let len = min(r.width, r.height) / 2
        let radius = arm * 0.22
        var p = Path()
        p.addRoundedRect(in: CGRect(x: c.x - half, y: c.y - len, width: arm, height: len * 2),
                         cornerSize: CGSize(width: radius, height: radius))
        p.addRoundedRect(in: CGRect(x: c.x - len, y: c.y - half, width: len * 2, height: arm),
                         cornerSize: CGSize(width: radius, height: radius))
        return p
    }
}

struct ArmShape: Shape {
    var arm: CGFloat
    var which: DPadView.Arm
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let half = arm / 2
        let len = min(r.width, r.height) / 2
        let radius = arm * 0.22
        let rect: CGRect
        switch which {
        case .up: rect = CGRect(x: c.x - half, y: c.y - len, width: arm, height: len - half)
        case .down: rect = CGRect(x: c.x - half, y: c.y + half, width: arm, height: len - half)
        case .left: rect = CGRect(x: c.x - len, y: c.y - half, width: len - half, height: arm)
        case .right: rect = CGRect(x: c.x + half, y: c.y - half, width: len - half, height: arm)
        }
        return Path(roundedRect: rect, cornerSize: CGSize(width: radius, height: radius))
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Face buttons

/// A domed cap: specular highlight, contact shadow, 2 pt of travel.
struct FaceButtonView: View {
    var label: String
    var tone: Control.Tone
    var pressed: Bool

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let (light, deep) = tone == .ember ? (Theme.ember, Theme.emberDeep) : (Theme.sand, Theme.sandDeep)
            ZStack {
                // Socket.
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: d * 1.1, height: d * 1.1)
                    .blur(radius: 1.5)
                Circle()
                    .fill(Theme.graphiteDeep)
                    .frame(width: d * 1.06, height: d * 1.06)
                    .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1).offset(y: 1))
                // Cap.
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [light, deep], center: UnitPoint(x: 0.38, y: 0.3),
                                             startRadius: d * 0.05, endRadius: d * 0.62))
                    Circle()
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.black.opacity(0.25)],
                                               startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    Ellipse()
                        .fill(LinearGradient(colors: [Color.white.opacity(pressed ? 0.22 : 0.55), .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: d * 0.52, height: d * 0.3)
                        .offset(x: -d * 0.08, y: -d * 0.22)
                        .blur(radius: d * 0.02)
                    Text(label)
                        .font(.rounded(.title3, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.42))
                        .shadow(color: .white.opacity(0.35), radius: 0, x: 0, y: 1)
                }
                .frame(width: d, height: d)
                .shadow(color: .black.opacity(0.6), radius: pressed ? d * 0.02 : d * 0.07, x: 0, y: pressed ? 1 : d * 0.06)
                .offset(y: pressed ? 2 : 0)
                .scaleEffect(pressed ? 0.97 : 1)
                .brightness(pressed ? -0.07 : 0)
                .animation(.spring(response: 0.1, dampingFraction: 0.65), value: pressed)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement()
        .accessibilityLabel("\(label) button")
    }
}

// MARK: - Small keys

/// Start / Select: a pill in a recessed channel, its name stamped beneath.
struct PillKeyView: View {
    var label: String
    var pressed: Bool

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Capsule().fill(Color.black.opacity(0.55)).padding(-3)
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: pressed ? 0.22 : 0.33), Color(white: pressed ? 0.14 : 0.2)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                    .offset(y: pressed ? 1 : 0)
            }
            .rotationEffect(.degrees(-18))
            Text(label)
                .font(.rounded(.caption2, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkDim)
                .fixedSize()
        }
        .accessibilityElement()
        .accessibilityLabel(label.capitalized)
    }
}

/// Menu, fast-forward and rewind: round recessed keys with a glyph.
struct RoundKeyView: View {
    var symbol: String
    var label: String
    var pressed: Bool

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.5)).padding(-2.5)
            Circle()
                .fill(LinearGradient(colors: [Color(white: pressed ? 0.17 : 0.25), Color(white: 0.13)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.8))
            Image(systemName: symbol)
                .font(.rounded(.caption, weight: .bold))
                .foregroundStyle(pressed ? Theme.ember : Theme.inkDim)
        }
        .scaleEffect(pressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

/// Two rows of short ventilation slots: the quiet signature on the body.
struct VentSlots: View {
    var columns = 6
    var body: some View {
        VStack(spacing: 5) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 5) {
                    ForEach(0..<columns, id: \.self) { _ in
                        Capsule()
                            .fill(Color.black.opacity(0.55))
                            .overlay(Capsule().stroke(Color.white.opacity(0.05), lineWidth: 0.6).offset(y: 0.6))
                            .frame(width: 14, height: 3.5)
                    }
                }
            }
        }
        .rotationEffect(.degrees(-18))
        .accessibilityHidden(true)
    }
}
