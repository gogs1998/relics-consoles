import CoreKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The surfaces a layout can be made for. Book pose has two (one per page).
enum ControllerArea: String, Codable, CaseIterable, Identifiable {
    case table, portrait, bookLeft, bookRight, landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .table: "Duo table"
        case .portrait: "Portrait"
        case .bookLeft: "Duo book, left page"
        case .bookRight: "Duo book, right page"
        case .landscape: "Landscape"
        }
    }
}

/// A saved layout: controls in unit space for one system, one area, and optionally one game.
struct SavedLayout: Codable, Hashable {
    var version = 1
    var system: SystemID
    var area: ControllerArea
    var gameID: String?
    var preset: LayoutPreset
    /// Unit-space controls; empty means "the preset's defaults".
    var controls: [Control]
    var settings: ControlSettings

    /// Clamps everything a file could get wrong: unit frames inside the area with a sensible
    /// minimum size, finite opacity / haptics, and settings in range.
    var sanitised: SavedLayout {
        var l = self
        l.settings = settings.sanitised
        l.controls = controls.compactMap { c in
            var c = c
            let f = c.frame
            guard f.minX.isFinite, f.minY.isFinite, f.width.isFinite, f.height.isFinite else { return nil }
            let w = min(1, max(0.04, f.width)), h = min(1, max(0.03, f.height))
            c.frame = CGRect(x: min(max(0, f.minX), 1 - w), y: min(max(0, f.minY), 1 - h), width: w, height: h)
            c.opacity = c.opacity.isFinite ? min(1, max(0.15, c.opacity)) : 1
            c.haptic = c.haptic.isFinite ? min(1, max(0, c.haptic)) : 0.6
            return c
        }
        return l
    }
}

/// A shareable file: every saved layout for one system.
struct LayoutBundle: Codable {
    var format = "foldback-layout"
    var version = 1
    var system: SystemID
    var layouts: [SavedLayout]
}

extension UTType {
    static let foldbackLayout = UTType(exportedAs: "com.iqlabs.duoemulator.layout", conformingTo: .json)
}

struct LayoutDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.foldbackLayout, .json] }
    var bundle: LayoutBundle

    init(bundle: LayoutBundle) { self.bundle = bundle }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        bundle = try LayoutDocument.decode(data)
    }

    static func decode(_ data: Data) throws -> LayoutBundle {
        let b = try JSONDecoder().decode(LayoutBundle.self, from: data)
        guard b.format == "foldback-layout", b.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return b
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try enc.encode(bundle))
    }
}

/// Layouts on disk: Application Support/Layouts/<system>-<area>[-<game>].json.
/// Lookup order: this game's layout, then this system's, then the preset defaults.
@MainActor
@Observable
final class LayoutStore {
    static let shared = LayoutStore()
    /// Bumped on every save so views re-resolve.
    private(set) var revision = 0
    @ObservationIgnored private var cache: [String: SavedLayout?] = [:]
    @ObservationIgnored private let dir: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Layouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func key(_ system: SystemID, _ area: ControllerArea, _ game: String?) -> String {
        let safeGame = game.map { "-" + $0.filter { $0.isLetter || $0.isNumber || $0 == "-" } } ?? ""
        return "\(system.rawValue)-\(area.rawValue)\(safeGame)"
    }

    private func url(_ key: String) -> URL { dir.appendingPathComponent(key + ".json") }

    func saved(_ system: SystemID, _ area: ControllerArea, game: String?) -> SavedLayout? {
        let k = key(system, area, game)
        if let hit = cache[k] { return hit }
        let value = (try? Data(contentsOf: url(k))).flatMap { try? JSONDecoder().decode(SavedLayout.self, from: $0) }?.sanitised
        cache[k] = value
        return value
    }

    /// The layout to use: game-specific, else system-wide, else nil (defaults).
    func resolve(_ system: SystemID, _ area: ControllerArea, game: String?) -> SavedLayout? {
        _ = revision
        if let game, let g = saved(system, area, game: game) { return g }
        return saved(system, area, game: nil)
    }

    func hasGameLayout(_ system: SystemID, game: String) -> Bool {
        ControllerArea.allCases.contains { saved(system, $0, game: game) != nil }
    }

    func save(_ layout: SavedLayout) {
        let k = key(layout.system, layout.area, layout.gameID)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let data = try? enc.encode(layout) { try? data.write(to: url(k), options: .atomic) }
        cache[k] = layout
        revision += 1
    }

    func remove(_ system: SystemID, _ area: ControllerArea, game: String?) {
        let k = key(system, area, game)
        try? FileManager.default.removeItem(at: url(k))
        cache[k] = .some(nil)
        revision += 1
    }

    func bundle(for system: SystemID, game: String?) -> LayoutBundle {
        LayoutBundle(system: system, layouts: ControllerArea.allCases.compactMap { resolve(system, $0, game: game) })
    }

    /// Imports a shared file. Layouts for another system are refused; per-game ids are kept only
    /// when `game` is given (they're applied to that game instead).
    @discardableResult
    func importBundle(_ b: LayoutBundle, game: String?) -> Int {
        var n = 0
        for var l in b.layouts where l.system == b.system {
            l.gameID = game
            save(l.sanitised)
            n += 1
        }
        return n
    }

    /// Resolves controls in points for an area of `size`, falling back to `defaults`.
    func controls(_ system: SystemID, _ area: ControllerArea, game: String?, size: CGSize,
                  defaults: (LayoutPreset) -> [Control]) -> (controls: [Control], settings: ControlSettings, preset: LayoutPreset) {
        guard let s = resolve(system, area, game: game) else { return (defaults(.standard), ControlSettings(), .standard) }
        if s.controls.isEmpty { return (defaults(s.preset), s.settings, s.preset) }
        return (s.controls.map { $0.fromUnit(size) }, s.settings, s.preset)
    }
}
