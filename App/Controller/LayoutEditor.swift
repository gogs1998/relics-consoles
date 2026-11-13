import CoreKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Edit mode for the touch controller: drag, resize, opacity, haptics, auto-fire, snap to grid,
/// presets, scope (this system / this game), reset, import and export. Works on every controller
/// area the current pose shows (book pose edits both pages together).
@MainActor
@Observable
final class LayoutEditor {
    let system: SystemID
    let gameID: String
    var scopeGame: Bool
    var preset: LayoutPreset = .standard
    var settings = ControlSettings()
    var snap = true
    static let grid: CGFloat = 8

    private(set) var controls: [ControllerArea: [Control]] = [:]
    private(set) var sizes: [ControllerArea: CGSize] = [:]
    /// Per area, a rect no control may overlap (the game, when controls share its area: landscape).
    private(set) var avoid: [ControllerArea: CGRect] = [:]
    @ObservationIgnored private var defaults: [ControllerArea: (LayoutPreset) -> [Control]] = [:]
    var selection: (area: ControllerArea, id: String)?
    var message: String?
    /// The pose the player is in: the editor edits that pose's layout (set by the player view).
    var pose: LayoutPose = .portrait

    private let store: LayoutStore

    init(system: SystemID, gameID: String, store: LayoutStore) {
        self.system = system
        self.gameID = gameID
        self.store = store
        scopeGame = store.hasGameLayout(system, game: gameID)
    }

    /// Called by each area's editor view when it appears (and when its size changes).
    func register(_ area: ControllerArea, size: CGSize, avoiding: CGRect? = nil,
                  defaults make: @escaping (LayoutPreset) -> [Control]) {
        defaults[area] = make
        avoid[area] = avoiding
        if let old = sizes[area], let list = controls[area] {
            // A size change (rotation, multitasking): keep the unsaved edits, rescaled.
            guard old != size, old.width > 0, old.height > 0 else { return }
            controls[area] = list.map { $0.toUnit(old).fromUnit(size) }
            sizes[area] = size
            return
        }
        sizes[area] = size
        let r = store.controls(system, area, game: gameID, size: size, defaults: make)
        controls[area] = r.controls
        if !area.isSecondary {   // book pose / DS table: the areas share one layout's settings; take the main one's
            settings = r.settings
            preset = r.preset
        }
    }

    func selected() -> Control? {
        guard let s = selection else { return nil }
        return controls[s.area]?.first { $0.id == s.id }
    }

    private func update(_ area: ControllerArea, _ id: String, _ change: (inout Control) -> Void) {
        guard var list = controls[area], let i = list.firstIndex(where: { $0.id == id }) else { return }
        let before = list[i].frame
        change(&list[i])
        list[i].frame = clamp(list[i].frame, in: sizes[area] ?? .zero)
        if let keepOut = avoid[area], list[i].frame.intersects(keepOut) {
            list[i].frame = pushedOut(list[i].frame, from: keepOut, in: sizes[area] ?? .zero) ?? before
        }
        controls[area] = list
    }

    /// Moves `r` sideways off `keepOut` (to the nearer side), or nil if it doesn't fit there.
    private func pushedOut(_ r: CGRect, from keepOut: CGRect, in size: CGSize) -> CGRect? {
        var f = r
        let leftRoom = keepOut.minX, rightRoom = size.width - keepOut.maxX
        if r.midX < keepOut.midX, r.width <= leftRoom {
            f.origin.x = keepOut.minX - r.width
        } else if r.width <= rightRoom {
            f.origin.x = keepOut.maxX
        } else if r.width <= leftRoom {
            f.origin.x = keepOut.minX - r.width
        } else {
            return nil
        }
        return f.intersects(keepOut) ? nil : f
    }

    private func clamp(_ r: CGRect, in size: CGSize) -> CGRect {
        var f = r
        f.size.width = min(f.width, size.width)
        f.size.height = min(f.height, size.height)
        f.origin.x = min(max(0, f.minX), size.width - f.width)
        f.origin.y = min(max(0, f.minY), size.height - f.height)
        return f
    }

    private func snapped(_ v: CGFloat) -> CGFloat { snap ? (v / Self.grid).rounded() * Self.grid : v }

    func move(_ area: ControllerArea, _ id: String, origin: CGPoint) {
        update(area, id) { $0.frame.origin = CGPoint(x: snapped(origin.x), y: snapped(origin.y)) }
    }

    /// Sets the width (keeping the shape), centred where it was. Never below 32 pt drawn.
    func resize(_ area: ControllerArea, _ id: String, width: CGFloat) {
        update(area, id) { c in
            let aspect = c.frame.height / max(1, c.frame.width)
            let w = max(32, min(260, snap ? snapped(width) : width))
            let centre = CGPoint(x: c.frame.midX, y: c.frame.midY)
            c.frame = CGRect(x: centre.x - w / 2, y: centre.y - w * aspect / 2, width: w, height: w * aspect)
        }
    }

    func setOpacity(_ v: Double) { if let s = selection { update(s.area, s.id) { $0.opacity = v } } }
    func setHaptic(_ v: Double) { if let s = selection { update(s.area, s.id) { $0.haptic = v } } }
    func setAutoFire(_ on: Bool) { if let s = selection { update(s.area, s.id) { $0.autoFire = on } } }
    func setHidden(_ hidden: Bool) { if let s = selection { update(s.area, s.id) { $0.hidden = hidden ? true : nil } } }

    func applyPreset(_ p: LayoutPreset) {
        preset = p
        for (area, make) in defaults { controls[area] = make(p) }
        selection = nil
    }

    /// Back to the built-in layout (nothing is written until Done; Cancel keeps the old one).
    func reset() {
        settings = ControlSettings()
        applyPreset(.standard)
        message = "Back to the standard layout. Done saves it; Cancel keeps the old one"
    }

    /// Other poses that have a saved layout to copy (for the current scope: this game's, else
    /// the system's).
    func copySources() -> [LayoutPose] {
        LayoutPose.allCases.filter { p in
            p != pose && p.areas(system).contains { store.resolve(system, $0, game: gameID) != nil }
        }
    }

    /// Copies another pose's saved arrangement onto this pose (Done saves it; Cancel discards it).
    func copy(from source: LayoutPose) {
        let saved = source.areas(system).compactMap { area in store.resolve(system, area, game: gameID).map { (area, $0) } }
        guard let main = saved.first(where: { !$0.0.isSecondary }) ?? saved.first else {
            message = "\(source.title) has no layout of its own yet"
            return
        }
        if main.1.preset != preset { applyPreset(main.1.preset) }
        let targets = pose.areas(system).filter { sizes[$0] != nil }
        let sources = saved.map { LayoutCopier.Source(area: $0.0, controls: $0.1.controls, areaSize: $0.1.areaSize) }
        let current = Dictionary(uniqueKeysWithValues: targets.map { ($0, controls[$0] ?? []) })
        let copied = LayoutCopier.copy(from: sources, into: current, sizes: sizes)
        for (area, list) in copied { controls[area] = list }
        // Anything that landed on the game (landscape) is pushed off it, or keeps its old place.
        for area in targets {
            guard let keepOut = avoid[area], let size = sizes[area] else { continue }
            controls[area] = (controls[area] ?? []).map { c in
                guard c.frame.intersects(keepOut) else { return c }
                var moved = c
                moved.frame = pushedOut(c.frame, from: keepOut, in: size)
                    ?? current[area]?.first { $0.id == c.id }?.frame ?? c.frame
                return moved
            }
        }
        settings = main.1.settings
        selection = nil
        message = "Copied from \(source.title). Done saves it; Cancel keeps the old one"
    }

    func save() {
        for (area, list) in controls {
            guard let size = sizes[area] else { continue }
            store.save(SavedLayout(system: system, area: area, gameID: scopeGame ? gameID : nil, preset: preset,
                                   controls: list.map { $0.toUnit(size) }, settings: settings, areaSize: size))
        }
        // Switching a game back to "all games" removes its own layout so the system's applies.
        if !scopeGame {
            for area in ControllerArea.allCases { store.remove(system, area, game: gameID) }
        }
    }

    /// The layouts being edited, as a shareable file (exporting saves nothing).
    func exportDocument() -> LayoutDocument {
        let layouts = controls.compactMap { area, list -> SavedLayout? in
            guard let size = sizes[area] else { return nil }
            return SavedLayout(system: system, area: area, gameID: nil, preset: preset,
                               controls: list.map { $0.toUnit(size) }, settings: settings, areaSize: size)
        }
        return LayoutDocument(bundle: LayoutBundle(system: system, layouts: layouts))
    }

    /// Loads a shared file into the editor (Done saves it; Cancel discards it).
    func importBundle(_ b: LayoutBundle) {
        guard b.system == system else {
            message = "That layout is for \(b.system.displayName), not \(system.displayName)"
            return
        }
        var n = 0
        for l in b.layouts.map(\.sanitised) {
            guard let size = sizes[l.area] else { continue }
            controls[l.area] = l.controls.isEmpty ? defaults[l.area]?(l.preset) ?? [] : l.controls.map { $0.fromUnit(size) }
            settings = l.settings
            preset = l.preset
            n += 1
        }
        selection = nil
        message = n == 0 ? "Nothing in that file fits this screen" : "Imported. Done saves it; Cancel discards it"
    }
}

/// One controller area in edit mode: a dotted grid, the controls (drag to move, pinch to resize,
/// tap to select), and the area's bounds as the limit.
struct LayoutEditorArea: View {
    let editor: LayoutEditor
    let model: ControllerModel
    let area: ControllerArea
    let size: CGSize
    /// The game's rect inside this area, when the area surrounds the game (landscape).
    var avoiding: CGRect?
    let defaults: (LayoutPreset) -> [Control]

    @State private var dragStart: [String: CGPoint] = [:]
    @State private var pinchStart: CGFloat?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.ember.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            if editor.snap {
                Canvas { ctx, s in
                    var y: CGFloat = LayoutEditor.grid
                    while y < s.height {
                        var x: CGFloat = LayoutEditor.grid
                        while x < s.width {
                            ctx.fill(Path(ellipseIn: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)),
                                     with: .color(.white.opacity(0.12)))
                            x += LayoutEditor.grid * 2
                        }
                        y += LayoutEditor.grid * 2
                    }
                }
                .allowsHitTesting(false)
            }
            ForEach(editor.controls[area] ?? []) { c in
                let isSelected = editor.selection?.area == area && editor.selection?.id == c.id
                ControlArt(control: c, model: model, outerRing: editor.settings.stickOuterRing)
                    .frame(width: c.frame.width, height: c.frame.height)
                    .opacity(c.isHidden ? 0.15 : max(0.25, c.opacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Theme.ember : Color.white.opacity(0.25),
                                          style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isSelected ? [] : [3, 3]))
                            .padding(-4)
                    )
                    .contentShape(Rectangle())
                    .position(x: c.frame.midX, y: c.frame.midY)
                    .gesture(drag(c))
                    .simultaneousGesture(pinch(c))
                    .onTapGesture { editor.selection = (area, c.id) }
                    .accessibilityElement()
                    .accessibilityLabel("Move \(name(c))")
                    .accessibilityAction(named: "Move left") { editor.move(area, c.id, origin: CGPoint(x: c.frame.minX - 8, y: c.frame.minY)) }
                    .accessibilityAction(named: "Move right") { editor.move(area, c.id, origin: CGPoint(x: c.frame.minX + 8, y: c.frame.minY)) }
                    .accessibilityAction(named: "Move up") { editor.move(area, c.id, origin: CGPoint(x: c.frame.minX, y: c.frame.minY - 8)) }
                    .accessibilityAction(named: "Move down") { editor.move(area, c.id, origin: CGPoint(x: c.frame.minX, y: c.frame.minY + 8)) }
                    .accessibilityAction(named: "Bigger") { editor.resize(area, c.id, width: c.frame.width + 8) }
                    .accessibilityAction(named: "Smaller") { editor.resize(area, c.id, width: c.frame.width - 8) }
                    .accessibilityIdentifier("edit.\(c.id)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear { editor.register(area, size: size, avoiding: avoiding, defaults: defaults) }
        .onChange(of: size) { _, new in editor.register(area, size: new, avoiding: avoiding, defaults: defaults) }
    }

    private func drag(_ c: Control) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                editor.selection = (area, c.id)
                let start = dragStart[c.id] ?? c.frame.origin
                if dragStart[c.id] == nil { dragStart[c.id] = start }
                editor.move(area, c.id, origin: CGPoint(x: start.x + v.translation.width, y: start.y + v.translation.height))
            }
            .onEnded { _ in dragStart[c.id] = nil }
    }

    private func pinch(_ c: Control) -> some Gesture {
        MagnifyGesture()
            .onChanged { v in
                editor.selection = (area, c.id)
                let start = pinchStart ?? c.frame.width
                if pinchStart == nil { pinchStart = start }
                editor.resize(area, c.id, width: start * v.magnification)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func name(_ c: Control) -> String {
        switch c.kind {
        case .dpad: "direction pad"
        case .face(_, let l, _): FaceButtonView.spoken(l)
        case .pill(_, let l): l.capitalized
        case .shoulder(_, let l): "\(l) shoulder"
        case .combo(_, let l): l == "AB" ? "A and B zone" : "row zone"
        case .menu: "menu key"
        case .fastForward: "fast-forward key"
        case .rewind: "rewind key"
        case .stick: "analog stick"
        }
    }
}

/// The editing panel: presets, scope, snap, reset, import/export, and the selected control's
/// size, opacity, haptics and auto-fire, or the layout-wide D-pad and auto-fire settings.
struct LayoutEditorPanel: View {
    let editor: LayoutEditor
    var onDone: () -> Void
    var onCancel: () -> Void
    @State private var exporting = false
    @State private var importing = false
    @State private var document: LayoutDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Edit controls")
                        .font(.rounded(.headline, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Label("\(editor.pose.title) layout", systemImage: editor.pose.symbol)
                        .font(.rounded(.caption, weight: .semibold))
                        .foregroundStyle(Theme.ember)
                        .accessibilityLabel("Editing the \(editor.pose.title) layout")
                        .accessibilityIdentifier("edit.pose")
                }
                Spacer(minLength: 4)
                Button("Cancel", action: onCancel).buttonStyle(ChipStyle(selected: false))
                Button {
                    editor.save()
                    onDone()
                } label: { Label("Done", systemImage: "checkmark") }
                .buttonStyle(EmberButtonStyle())
                .accessibilityIdentifier("edit.done")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(LayoutPreset.available(for: editor.system)) { p in
                            Button(p.title) { editor.applyPreset(p) }
                        }
                    } label: { Label(editor.preset.title, systemImage: "square.grid.3x2") }
                    .buttonStyle(ChipStyle(selected: false))
                    .accessibilityIdentifier("edit.preset")
                    Menu {
                        Button("All \(editor.system.displayName) games") { editor.scopeGame = false }
                        Button("This game only") { editor.scopeGame = true }
                    } label: { Label(editor.scopeGame ? "This game" : "All games", systemImage: "scope") }
                    .buttonStyle(ChipStyle(selected: false))
                    Menu {
                        let sources = editor.copySources()
                        if sources.isEmpty {
                            Text("No other pose has its own layout yet")
                        }
                        ForEach(sources) { p in
                            Button { editor.copy(from: p) } label: { Label(p.title, systemImage: p.symbol) }
                        }
                    } label: { Label("Copy from", systemImage: "doc.on.doc") }
                    .buttonStyle(ChipStyle(selected: false))
                    .accessibilityLabel("Copy the layout from another pose")
                    .accessibilityIdentifier("edit.copyFrom")
                    Button { editor.snap.toggle() } label: { Label("Snap", systemImage: "grid") }
                        .buttonStyle(ChipStyle(selected: editor.snap))
                    Button { editor.reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(ChipStyle(selected: false))
                    Button {
                        document = editor.exportDocument()
                        exporting = true
                    } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .buttonStyle(ChipStyle(selected: false))
                    Button { importing = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                        .buttonStyle(ChipStyle(selected: false))
                }
            }
            if let c = editor.selected() {
                selectedControls(c)
            } else {
                layoutSettings
            }
            if let m = editor.message {
                Text(m).font(.rounded(.caption)).foregroundStyle(Theme.inkDim)
                    .task(id: m) { try? await Task.sleep(for: .seconds(3)); editor.message = nil }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.graphite.opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
        )
        .fileExporter(isPresented: $exporting, document: document, contentType: .foldbackLayout,
                      defaultFilename: "\(editor.system.rawValue)-controls") { _ in }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.foldbackLayout, .json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let b = try? LayoutDocument.decode(data) {
                editor.importBundle(b)
            } else {
                editor.message = "That file isn't a Relics Games layout"
            }
        }
    }

    private func selectedControls(_ c: Control) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            slider("Size", value: Binding(get: { Double(c.frame.width) }, set: { v in
                if let s = editor.selection { editor.resize(s.area, s.id, width: CGFloat(v)) }
            }), range: 32...260)
            slider("Opacity", value: Binding(get: { c.opacity }, set: { editor.setOpacity($0) }), range: 0.15...1)
            slider("Haptics", value: Binding(get: { c.haptic }, set: { editor.setHaptic($0) }), range: 0...1)
            Toggle(isOn: Binding(get: { !c.isHidden }, set: { editor.setHidden(!$0) })) {
                Text("Show this control").font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            .tint(Theme.ember)
            if !c.buttons.isEmpty, !c.buttons.contains(.start) {
                Toggle(isOn: Binding(get: { c.autoFire }, set: { editor.setAutoFire($0) })) {
                    Text("Auto-fire while held").font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.ink)
                }
                .tint(Theme.ember)
            }
            Button("Deselect") { editor.selection = nil }
                .buttonStyle(ChipStyle(selected: false, dense: true))
        }
    }

    private var layoutSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tap a control to change it. Drag to move, pinch to resize.")
                .font(.rounded(.caption)).foregroundStyle(Theme.inkDim)
            HStack {
                Text("Diagonals").font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.ink)
                Picker("Diagonals", selection: Binding(get: { editor.settings.diagonalDegrees }, set: { editor.settings.diagonalDegrees = $0 })) {
                    Text("Off").tag(0.0)
                    Text("Narrow").tag(24.0)
                    Text("Normal").tag(36.0)
                    Text("Wide").tag(45.0)
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Text("Auto-fire").font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.ink)
                Picker("Auto-fire rate", selection: Binding(get: { editor.settings.autoFireHz }, set: { editor.settings.autoFireHz = $0 })) {
                    Text("5/s").tag(5.0)
                    Text("10/s").tag(10.0)
                    Text("15/s").tag(15.0)
                    Text("30/s").tag(30.0)
                }
                .pickerStyle(.segmented)
            }
            slider("Haptics (all)", value: Binding(get: { editor.settings.hapticLevel }, set: { editor.settings.hapticLevel = $0 }), range: 0...1)
            if editor.system == .n64 { stickSettings }
        }
    }

    /// The analog stick's tuning (Nintendo 64): true analog always; these shape it.
    private var stickSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Analog stick").font(.rounded(.subheadline, weight: .heavy)).foregroundStyle(Theme.ink)
                .padding(.top, 4)
            // Sensitivity: how far the thumb travels for full deflection (shown so right = more sensitive).
            slider("Sensitivity", value: Binding(get: { 1.4 - editor.settings.stickRange },
                                                 set: { editor.settings.stickRange = 1.4 - $0 }), range: 0.4...1.0)
                .accessibilityIdentifier("edit.stickSensitivity")
                .accessibilityValue("Full tilt at \(Int((editor.settings.stickRange * 100).rounded())) percent of the stick")
            slider("Dead zone", value: Binding(get: { editor.settings.stickDeadZone },
                                               set: { editor.settings.stickDeadZone = $0 }), range: 0...0.4)
                .accessibilityIdentifier("edit.stickDeadZone")
                .accessibilityValue("\(Int((editor.settings.stickDeadZone * 100).rounded())) percent")
            Toggle(isOn: Binding(get: { editor.settings.stickOuterRing }, set: { editor.settings.stickOuterRing = $0 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Outer ring").font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text("Touching the ring is always full tilt").font(.rounded(.caption2)).foregroundStyle(Theme.inkDim)
                }
            }
            .tint(Theme.ember)
            .accessibilityIdentifier("edit.stickRing")
            Toggle(isOn: Binding(get: { editor.settings.stickRecentre }, set: { editor.settings.stickRecentre = $0 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Centre where I touch").font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text("The stick starts under your thumb").font(.rounded(.caption2)).foregroundStyle(Theme.inkDim)
                }
            }
            .tint(Theme.ember)
            .accessibilityIdentifier("edit.stickRecentre")
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.ink)
                .frame(width: 96, alignment: .leading)
            Slider(value: value, in: range).tint(Theme.ember)
        }
    }
}
