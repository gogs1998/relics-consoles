import CoreKit
import SwiftUI

/// The DS's two screens in every arrangement.
///
/// - Duo table: the top screen on the top half; the touch screen in the middle of the bottom half
///   with the controls in three areas around it (left: L, D-pad, Select; right: R, Y X B A, Start;
///   below: rewind, menu, fast-forward), so no control can ever cover it.
/// - Duo book (landscape): one screen per page, controls under each.
/// - Ordinary portrait: the screens stacked, controls below. Landscape: side by side, controls in
///   the margins.
/// Only the touch screen's own rect takes stylus input.
extension PlayerView {
    private static let screen = CGSize(width: 256, height: 192)
    private static var topRegion: ScreenRegion { ScreenRegion(x: 0, y: 0, width: 256, height: 192) }
    private static var touchRegion: ScreenRegion { ScreenRegion(x: 0, y: 192, width: 256, height: 192, isTouch: true) }

    @ViewBuilder var dsLayout: some View {
        switch arrangement {
        case .table: dsTableLayout
        case .book: dsBookLayout
        case .portrait: dsPortraitLayout
        case .landscape: dsLandscapeLayout
        }
    }

    // MARK: arrangements

    private var dsTableLayout: some View {
        let top = stage.farHalf
        let bottom = stage.nearHalf
        let topScreen = dsFit(in: top.insetBy(dx: 12, dy: 10))
        // The touch screen takes ~70 % of the bottom half's height, centred, near the top.
        let maxH = (bottom.height - 14) * 0.7
        let touchBox = CGRect(x: bottom.midX - maxH * 4 / 3 / 2, y: bottom.minY + 8, width: maxH * 4 / 3, height: maxH)
        let touch = dsFit(in: touchBox, alignTop: true)
        let left = CGRect(x: bottom.minX + 2, y: bottom.minY + 4, width: touch.minX - bottom.minX - 8, height: bottom.height - 8)
        let right = CGRect(x: touch.maxX + 6, y: bottom.minY + 4, width: bottom.maxX - touch.maxX - 8, height: bottom.height - 8)
        let below = CGRect(x: touch.minX, y: touch.maxY + 4, width: touch.width, height: bottom.maxY - touch.maxY - 8)
        return ZStack(alignment: .topLeading) {
            dsScreen(Self.topRegion, at: topScreen)
            HingeSeam(axis: .horizontal).place(stage.fold.frame)
            dsScreen(Self.touchRegion, at: touch)
            if !model.physicalMode {
                controllerArea(.dsTableLeft, rect: left) { ControllerLayout.dsTableLeft(left.size, preset: $0) }
                controllerArea(.dsTableRight, rect: right) { ControllerLayout.dsTableRight(right.size, preset: $0) }
                controllerArea(.dsTableBelow, rect: below) { ControllerLayout.dsTableBelow(below.size, preset: $0) }
            } else {
                dsMenuKey.place(CGRect(x: below.midX - 18, y: below.midY - 18, width: 36, height: 36))
            }
            dsTouchPad.place(touch)
            toastView.place(CGRect(x: topScreen.minX, y: topScreen.minY + 6, width: topScreen.width, height: 40))
            if model.menuOpen { menuPanel.place(bottom.insetBy(dx: 10, dy: 8)) }
            if model.editor != nil { editorPanel.place(top.insetBy(dx: 10, dy: 8)) }
        }
    }

    private var dsBookLayout: some View {
        let left = stage.farHalf
        let right = stage.nearHalf
        let screenH = left.height * 0.6 - 12
        let leftScreen = dsFit(in: CGRect(x: left.minX + 12, y: left.minY + 12, width: left.width - 24, height: screenH))
        let rightScreen = dsFit(in: CGRect(x: right.minX + 12, y: right.minY + 12, width: right.width - 24, height: screenH))
        let padTop = left.minY + 12 + screenH + 4
        let leftPad = CGRect(x: left.minX, y: padTop, width: left.width, height: left.maxY - padTop - 4)
        // Run the lower right controls on under the Duo's right-edge status column (only its clock needs room).
        let reserve = max(0, stage.safeArea.trailing - stage.safeArea.leading)
        let rightPad = CGRect(x: right.minX, y: padTop, width: right.width + reserve, height: right.maxY - padTop - 4)
        return ZStack(alignment: .topLeading) {
            dsScreen(Self.topRegion, at: leftScreen)
            HingeSeam(axis: .vertical).place(stage.fold.frame)
            dsScreen(Self.touchRegion, at: rightScreen)
            if !model.physicalMode {
                controllerArea(.bookLeft, rect: leftPad) { ControllerLayout.bookLeft(leftPad.size, system: .ds, preset: $0) }
                controllerArea(.bookRight, rect: rightPad) { ControllerLayout.dsBookRight(rightPad.size, preset: $0) }
            } else {
                dsMenuKey.place(CGRect(x: right.midX - 18, y: rightPad.midY - 18, width: 36, height: 36))
            }
            dsTouchPad.place(rightScreen)
            toastView.place(CGRect(x: leftScreen.minX, y: leftScreen.minY + 6, width: leftScreen.width, height: 40))
            if model.menuOpen { menuPanel.place(right.insetBy(dx: 10, dy: 10)) }
            if model.editor != nil { editorPanel.place(left.insetBy(dx: 10, dy: 10)) }
        }
    }

    private var dsPortraitLayout: some View {
        let c = stage.canvas
        // Two 4:3 screens stacked, at most ~62 % of the height.
        let w = min(c.width - 24, c.height * 0.62 / 1.5)
        let stack = CGRect(x: c.midX - w / 2, y: c.minY + 10, width: w, height: w * 1.5 + 6)
        let topScreen = dsFit(in: CGRect(x: stack.minX, y: stack.minY, width: w, height: w * 0.75))
        let touch = dsFit(in: CGRect(x: stack.minX, y: topScreen.maxY + 6, width: w, height: w * 0.75), alignTop: true)
        let deck = CGRect(x: c.minX + 4, y: touch.maxY + 8, width: c.width - 8, height: c.maxY - touch.maxY - 12)
        return ZStack(alignment: .topLeading) {
            dsScreen(Self.topRegion, at: topScreen)
            dsScreen(Self.touchRegion, at: touch)
            if !model.physicalMode {
                controllerArea(.portrait, rect: deck) { ControllerLayout.deck(deck.size, system: .ds, preset: $0) }
            } else {
                dsMenuKey.place(CGRect(x: deck.midX - 18, y: deck.minY + 12, width: 36, height: 36))
            }
            dsTouchPad.place(touch)
            toastView.place(CGRect(x: topScreen.minX, y: topScreen.minY + 6, width: topScreen.width, height: 40))
            if model.menuOpen { menuPanel.place(c.insetBy(dx: 14, dy: c.height * 0.12)) }
            if model.editor != nil { editorPanel.place(topScreen) }
        }
    }

    private var dsLandscapeLayout: some View {
        let c = stage.canvas
        let physical = model.physicalMode
        let boxW = physical ? c.width - 16 : c.width * 0.68
        let each = CGSize(width: (boxW - 8) / 2, height: c.height - 16)
        let fit = ScreenFit.rect(video: Self.screen, in: each, mode: model.screenMode, displayScale: displayScale)
        let total = CGSize(width: fit.size.width * 2 + 8, height: fit.size.height)
        let topScreen = CGRect(x: c.midX - total.width / 2, y: c.midY - total.height / 2,
                               width: fit.size.width, height: fit.size.height)
        let touch = topScreen.offsetBy(dx: fit.size.width + 8, dy: 0)
        let both = topScreen.union(touch).offsetBy(dx: -c.minX, dy: -c.minY)
        return ZStack(alignment: .topLeading) {
            dsScreen(Self.topRegion, at: topScreen)
            dsScreen(Self.touchRegion, at: touch)
            if !physical {
                controllerArea(.landscape, rect: c) {
                    ControllerLayout.overlay(c.size, gameRect: both, system: .ds, preset: $0)
                }
            } else {
                dsMenuKey.place(CGRect(x: c.maxX - 44, y: c.minY + 6, width: 36, height: 36))
            }
            // Above the controller overlay: a touch that starts on the screen is always the stylus.
            dsTouchPad.place(touch)
            toastView.place(CGRect(x: topScreen.minX, y: topScreen.minY + 10, width: topScreen.width, height: 40))
            if model.menuOpen { menuPanel.place(c.insetBy(dx: c.width * 0.2, dy: 14)) }
            if model.editor != nil {
                editorPanel.place(CGRect(x: c.midX - min(270, c.width * 0.3), y: c.minY + 6, width: min(540, c.width * 0.6), height: c.height * 0.62))
            }
        }
    }

    // MARK: pieces

    /// The largest 4:3 rect for one screen inside `box` (integer-scaled when the mode allows),
    /// centred horizontally, and vertically unless `alignTop`.
    private func dsFit(in box: CGRect, alignTop: Bool = false) -> CGRect {
        let fit = ScreenFit.rect(video: Self.screen, in: box.size, mode: model.screenMode, displayScale: displayScale)
        let y = alignTop ? box.minY : box.midY - fit.size.height / 2
        return CGRect(x: box.midX - fit.size.width / 2, y: y, width: fit.size.width, height: fit.size.height)
    }

    private func dsScreen(_ region: ScreenRegion, at rect: CGRect) -> some View {
        let fit = ScreenFit.rect(video: Self.screen, in: rect.size, mode: model.screenMode, displayScale: displayScale)
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.screenGlass)
                .padding(-5)
                .shadow(color: .black.opacity(0.55), radius: 8, y: 4)
            GameScreen(frames: model.session.frames, mode: model.screenMode, integer: fit.integer, crop: region)
                .accessibilityLabel(region.isTouch ? "Touch screen picture" : "Top screen")
        }
        .place(rect)
    }

    private var dsTouchPad: some View {
        DSTouchPad(input: model.session.input) { point in
            #if DEBUG
            let count = (Int(model.stylusDebug.split(separator: " ").first ?? "0") ?? 0) + 1
            model.stylusDebug = "\(count) \(point.x) \(point.y)"
            #endif
        }
    }

    private var dsMenuKey: some View {
        Button { model.menuOpen = true } label: {
            Image(systemName: "ellipsis")
                .font(.rounded(.footnote, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .accessibilityLabel("Menu")
        .accessibilityIdentifier("ds.menu")
    }
}

/// The DS touch screen's input layer: exactly the screen's rect, mapping a finger to the
/// 256 x 192 screen's pixels. A press that starts here stays the stylus until it lifts.
struct DSTouchPad: View {
    let input: InputLatch
    /// Called when the stylus goes down (DEBUG readout).
    var onDown: (TouchPoint) -> Void = { _ in }
    @State private var down = false

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { v in
                            let p = Self.map(v.location, in: geo.size)
                            input.stylus.store(InputLatch.stylus(x: p.x, y: p.y), ordering: .relaxed)
                            if !down {
                                down = true
                                onDown(p)
                            }
                        }
                        .onEnded { _ in
                            input.stylus.store(0, ordering: .relaxed)
                            down = false
                        }
                )
        }
        .onDisappear { input.stylus.store(0, ordering: .relaxed) }
        .accessibilityElement()
        .accessibilityLabel("Touch screen")
        .accessibilityHint("Touch and drag to use the stylus")
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityIdentifier("ds.touchScreen")
    }

    /// A point in the view (size `size`) to DS touch-screen pixels, clamped onto the screen.
    static func map(_ p: CGPoint, in size: CGSize) -> TouchPoint {
        guard size.width > 0, size.height > 0 else { return TouchPoint(x: 0, y: 0) }
        let x = Int((p.x / size.width * 256).rounded(.down))
        let y = Int((p.y / size.height * 192).rounded(.down))
        return TouchPoint(x: min(max(x, 0), 255), y: min(max(y, 0), 191))
    }
}
