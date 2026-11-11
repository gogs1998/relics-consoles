import CoreKit
@testable import DuoEmulator
import Foundation
import Testing

/// Layout model, store and touch geometry (app-hosted, runs in the simulator).
@MainActor
@Suite struct LayoutTests {
    private func tempStore() -> LayoutStore {
        LayoutStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test func unitRoundTrip() {
        let c = Control(kind: .face(.a, "A", .ember), frame: CGRect(x: 40, y: 20, width: 60, height: 60))
        let size = CGSize(width: 400, height: 260)
        #expect(c.toUnit(size).fromUnit(size).frame == c.frame)
    }

    @Test func codableKeepsEverything() throws {
        var c = Control(kind: .combo([.a, .b], "AB"), frame: CGRect(x: 0.1, y: 0.2, width: 0.05, height: 0.05))
        c.opacity = 0.4; c.haptic = 0.2; c.autoFire = true
        let back = try JSONDecoder().decode(Control.self, from: JSONEncoder().encode(c))
        #expect(back == c)
    }

    @Test func storeResolvesGameThenSystemThenDefaults() {
        let store = tempStore()
        let size = CGSize(width: 400, height: 260)
        let defaults: (LayoutPreset) -> [Control] = { ControllerLayout.deck(size, system: .nes, preset: $0) }
        #expect(store.controls(.nes, .table, game: "g1", size: size, defaults: defaults).controls == defaults(.standard))
        var moved = defaults(.standard)
        moved[0].frame.origin.x += 16
        store.save(SavedLayout(system: .nes, area: .table, gameID: nil, preset: .standard,
                               controls: moved.map { $0.toUnit(size) }, settings: ControlSettings()))
        let sys = store.controls(.nes, .table, game: "g1", size: size, defaults: defaults).controls
        #expect(abs(sys[0].frame.minX - moved[0].frame.minX) < 0.001)
        var game = moved
        game[0].frame.origin.x += 16
        store.save(SavedLayout(system: .nes, area: .table, gameID: "g1", preset: .standard,
                               controls: game.map { $0.toUnit(size) }, settings: ControlSettings(diagonalDegrees: 0)))
        let g = store.controls(.nes, .table, game: "g1", size: size, defaults: defaults)
        #expect(abs(g.controls[0].frame.minX - game[0].frame.minX) < 0.001)
        #expect(g.settings.diagonalDegrees == 0)
        store.remove(.nes, .table, game: "g1")
        #expect(abs(store.controls(.nes, .table, game: "g1", size: size, defaults: defaults).controls[0].frame.minX - moved[0].frame.minX) < 0.001)
    }

    @Test func exportImportBundle() throws {
        let a = tempStore(), b = tempStore()
        let size = CGSize(width: 400, height: 260)
        let list = ControllerLayout.deck(size, system: .snes, preset: .arcade)
        a.save(SavedLayout(system: .snes, area: .table, gameID: nil, preset: .arcade, controls: list.map { $0.toUnit(size) },
                           settings: ControlSettings(autoFireHz: 15)))
        let data = try JSONEncoder().encode(a.bundle(for: .snes, game: nil))
        let bundle = try LayoutDocument.decode(data)
        #expect(b.importBundle(bundle, game: nil) == 1)
        #expect(b.resolve(.snes, .table, game: nil)?.preset == .arcade)
        #expect(b.resolve(.snes, .table, game: nil)?.settings.autoFireHz == 15)
    }

    @Test func arcadePresetIsTwoRowsOfThree() {
        let size = CGSize(width: 402, height: 265)
        let snes = ControllerLayout.deck(size, system: .snes, preset: .arcade)
        let faces = snes.compactMap { c -> String? in if case .face(_, let l, _) = c.kind { l } else { nil } }
        #expect(Set(faces) == ["Y", "X", "L", "B", "A", "R"])
        #expect(!snes.contains { if case .shoulder = $0.kind { true } else { false } })   // L/R are on the panel
        let md = ControllerLayout.deck(size, system: .md, preset: .arcade)
        let mdFaces = md.compactMap { c -> String? in if case .face(_, let l, _) = c.kind { l } else { nil } }
        #expect(Set(mdFaces) == ["X", "Y", "Z", "A", "B", "C"])
        let combos = md.filter { if case .combo = $0.kind { true } else { false } }
        #expect(combos.count == 2)
        // Everything stays inside the controller area, so nothing can cover the game in table pose.
        for c in snes + md { #expect(CGRect(origin: .zero, size: size).insetBy(dx: -1, dy: -1).contains(c.frame)) }
    }

    @Test func dpadDiagonals() {
        let f = CGRect(x: 0, y: 0, width: 100, height: 100)
        let diag = CGPoint(x: 50 + 30, y: 50 - 30)            // exactly up-right
        #expect(TouchSurface.SurfaceView.dpad(diag, in: f, diagonal: 36).0 == [.up, .right])
        #expect(TouchSurface.SurfaceView.dpad(diag, in: f, diagonal: 0).0.rawValue.nonzeroBitCount == 1)
        let nearRight = CGPoint(x: 50 + 40, y: 50 - 12)        // ~17 degrees above right
        #expect(TouchSurface.SurfaceView.dpad(nearRight, in: f, diagonal: 24).0 == [.right])
        #expect(TouchSurface.SurfaceView.dpad(nearRight, in: f, diagonal: 90).0 == [.up, .right])
        #expect(TouchSurface.SurfaceView.dpad(CGPoint(x: 52, y: 51), in: f).0.isEmpty)   // dead zone
    }

    @Test func comboAndMinimumHitArea() {
        let pill = Control(kind: .pill(.start, "START"), frame: CGRect(x: 0, y: 0, width: 30, height: 10))
        #expect(pill.hitFrame.width >= 44 && pill.hitFrame.height >= 44)
        let b = Control(kind: .face(.b, "B", .sand), frame: CGRect(x: 0, y: 40, width: 60, height: 60))
        let a = Control(kind: .face(.a, "A", .ember), frame: CGRect(x: 80, y: 0, width: 60, height: 60))
        let ab = ControllerLayout.comboAB(between: b, and: a)
        #expect(ab.buttons == [.a, .b])
        #expect(ab.hitFrame == ab.frame)
    }
}
