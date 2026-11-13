import CoreKit
import DuoKit
import SwiftUI
import UniformTypeIdentifiers

/// The shelf. On the Duo the top half (table) or right page (book) shows the selected game large.
struct LibraryView: View {
    let store: GameStore
    let stage: DuoStage
    var onPlay: (GameRecord) -> Void

    @State private var importing = false
    @State private var showingAbout = false
    @State private var selected: GameRecord.ID?
    @State private var renaming: GameRecord?
    @State private var newTitle = ""

    private var focus: GameRecord? {
        store.games.first { $0.id == selected } ?? store.recentlyPlayed.first ?? store.sortedGames.first
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            BodySurface()
            if stage.fold.isActive && !stage.fold.frame.isEmpty && !store.games.isEmpty {
                if stage.fold.axis == .horizontal {
                    hero.place(stage.farHalf.insetBy(dx: 14, dy: 12))
                    HingeSeam(axis: .horizontal).place(stage.fold.frame)
                    shelf(compactHeader: true).place(stage.nearHalf)
                } else {
                    shelf(compactHeader: true).place(stage.farHalf)
                    HingeSeam(axis: .vertical).place(stage.fold.frame)
                    hero.place(stage.nearHalf.insetBy(dx: 14, dy: 14))
                }
            } else {
                shelf(compactHeader: false).place(stage.canvas)
            }
        }
        .frame(width: stage.bounds.width, height: stage.bounds.height)
        .sheet(isPresented: $showingAbout) { AboutView() }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { store.importFiles(urls) }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Save") { if let g = renaming { store.rename(g.id, to: newTitle) } }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if let msg = store.lastImportMessage {
                Text(msg)
                    .font(.rounded(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                    .padding(.bottom, 24)
                    .task(id: msg) {
                        try? await Task.sleep(for: .seconds(3))
                        store.lastImportMessage = nil
                    }
            }
        }
    }

    static var importTypes: [UTType] {
        var exts = ["nes", "gb", "gbc", "gba", "sfc", "smc", "md", "gen", "smd", "nds"]
        if SystemID.n64.isAvailableInThisBuild { exts += ["z64", "n64", "v64"] }
        let ids = exts.map { "com.iqlabs.duoemulator.\($0)" }
        return ids.compactMap { UTType($0) } + [.zip, .data]
    }

    // MARK: shelf

    private func shelf(compactHeader: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(compact: compactHeader)
                if store.games.isEmpty {
                    EmptyShelf { importing = true }
                } else {
                    if !store.recentlyPlayed.isEmpty && !compactHeader {
                        section("Continue") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(store.recentlyPlayed) { g in
                                        card(g, width: 200)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    ForEach(store.systemsPresent) { system in
                        section(system.displayName) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: compactHeader ? 128 : 150), spacing: 14)],
                                      spacing: 16) {
                                ForEach(store.games(for: system)) { g in card(g, width: nil) }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    Text("Plays games you own. Nothing is included or downloaded.")
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.inkDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Shelf")
                    .font(.rounded(compact ? .title2 : .largeTitle, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                if !compact {
                    Text(store.games.isEmpty ? "No games yet" : "\(store.games.count) games")
                        .font(.rounded(.subheadline))
                        .foregroundStyle(Theme.inkDim)
                }
            }
            Spacer()
            Button { showingAbout = true } label: {
                Image(systemName: "info.circle").font(.rounded(.title3)).foregroundStyle(Theme.inkDim)
            }
            .accessibilityLabel("About and acknowledgements")
            .padding(.trailing, 6)
            Button { importing = true } label: { Label("Add games", systemImage: "plus") }
                .buttonStyle(EmberButtonStyle())
        }
        .padding(.horizontal, 20)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.rounded(.caption, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(Theme.inkDim)
                .padding(.horizontal, 20)
            content()
        }
    }

    private func card(_ g: GameRecord, width: CGFloat?) -> some View {
        Button {
            if stage.fold.isActive && selected != g.id { selected = g.id } else { onPlay(g) }
        } label: {
            GameCard(game: g, artwork: store.artwork(for: g), highlighted: stage.fold.isActive && focus?.id == g.id)
                .frame(width: width)
        }
        .buttonStyle(CardPressStyle())
        .contextMenu {
            Button { onPlay(g) } label: { Label("Play", systemImage: "play.fill") }
            Button { newTitle = g.title; renaming = g } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { store.delete(g.id) } label: { Label("Remove", systemImage: "trash") }
        }
        .accessibilityHint(stage.fold.isActive ? "Selects the game; tap again to play" : "Plays the game")
    }

    // MARK: hero (Duo)

    @ViewBuilder private var hero: some View {
        if let g = focus {
            HStack(spacing: 18) {
                GameCard(game: g, artwork: store.artwork(for: g), highlighted: false)
                    .frame(maxWidth: 230)
                VStack(alignment: .leading, spacing: 10) {
                    Text(g.system.displayName.uppercased())
                        .font(.rounded(.caption, weight: .heavy))
                        .tracking(1.6)
                        .foregroundStyle(Theme.tint(g.system))
                    Text(g.title)
                        .font(.rounded(.title, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                    Text(lastPlayedText(g))
                        .font(.rounded(.subheadline))
                        .foregroundStyle(Theme.inkDim)
                    Button { onPlay(g) } label: { Label("Play", systemImage: "play.fill") }
                        .buttonStyle(EmberButtonStyle())
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
            )
        }
    }

    private func lastPlayedText(_ g: GameRecord) -> String {
        guard let d = g.lastPlayed else { return "Not played yet" }
        let f = RelativeDateTimeFormatter()
        let mins = Int(g.playSeconds / 60)
        return "Played \(f.localizedString(for: d, relativeTo: Date())) · \(mins) min in total"
    }
}

/// A generated "cartridge label": our own shape (a card with grip ridges), the system tint from the
/// app palette, and the latest screenshot once the game has been played.
struct GameCard: View {
    let game: GameRecord
    let artwork: UIImage?
    var highlighted: Bool

    var body: some View {
        let tint = Theme.tint(game.system)
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let artwork {
                    Image(uiImage: artwork)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LabelPattern(seed: game.id, tint: tint)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 13, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.35), lineWidth: 1))
            .padding([.horizontal, .top], 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.title)
                    .font(.rounded(.subheadline, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(game.isDemo ? "\(game.system.displayName) · Free demo" : game.system.displayName)
                    .font(.rounded(.caption2, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            // Grip ridges.
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { _ in
                    Capsule().fill(Color.black.opacity(0.14)).frame(height: 3)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.18), tint], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.ember, lineWidth: highlighted ? 2.5 : 0)
        )
        .accessibilityElement(children: .combine)
    }
}

/// A generated label for games not played yet: one of eight motifs, its own colours and
/// layout, all derived from the game's id, so every card on the shelf looks different.
struct LabelPattern: View {
    let seed: String
    let tint: Color

    private var hash: UInt64 {
        seed.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
    }

    var body: some View {
        let h = hash
        // Shift the system tint's hue a little per game, and pick a ground and an accent.
        let hueShift = Double((h >> 8) % 60) / 360 - 30.0 / 360
        let base = tint.rotatedHue(by: hueShift)
        let accent = Theme.sand.rotatedHue(by: Double((h >> 20) % 40) / 360 - 20.0 / 360)
        let ground = (h >> 30) % 3 == 0 ? Color(white: 0.92) : Color(white: 0.11)
        let motif = Int(h % 8)
        Canvas { ctx, size in
            let w = size.width, hh = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))
            var rng = SplitMix(seed: h)
            switch motif {
            case 0: // sun and stripes
                let n = 4 + Int(rng.next() % 4)
                let sh = hh / CGFloat(n * 2)
                for i in 0..<n {
                    let y = hh * 0.55 + CGFloat(i) * sh * 1.2
                    ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: sh * 0.6)), with: .color(base.opacity(0.9 - Double(i) * 0.15)))
                }
                let r = hh * 0.2, cx = w * (0.25 + rng.unit() * 0.5)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: hh * 0.45 - r * 1.6, width: r * 2, height: r * 2)), with: .color(accent))
            case 1: // mountains
                for layer in 0..<3 {
                    var p = Path()
                    let baseY = hh * (0.55 + CGFloat(layer) * 0.15)
                    p.move(to: CGPoint(x: 0, y: hh))
                    var x: CGFloat = 0
                    p.addLine(to: CGPoint(x: 0, y: baseY))
                    while x < w {
                        let peak = baseY - hh * (0.12 + rng.unit() * 0.25)
                        p.addLine(to: CGPoint(x: x + w * 0.12, y: peak))
                        x += w * 0.24
                        p.addLine(to: CGPoint(x: x, y: baseY))
                    }
                    p.addLine(to: CGPoint(x: w, y: hh))
                    ctx.fill(p, with: .color(base.opacity(0.45 + Double(layer) * 0.25)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.7, y: hh * 0.12, width: hh * 0.16, height: hh * 0.16)), with: .color(accent))
            case 2: // plaid
                let step = w / CGFloat(5 + rng.next() % 4)
                var x: CGFloat = 0
                while x < w { ctx.fill(Path(CGRect(x: x, y: 0, width: step * 0.35, height: hh)), with: .color(base.opacity(0.55))); x += step }
                var y: CGFloat = 0
                while y < hh { ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: step * 0.35)), with: .color(accent.opacity(0.45))); y += step }
            case 3: // waves
                for i in 0..<6 {
                    var p = Path()
                    let y0 = hh * (0.2 + CGFloat(i) * 0.14)
                    p.move(to: CGPoint(x: 0, y: y0))
                    var x: CGFloat = 0
                    while x <= w { p.addLine(to: CGPoint(x: x, y: y0 + sin(x / w * .pi * 4 + CGFloat(i)) * hh * 0.04)); x += 2 }
                    ctx.stroke(p, with: .color(i % 2 == 0 ? base : accent), lineWidth: hh * 0.045)
                }
            case 4: // concentric rings
                let c = CGPoint(x: w * (0.3 + rng.unit() * 0.4), y: hh * (0.3 + rng.unit() * 0.4))
                for i in (1...7).reversed() {
                    let r = CGFloat(i) * hh * 0.11
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .color(i % 2 == 0 ? base : (i == 1 ? accent : ground)))
                }
            case 5: // diagonal bands
                for i in -4..<10 {
                    var p = Path()
                    let x = CGFloat(i) * w * 0.16
                    p.move(to: CGPoint(x: x, y: hh)); p.addLine(to: CGPoint(x: x + w * 0.08, y: hh))
                    p.addLine(to: CGPoint(x: x + w * 0.08 + hh, y: 0)); p.addLine(to: CGPoint(x: x + hh, y: 0)); p.closeSubpath()
                    ctx.fill(p, with: .color((i % 3 == 0 ? accent : base).opacity(0.85)))
                }
            case 6: // starfield and planet
                for _ in 0..<40 {
                    let r = 0.6 + rng.unit() * 1.4
                    ctx.fill(Path(ellipseIn: CGRect(x: rng.unit() * w, y: rng.unit() * hh, width: r, height: r)), with: .color(accent))
                }
                let pr = hh * 0.28
                let pc = CGPoint(x: w * (0.3 + rng.unit() * 0.4), y: hh * 0.55)
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)), with: .color(base))
                ctx.stroke(Path(ellipseIn: CGRect(x: pc.x - pr * 1.6, y: pc.y - pr * 0.35, width: pr * 3.2, height: pr * 0.7)), with: .color(accent.opacity(0.8)), lineWidth: 2)
            default: // pixel blocks
                let cols = 8, rows = 6
                let cw = w / CGFloat(cols), ch = hh / CGFloat(rows)
                for r in 0..<rows { for c in 0..<cols where rng.next() % 3 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(c) * cw + 1, y: CGFloat(r) * ch + 1, width: cw - 2, height: ch - 2)),
                             with: .color((rng.next() % 2 == 0 ? base : accent).opacity(0.9)))
                } }
            }
        }
    }
}

/// Small deterministic generator for the label art.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> CGFloat { CGFloat(next() % 10_000) / 10_000 }
}

extension Color {
    /// The same colour with its hue turned by `amount` (0...1 = a full turn).
    func rotatedHue(by amount: Double) -> Color {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var nh = h + CGFloat(amount)
        nh -= floor(nh)
        return Color(hue: Double(nh), saturation: Double(s), brightness: Double(b), opacity: Double(a))
    }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct EmptyShelf: View {
    var onAdd: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                    .foregroundStyle(Theme.inkDim.opacity(0.5))
                    .frame(width: 120, height: 150)
                Image(systemName: "plus")
                    .font(.rounded(.largeTitle, weight: .bold))
                    .foregroundStyle(Theme.ember)
            }
            Text("Your shelf is empty")
                .font(.rounded(.title3, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Add game files you own from the Files app. Nothing is included or downloaded.")
                .font(.rounded(.subheadline))
                .foregroundStyle(Theme.inkDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button("Add games", action: onAdd)
                .buttonStyle(EmberButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
