import CoreKit
import DuoKit
import SwiftUI

@main
struct DuoEmulatorApp: App {
    @State private var store = GameStore()

    init() {
        #if DEBUG
        // -duoAspect NO: draw like an ordinary iPhone (no 1.42 letterbox) for "plain phone" checks.
        // -resetLayouts YES: start from the built-in controller layouts (UI tests).
        if UserDefaults.standard.bool(forKey: "resetLayouts") {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Layouts")
            try? FileManager.default.removeItem(at: dir)
        }
        if UserDefaults.standard.object(forKey: "duoAspect") != nil, !UserDefaults.standard.bool(forKey: "duoAspect") {
            MainActor.assumeIsolated { FoldSimulator.shared.constrainToDuoAspect = false }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .preferredColorScheme(.dark)
                .onOpenURL { url in store.openURL(url) }
        }
    }
}

/// Shelf or player, inside the Duo stage.
struct RootView: View {
    let store: GameStore
    @State private var player: PlayerModel?
    @State private var openError: String?

    var body: some View {
        DuoStageReader { stage in
            ZStack {
                if let player {
                    PlayerView(model: player, stage: stage) { quit() }
                        .transition(.opacity)
                } else {
                    LibraryView(store: store, stage: stage) { play($0) }
                        .transition(.opacity)
                }
            }
        }
        .background(BodySurface())
        .alert("Couldn't open the game", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openError ?? "")
        }
        .task { debugAutoplay() }
    }

    private func play(_ game: GameRecord) {
        do {
            let model = try PlayerModel(game: game, store: store)
            withAnimation(.easeInOut(duration: 0.25)) { player = model }
            model.start(resume: !Self.debugFlag("freshStart"))
        } catch {
            openError = (error as? LocalizedError)?.errorDescription ?? "The file couldn't be read."
        }
    }

    private func quit() {
        player?.stop()
        withAnimation(.easeInOut(duration: 0.25)) { player = nil }
    }

    private static func debugFlag(_ name: String) -> Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: name)
        #else
        return false
        #endif
    }

    /// DEBUG launch arguments for screenshots:
    ///   -autoplay demo.nes      open a bundled test cart (by file name) straight into the player
    ///   -holdInput right,a      hold buttons (as if on a keyboard) from launch
    ///   -holdStylus 128,96      hold the stylus on the DS touch screen at that pixel from launch
    ///   -openMenu YES           open the pause menu after 2 s
    ///   -freshStart YES         ignore the auto-save
    ///   -editControls YES       open the touch-layout editor after 2 s
    private func debugAutoplay() {
        #if DEBUG
        let d = UserDefaults.standard
        guard let name = d.string(forKey: "autoplay"),
              let game = store.games.first(where: { $0.fileName == name || $0.title == name }) else { return }
        play(game)
        if let hold = d.string(forKey: "holdInput"), let player {
            let map: [String: InputState] = ["up": .up, "down": .down, "left": .left, "right": .right,
                                             "a": .a, "b": .b, "x": .x, "y": .y, "l": .l, "r": .r,
                                             "start": .start, "select": .select]
            let bits = hold.split(separator: ",").compactMap { map[String($0)] }.reduce(InputState()) { $0.union($1) }
            player.session.input.keyboard.store(bits.rawValue, ordering: .relaxed)
        }
        if let stylus = d.string(forKey: "holdStylus"), let player {
            let xy = stylus.split(separator: ",").compactMap { Int($0) }
            if xy.count == 2 {
                player.session.input.stylus.store(InputLatch.stylus(x: xy[0], y: xy[1]), ordering: .relaxed)
            }
        }
        if d.bool(forKey: "editControls") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                player?.beginEditingControls()
            }
        }
        if d.bool(forKey: "openMenu") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                player?.menuOpen = true
            }
        }
        #endif
    }
}
