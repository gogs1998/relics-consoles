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
        let ids = ["com.iqlabs.duoemulator.nes", "com.iqlabs.duoemulator.gb", "com.iqlabs.duoemulator.gbc"]
        return ids.compactMap { UTType($0) } + [.data]
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
                Text(game.system.displayName)
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

/// A stand-in label for games not played yet: stripes and a sun, varied per game.
struct LabelPattern: View {
    let seed: String
    let tint: Color

    var body: some View {
        let h = seed.unicodeScalars.reduce(UInt32(2166136261)) { ($0 ^ $1.value) &* 16777619 }
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.12)))
            let stripes = 4 + Int(h % 4)
            let sh = size.height / CGFloat(stripes * 2)
            for i in 0..<stripes {
                let y = size.height * 0.55 + CGFloat(i) * sh * 1.2
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: sh * 0.6)),
                         with: .color(tint.opacity(0.85 - Double(i) * 0.15)))
            }
            let r = size.height * 0.22
            let cx = size.width * (0.25 + CGFloat((h >> 8) % 50) / 100)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: size.height * 0.48 - r * 1.6, width: r * 2, height: r * 2)),
                     with: .color(Theme.sand.opacity(0.9)))
        }
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
