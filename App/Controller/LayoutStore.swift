import CoreKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The surfaces a layout can be made for. Book pose has two (one per page).
enum ControllerArea: String, Codable, CaseIterable, Identifiable {
    case table, portrait, bookLeft, bookRight, landscape
    /// DS in Duo table pose: the touch screen sits in the middle of the bottom half, so its
    /// controls live in three areas around it (they can never be dragged over the screen).
    case dsTableLeft, dsTableRight, dsTableBelow

    /// Areas that share one layout's settings with a main area (the editor reads the main one's).
    var isSecondary: Bool { self == .bookLeft || self == .dsTableLeft || self == .dsTableBelow }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .table: "Duo table"
        case .portrait: "Portrait"
        case .bookLeft: "Duo book, left page"
        case .bookRight: "Duo book, right page"
        case .landscape: "Landscape"
        case .dsTableLeft: "Duo table, left of the touch screen"
        case .dsTableRight: "Duo table, right of the touch screen"
        case .dsTableBelow: "Duo table, below the touch screen"
        }
    }
}

/// The poses a player can be in, each with its own layout (one or more areas).
enum LayoutPose: String, CaseIterable, Identifiable {
    case table, book, portrait, landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .table: "Duo table"
        case .book: "Duo book"
        case .portrait: "Portrait"
        case .landscape: "Landscape"
        }
    }

    var symbol: String {
        switch self {
        case .table: "laptopcomputer"
        case .book: "book"
        case .portrait: "iphone"
        case .landscape: "iphone.landscape"
        }
    }

    func areas(_ system: SystemID) -> [ControllerArea] {
        switch self {
        case .table: system == .ds ? [.dsTableLeft, .dsTableRight, .dsTableBelow] : [.table]
        case .book: [.bookLeft, .bookRight]
        case .portrait: [.portrait]
        case .landscape: [.landscape]
        }
    }

    init(area: ControllerArea) {
        switch area {
        case .table, .dsTableLeft, .dsTableRight, .dsTableBelow: self = .table
        case .bookLeft, .bookRight: self = .book
        case .portrait: self = .portrait
        case .landscape: self = .landscape
        }
    }

    /// Where an area sits inside its pose, in a unit square: the common ground "copy from another
    /// pose" maps through (book pages side by side; the DS table areas around the touch screen).
    static func region(_ area: ControllerArea) -> CGRect {
        switch area {
        case .table, .portrait, .landscape: CGRect(x: 0, y: 0, width: 1, height: 1)
        case .bookLeft: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .bookRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .dsTableLeft: CGRect(x: 0, y: 0, width: 0.25, height: 1)
        case .dsTableRight: CGRect(x: 0.75, y: 0, width: 0.25, height: 1)
        case .dsTableBelow: CGRect(x: 0.25, y: 0.75, width: 0.5, height: 0.25)
        }
    }
}

/// "Copy from another pose": the source pose's arrangement, mapped onto this pose's areas.
enum LayoutCopier {
    struct Source {
        var area: ControllerArea
        /// Unit-space controls, as saved.
        var controls: [Control]
        /// The area's size in points when it was saved (older files don't have it).
        var areaSize: CGSize?
    }

    /// Each control the source has moves to the same relative place in this pose (into whichever
    /// area holds that place) and takes the source's look (opacity, haptics, auto-fire, hidden).
    /// Its size comes from the source when the source's size in points is known, else it keeps
    /// its current size. Controls the source lacks stay where they are.
    static func copy(from sources: [Source], into target: [ControllerArea: [Control]],
                     sizes: [ControllerArea: CGSize]) -> [ControllerArea: [Control]] {
        var placed: [String: (centre: CGPoint, size: CGSize?, control: Control)] = [:]
        for s in sources {
            let r = LayoutPose.region(s.area)
            for c in s.controls {
                let centre = CGPoint(x: r.minX + c.frame.midX * r.width, y: r.minY + c.frame.midY * r.height)
                let size = s.areaSize.map { CGSize(width: c.frame.width * $0.width, height: c.frame.height * $0.height) }
                placed[c.id] = (centre, size, c)
            }
        }
        let areas = target.keys.filter { sizes[$0] != nil }.sorted { $0.rawValue < $1.rawValue }
        var out: [ControllerArea: [Control]] = [:]
        for a in areas { out[a] = [] }
        for a in areas {
            for var c in target[a] ?? [] {
                guard let p = placed[c.id] else { out[a, default: []].append(c); continue }
                // The area whose region holds the centre, else the nearest one.
                let dest = areas.first { LayoutPose.region($0).contains(p.centre) } ?? areas.min { lhs, rhs in
                    distance(p.centre, LayoutPose.region(lhs)) < distance(p.centre, LayoutPose.region(rhs))
                } ?? a
                guard let size = sizes[dest] else { out[a, default: []].append(c); continue }
                let r = LayoutPose.region(dest)
                let local = CGPoint(x: (p.centre.x - r.minX) / r.width * size.width,
                                    y: (p.centre.y - r.minY) / r.height * size.height)
                var s = p.size ?? c.frame.size
                s.width = min(s.width, size.width)
                s.height = min(s.height, size.height)
                var f = CGRect(x: local.x - s.width / 2, y: local.y - s.height / 2, width: s.width, height: s.height)
                f.origin.x = min(max(0, f.minX), size.width - f.width)
                f.origin.y = min(max(0, f.minY), size.height - f.height)
                c.frame = f
                c.opacity = p.control.opacity
                c.haptic = p.control.haptic
                c.autoFire = p.control.autoFire
                c.hidden = p.control.hidden
                out[dest, default: []].append(c)
            }
        }
        return out
    }

    private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
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
    /// The area's size in points when saved, so another pose can copy real control sizes.
    var areaSize: CGSize?

    /// Clamps everything a file could get wrong: unit frames inside the area with a sensible
    /// minimum size, finite opacity / haptics, and settings in range.
    var sanitised: SavedLayout {
        var l = self
        l.settings = settings.sanitised
        if let a = areaSize, !(a.width.isFinite && a.height.isFinite && a.width > 0 && a.height > 0
                                && a.width < 5000 && a.height < 5000) {
            l.areaSize = nil
        }
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
