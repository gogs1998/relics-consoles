import CoreKit
import DuoKit
import SwiftUI

/// The player in every pose. Lays out from the stage's real rects (canvas, halves, fold band).
///
/// - Duo table (horizontal fold): the game on the top half, the full controller on the bottom half.
/// - Duo book (vertical fold, landscape): left page game + D-pad, right page companion + buttons.
/// - Flat / ordinary iPhone portrait: game above, controller below.
/// - Landscape: game centred, translucent controls in the margins.
/// No PoseDetector is used: a horizontal fold is always the laptop layout (never tent).
struct PlayerView: View {
    @State var model: PlayerModel
    let stage: DuoStage
    var onQuit: () -> Void
    @Environment(\.displayScale) var displayScale

    enum Arrangement { case table, book, portrait, landscape }

    var arrangement: Arrangement {
        if stage.fold.isActive && !stage.fold.frame.isEmpty {
            return stage.fold.axis == .horizontal ? .table : .book
        }
        return stage.canvas.width > stage.canvas.height ? .landscape : .portrait
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            BodySurface()
            if let error = model.errorMessage {
                errorView(error)
            } else if model.game.system == .ds {
                dsLayout   // two screens (DSPlayerView.swift)
            } else {
                switch arrangement {
                case .table: tableLayout
                case .book: bookLayout
                case .portrait: portraitLayout
                case .landscape: landscapeLayout
                }
            }
        }
        .frame(width: stage.bounds.width, height: stage.bounds.height)
        // Never hide the status bar on an iPhone Duo (Gordon, 14 Nov 2026): there it sits on the right edge and
        // hiding it leaves a black band, so the layout keeps clear of its safe-area inset instead. Hidden only on
        // ordinary iPhones (no real fold, never closed). Same rule as Relics: Phones.
        .statusBarHidden(UIDevice.current.userInterfaceIdiom == .phone && !Self.isDuo(stage))
        .persistentSystemOverlays(.hidden)
        .onChange(of: arrangement, initial: true) { _, new in
            switch new {
            case .table: model.pose = .table
            case .book: model.pose = .book
            case .portrait: model.pose = .portrait
            case .landscape: model.pose = .landscape
            }
        }
        .onChange(of: arrangement) { _, _ in
            model.controller.releaseAll()
            model.session.input.stylus.store(0, ordering: .relaxed)
        }
        // Close-to-sleep: the hinge's closed posture (never its angle) pauses and saves; opening
        // resumes exactly where play stopped. Every system goes through the same path.
        .onChange(of: lidClosed, initial: true) { _, closed in
            if closed { model.sleep(.lidClosed) } else { model.wake(.lidClosed) }
        }
        .overlay {
            if model.isAsleepWithLidClosed { SleepVeil(autoSaved: model.settings.autoSave).transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.3), value: model.isAsleepWithLidClosed)
        #if DEBUG
        .task { await debugLidCycle() }
        #endif
        .onChange(of: model.physicalMode) { _, physical in
            // The touch layout's auto-fire buttons don't carry over to a physical controller.
            if physical {
                model.controller.releaseAll()
                model.session.input.autoFire.store(0, ordering: .relaxed)
            }
        }
        .sheet(isPresented: Binding(get: { model.showingControllers }, set: { if !$0 { model.closeControllers() } })) {
            ControllersSheet(model: model)
        }
        .sheet(isPresented: Binding(get: { model.showingSettings }, set: { if !$0 { model.closeSettings() } })) {
            SettingsView()
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            Text("audio \(model.audioStats)")
                .font(.caption2)
                .opacity(0.01)
                .accessibilityIdentifier("debug.audio")
                .accessibilityValue(model.audioStats)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Text("touch \(model.controller.everPressed.rawValue)")
                .font(.caption2)
                .opacity(0.01)
                .accessibilityIdentifier("debug.touchInput")
                .accessibilityValue("\(model.controller.everPressed.rawValue)")
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            let p = model.controller.stickPeak
            Text("stick \(String(format: "%.2f %.2f", p.x, p.y))")
                .font(.caption2)
                .opacity(0.01)
                .accessibilityIdentifier("debug.stick")
                .accessibilityValue(String(format: "%.2f %.2f", p.x, p.y))
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            Text("stylus \(model.stylusDebug)")
                .font(.caption2)
                .opacity(0.01)
                .accessibilityIdentifier("debug.stylus")
                .accessibilityValue(model.stylusDebug)
                .allowsHitTesting(false)
        }
        #endif
    }

    /// A real iPhone Duo: the OS reports a division region (not DuoKit's DEBUG simulation), or the hinge says closed
    /// (the outer display has no division region).
    static func isDuo(_ stage: DuoStage) -> Bool {
        (!stage.fold.frame.isEmpty && !stage.fold.isSimulated) || stage.isClosed
    }

    /// The Duo is folded shut (DuoKit's hinge posture), or DEBUG `-lidCycle` says so.
    private var lidClosed: Bool {
        #if DEBUG
        if debugLidClosed { return true }
        #endif
        return stage.isClosed
    }

    #if DEBUG
    @State private var debugLidClosed = false

    /// DEBUG `-lidCycle 3,8`: pretend the lid closes 3 s after the player opens and opens again
    /// at 8 s (the simulator has no hinge).
    private func debugLidCycle() async {
        guard let spec = UserDefaults.standard.string(forKey: "lidCycle") else { return }
        let t = spec.split(separator: ",").compactMap { Double($0) }
        guard t.count == 2, t[1] > t[0] else { return }
        try? await Task.sleep(for: .seconds(t[0]))
        debugLidClosed = true
        try? await Task.sleep(for: .seconds(t[1] - t[0]))
        debugLidClosed = false
    }
    #endif

    // MARK: arrangements

    private var tableLayout: some View {
        let top = stage.farHalf
        let bottom = stage.nearHalf
        let bezel = top.insetBy(dx: 14, dy: 12)
        let deck = bottom.insetBy(dx: 8, dy: 6)
        let system = model.game.system, six = model.sixButtonPad
        return ZStack(alignment: .topLeading) {
            screen(in: bezel)
            HingeSeam(axis: .horizontal).place(stage.fold.frame)
            if model.physicalMode {
                // With a controller in hand, the bottom screen becomes a companion: states,
                // rewind / fast-forward, the menu and who's playing. (Spreading the game across
                // both halves would put the hinge through the picture.)
                ControllerCompanion(model: model, onQuit: onQuit).place(deck)
            } else if system == .n64 {
                deckBody(in: deck, area: .table)
            } else {
                // The spare room around the controller: quick slots with thumbnails along the
                // hinge, rewind and fast-forward either side, the menu key between Select and Start.
                let tray = ControllerLayout.tableTray(deck.size, shoulders: ControllerLayout.hasShoulders(system))
                deckBody(in: deck, area: .table, avoiding: tray) { size, preset in
                    ControllerLayout.tableDeck(size, system: system, sixButton: six, preset: preset)
                }
                QuickSlotTray(model: model).place(tray.offsetBy(dx: deck.minX, dy: deck.minY))
            }
            if model.menuOpen { menuPanel.place(bottom.insetBy(dx: 10, dy: 8)) }
            if model.editor != nil { editorPanel.place(top.insetBy(dx: 10, dy: 8)) }
        }
    }

    private var bookLayout: some View {
        let left = stage.farHalf
        let right = stage.nearHalf
        if model.physicalMode {
            // A controller: the game takes the whole left page; the right page is the companion.
            return AnyView(ZStack(alignment: .topLeading) {
                screen(in: left.insetBy(dx: 12, dy: 12))
                HingeSeam(axis: .vertical).place(stage.fold.frame)
                ControllerCompanion(model: model, onQuit: onQuit).place(right.insetBy(dx: 12, dy: 12))
                if model.menuOpen { menuPanel.place(right.insetBy(dx: 10, dy: 10)) }
            })
        }
        let leftScreen = CGRect(x: left.minX + 12, y: left.minY + 12, width: left.width - 24, height: left.height * 0.6 - 12)
        let leftPad = CGRect(x: left.minX, y: leftScreen.maxY + 4, width: left.width, height: left.maxY - leftScreen.maxY - 8)
        let rightTop = CGRect(x: right.minX + 12, y: right.minY + 12, width: right.width - 24, height: right.height * 0.6 - 12)
        let rightPad = CGRect(x: right.minX, y: rightTop.maxY + 4, width: right.width, height: right.maxY - rightTop.maxY - 8)
        let system = model.game.system, six = model.sixButtonPad
        return AnyView(ZStack(alignment: .topLeading) {
            screen(in: leftScreen)
            controllerArea(.bookLeft, rect: leftPad) { ControllerLayout.bookLeft(leftPad.size, system: system, sixButton: six, preset: $0) }
            HingeSeam(axis: .vertical).place(stage.fold.frame)
            CompanionPage(model: model, onQuit: onQuit).place(rightTop)
            controllerArea(.bookRight, rect: rightPad) { ControllerLayout.bookRight(rightPad.size, system: system, sixButton: six, preset: $0) }
            if model.menuOpen { menuPanel.place(right.insetBy(dx: 10, dy: 10)) }
            if model.editor != nil { editorPanel.place(rightTop) }
        })
    }

    private var portraitLayout: some View {
        let c = stage.canvas
        if model.physicalMode {
            let screenRect = CGRect(x: c.minX + 8, y: c.minY + 8, width: c.width - 16, height: min(c.height * 0.62, c.width * 0.9 + 34))
            return AnyView(ZStack(alignment: .topLeading) {
                screen(in: screenRect)
                ControllerCompanion(model: model, onQuit: onQuit, compact: true)
                    .place(CGRect(x: c.minX + 8, y: screenRect.maxY + 10, width: c.width - 16, height: c.maxY - screenRect.maxY - 18))
                if model.menuOpen { menuPanel.place(c.insetBy(dx: 14, dy: c.height * 0.12)) }
            })
        }
        let screenH = min(c.width * 0.86 + 34, c.height * 0.5)
        let bezel = CGRect(x: c.minX + 12, y: c.minY + 10, width: c.width - 24, height: screenH)
        let deck = CGRect(x: c.minX + 4, y: bezel.maxY + 10, width: c.width - 8, height: c.maxY - bezel.maxY - 14)
        return AnyView(ZStack(alignment: .topLeading) {
            screen(in: bezel)
            deckBody(in: deck, area: .portrait)
            if model.menuOpen { menuPanel.place(c.insetBy(dx: 14, dy: c.height * 0.12)) }
            if model.editor != nil { editorPanel.place(bezel) }
        })
    }

    private var landscapeLayout: some View {
        let c = stage.canvas
        // With a controller: the whole height, pixel-perfect when "Auto" (integer scaling).
        // Touch: the game gets 62% of the width on phones; on iPad-size canvases the side controls
        // need less of the width, so the game gets 74%.
        let physical = model.physicalMode
        let mode: ScreenMode = physical && model.screenMode == .auto ? .integer : model.screenMode
        let box = physical ? CGSize(width: c.width - 16, height: c.height - 8) : CGSize(width: c.width * (c.width >= 1000 ? 0.74 : 0.62), height: c.height - 16)
        let fit = ScreenFit.rect(video: model.videoSize, in: box, mode: mode, displayScale: displayScale)
        let game = CGRect(x: c.midX - fit.size.width / 2, y: c.midY - fit.size.height / 2,
                          width: fit.size.width, height: fit.size.height)
        let system = model.game.system, six = model.sixButtonPad
        let gameInArea = game.offsetBy(dx: -c.minX, dy: -c.minY)
        return ZStack(alignment: .topLeading) {
            GameScreen(frames: model.session.frames, mode: mode, integer: fit.integer)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityElement()
                .accessibilityLabel("Game screen")
                .accessibilityIdentifier("game.screen")
                .place(game)
            if !physical {
                controllerArea(.landscape, rect: c, avoiding: gameInArea) {
                    ControllerLayout.overlay(c.size, gameRect: gameInArea, system: system, sixButton: six, preset: $0)
                }
            }
            toastView.place(CGRect(x: game.minX, y: game.minY + 10, width: game.width, height: max(40, game.height - 20)))
            if physical && !model.menuOpen {
                // With the game edge to edge, a small menu key stays reachable by touch.
                Button { model.menuOpen = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.rounded(.footnote, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .accessibilityLabel("Menu")
                .accessibilityIdentifier("landscape.menu")
                .place(CGRect(x: c.maxX - 44, y: c.minY + 6, width: 36, height: 36))
            }
            if model.menuOpen { menuPanel.place(c.insetBy(dx: c.width * 0.2, dy: 14)) }
            if model.editor != nil {
                editorPanel.place(CGRect(x: c.midX - min(270, c.width * 0.3), y: c.minY + 6, width: min(540, c.width * 0.6), height: c.height * 0.62))
            }
        }
    }

    // MARK: pieces

    private func screen(in rect: CGRect) -> some View {
        ScreenBezel(model: model, rect: rect, displayScale: displayScale) {
            toastView
        }
        .place(rect)
    }

    private func deckBody(in rect: CGRect, area: ControllerArea, avoiding: CGRect? = nil,
                          layout: ((CGSize, LayoutPreset) -> [Control])? = nil) -> some View {
        let system = model.game.system, six = model.sixButtonPad, size = rect.size
        return ZStack(alignment: .topLeading) {
            if system != .n64 {   // the N64 deck uses that corner for the C buttons
                VentSlots(columns: 5)
                    .position(x: rect.width * 0.86, y: rect.height * 0.88)
            }
            controllerArea(area, rect: CGRect(origin: .zero, size: size), avoiding: avoiding) {
                layout?(size, $0) ?? ControllerLayout.deck(size, system: system, sixButton: six, preset: $0)
            }
        }
        .place(rect)
    }

    /// The touch controller for one area: the saved layout (game, then system), or the preset's
    /// defaults; in edit mode, the editor for that area instead.
    @ViewBuilder
    func controllerArea(_ area: ControllerArea, rect: CGRect, avoiding: CGRect? = nil,
                                defaults: @escaping (LayoutPreset) -> [Control]) -> some View {
        if let editor = model.editor {
            LayoutEditorArea(editor: editor, model: model.controller, area: area, size: rect.size, avoiding: avoiding,
                             defaults: defaults)
                .place(rect)
        } else {
            let r = model.layouts.controls(model.game.system, area, game: model.game.id, size: rect.size, defaults: defaults)
            let controls = model.game.system == .n64
                ? N64Layout.camera(r.controls, cStick: model.layouts.options(.n64, game: model.game.id).cStick ?? false)
                : r.controls
            ControllerView(controls: controls, model: model.controller, settings: r.settings, floating: area == .landscape)
                .place(rect)
        }
    }

    var editorPanel: some View {
        Group {
            if let editor = model.editor {
                ScrollView {
                    LayoutEditorPanel(editor: editor, onDone: { model.endEditingControls() },
                                      onCancel: { model.endEditingControls() })
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    /// The toast, and below it any lasting notice about the machine (with an OK to dismiss it).
    var toastView: some View {
        VStack(spacing: 8) {
            toastCapsule
            noticeCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder var noticeCard: some View {
        if let notice = model.notice {
            VStack(alignment: .leading, spacing: 8) {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.rounded(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button("OK") { model.notice = nil }
                    .font(.rounded(.footnote, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Dismiss the message")
                    .accessibilityIdentifier("notice.ok")
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("player.notice")
        }
    }

    @ViewBuilder var toastCapsule: some View {
        if let toast = model.toast {
            HStack(spacing: 10) {
                Text(toast)
                    .font(.rounded(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                if model.toastOffersUndo {
                    Button("Undo") { model.undoQuickLoad() }
                        .font(.rounded(.footnote, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                        .accessibilityLabel("Undo the load")
                        .accessibilityIdentifier("toast.undo")
                }
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .transition(.move(edge: .top).combined(with: .opacity))
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    var menuPanel: some View {
        PlayerMenu(model: model, onQuit: onQuit)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.rounded(.largeTitle))
                .foregroundStyle(Theme.ember)
            Text(message)
                .font(.rounded(.body))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Button("Back to the shelf", action: onQuit)
                .buttonStyle(EmberButtonStyle())
        }
        .padding(32)
        .frame(width: stage.bounds.width, height: stage.bounds.height)
    }
}

/// The screen: dark glass in a bevelled surround, the game centred at its fitted size, a status LED.
struct ScreenBezel<Overlay: View>: View {
    let model: PlayerModel
    let rect: CGRect
    let displayScale: CGFloat
    @ViewBuilder var overlay: () -> Overlay
    @State private var ledGlow = false

    var body: some View {
        let inner = CGSize(width: rect.width - 20, height: rect.height - 34)
        let fit = ScreenFit.rect(video: model.videoSize, in: inner, mode: model.screenMode, displayScale: displayScale)
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.screenGlass)
                .padding(EdgeInsets(top: 8, leading: 8, bottom: 24, trailing: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.black.opacity(0.8), lineWidth: 2)
                        .padding(EdgeInsets(top: 8, leading: 8, bottom: 24, trailing: 8))
                )
            VStack(spacing: 0) {
                ZStack {
                    GameScreen(frames: model.session.frames, mode: model.screenMode, integer: fit.integer)
                        .frame(width: fit.size.width, height: fit.size.height)
                        .accessibilityElement()
                        .accessibilityLabel("Game screen")
                        .accessibilityIdentifier("game.screen")
                    // A faint glass sheen across the top of the screen.
                    LinearGradient(colors: [Color.white.opacity(0.05), .clear], startPoint: .top, endPoint: .center)
                        .frame(width: fit.size.width, height: fit.size.height)
                        .allowsHitTesting(false)
                }
                .frame(width: inner.width, height: inner.height)
                .padding(.top, 10)
                HStack(spacing: 7) {
                    Circle()
                        .fill(Theme.ember)
                        .frame(width: 6, height: 6)
                        .shadow(color: Theme.ember.opacity(ledGlow ? 0.95 : 0.35), radius: ledGlow ? 6 : 2)
                        .opacity(ledGlow ? 1 : 0.7)
                        .accessibilityHidden(true)
                    // Uppercase, but keep the micro sign: "µCity".uppercased() would turn it into a Greek capital Mu ("ΜCITY").
                    Text(model.game.title.map { $0 == "µ" ? "µ" : $0.uppercased() }.joined())
                        .font(.rounded(.caption2, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.inkDim)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if model.fastForward { badge("FAST", symbol: "forward.fill") }
                    if model.rewinding { badge("REWIND", symbol: "backward.fill") }
                }
                .padding(.horizontal, 16)
                .frame(height: 24)
            }
            overlay()
        }
        .onChange(of: model.savingPulse) { _, _ in
            withAnimation(.easeOut(duration: 0.15)) { ledGlow = true }
            withAnimation(.easeIn(duration: 0.6).delay(0.25)) { ledGlow = false }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
    }

    private func badge(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.rounded(.caption2, weight: .heavy))
            .foregroundStyle(Theme.ember)
    }
}

/// The dark band where the halves meet, with two hinge knuckles.
struct HingeSeam: View {
    enum Axis { case horizontal, vertical }
    var axis: Axis

    var body: some View {
        GeometryReader { geo in
            let horizontal = axis == .horizontal
            ZStack {
                LinearGradient(colors: [Color.black.opacity(0.85), Color(white: 0.05), Color.black.opacity(0.85)],
                               startPoint: horizontal ? .top : .leading, endPoint: horizontal ? .bottom : .trailing)
                ForEach([0.18, 0.82], id: \.self) { f in
                    Capsule()
                        .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.1)],
                                             startPoint: horizontal ? .top : .leading,
                                             endPoint: horizontal ? .bottom : .trailing))
                        .frame(width: horizontal ? geo.size.width * 0.12 : geo.size.width * 0.5,
                               height: horizontal ? geo.size.height * 0.5 : geo.size.height * 0.12)
                        .position(x: horizontal ? geo.size.width * f : geo.size.width / 2,
                                  y: horizontal ? geo.size.height / 2 : geo.size.height * f)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Sizes and positions a view at an absolute rect inside a top-leading ZStack.
    func place(_ r: CGRect) -> some View {
        frame(width: max(0, r.width), height: max(0, r.height))
            .position(x: r.midX, y: r.midY)
    }
}

/// Shown while the lid is closed: the game is paused and saved.
struct SleepVeil: View {
    var autoSaved = true
    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
            VStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill")
                    .font(.rounded(.largeTitle))
                    .foregroundStyle(Theme.sand)
                Text("Sleeping")
                    .font(.rounded(.title3, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(autoSaved ? "Saved. Open to carry on where you left off." : "Paused. Open to carry on where you left off.")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.inkDim)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("player.sleeping")
    }
}
