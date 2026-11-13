import CoreKit
import CryptoKit
import Foundation
import Observation
import UIKit

/// A game on the shelf. Identified by the SHA-1 of its file, so re-importing is harmless.
struct GameRecord: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var system: SystemID
    var fileName: String
    var added: Date
    var lastPlayed: Date?
    var playSeconds: Double = 0
    /// DEBUG test carts live in the app bundle and are never copied into Documents.
    var isBundledTestCart = false
    /// A free homebrew demo seeded from the app bundle on first launch (optional, so older
    /// library files without the key still decode).
    var demo: Bool?

    var isDemo: Bool { demo == true }
}

extension SystemID {
    /// Systems this build lets you import and play. Nintendo 64 is Debug-only (`N64_ENABLED`)
    /// until it has a renderer for real games.
    var isAvailableInThisBuild: Bool {
        #if N64_ENABLED
        true
        #else
        self != .n64
        #endif
    }
}

enum ImportError: LocalizedError {
    case notAGame(String)
    case unreadable(String)
    case notInThisVersion(String, SystemID)
    case zip(String, String)

    var errorDescription: String? {
        switch self {
        case .notAGame(let name): "\(name) isn't a game file this app can play (NES, SNES, Game Boy, Game Boy Color, Game Boy Advance, Mega Drive or Nintendo DS)."
        case .unreadable(let name): "\(name) couldn't be read."
        case .notInThisVersion(let name, let system): "\(name) is a \(system.displayName) game. \(system.displayName) isn't available in this version yet."
        case .zip(let name, let reason): "\(name) \(reason)"
        }
    }
}

/// The library: files in Documents/Games/<system>/, an index in library.json, saves beside them.
///
/// Folder layout (all visible in the Files app):
///   Games/NES/…  Saves/<file>.sav  States/<game id>/slotN.state|png  Inbox/ (scanned at launch)
@MainActor
@Observable
final class GameStore {
    private(set) var games: [GameRecord] = []
    var lastImportMessage: String?

    let documents: URL
    var gamesDir: URL { documents.appendingPathComponent("Games", isDirectory: true) }
    var savesDir: URL { documents.appendingPathComponent("Saves", isDirectory: true) }
    var statesDir: URL { documents.appendingPathComponent("States", isDirectory: true) }
    private var indexURL: URL { documents.appendingPathComponent(".library.json") }

    init(documents: URL? = nil) {
        self.documents = documents ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for dir in [gamesDir, savesDir, statesDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        load()
        seedDemos()
        scanInbox()
        #if DEBUG
        addBundledTestCarts()
        #endif
    }

    var sortedGames: [GameRecord] {
        games.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var recentlyPlayed: [GameRecord] {
        games.filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
            .prefix(3).map { $0 }
    }

    func games(for system: SystemID) -> [GameRecord] {
        sortedGames.filter { $0.system == system }
    }

    var systemsPresent: [SystemID] {
        SystemID.allCases.filter { s in games.contains { $0.system == s } }
    }

    // MARK: persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([GameRecord].self, from: data) else { return }
        games = list.filter {
            $0.system.isAvailableInThisBuild
                && ($0.isBundledTestCart || FileManager.default.fileExists(atPath: romURL(for: $0).path))
        }
    }

    private func save() {
        let persistent = games.filter { !$0.isBundledTestCart } + games.filter(\.isBundledTestCart)
        if let data = try? JSONEncoder().encode(persistent) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    func romURL(for game: GameRecord) -> URL {
        if game.isBundledTestCart {
            return Bundle.main.bundleURL.appendingPathComponent("TestCarts").appendingPathComponent(game.fileName)
        }
        return gamesDir.appendingPathComponent(folderName(game.system)).appendingPathComponent(game.fileName)
    }

    private func folderName(_ system: SystemID) -> String {
        switch system {
        case .nes: "NES"
        case .gb: "Game Boy"
        case .gbc: "Game Boy Color"
        case .gba: "Game Boy Advance"
        case .snes: "SNES"
        case .md: "Mega Drive"
        case .ds: "Nintendo DS"
        case .n64: "Nintendo 64"
        }
    }

    func batteryURL(for game: GameRecord) -> URL {
        let base = (game.fileName as NSString).deletingPathExtension
        let prefix = game.isBundledTestCart ? "testcart-" : ""
        return savesDir.appendingPathComponent("\(prefix)\(base).sav")
    }

    func stateDir(for game: GameRecord) -> URL {
        let dir = statesDir.appendingPathComponent(game.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func stateURL(for game: GameRecord, slot: Int) -> URL {
        stateDir(for: game).appendingPathComponent(slot == 0 ? "auto.state" : "slot\(slot).state")
    }

    func thumbnailURL(for game: GameRecord, slot: Int) -> URL {
        stateDir(for: game).appendingPathComponent(slot == 0 ? "auto.png" : "slot\(slot).png")
    }

    /// The artwork on the card: the latest auto-save screenshot.
    func artwork(for game: GameRecord) -> UIImage? {
        UIImage(contentsOfFile: thumbnailURL(for: game, slot: 0).path)
    }

    // MARK: import

    /// Copies picked files into the library. Returns how many were added.
    @discardableResult
    func importFiles(_ urls: [URL]) -> Int {
        var added = 0
        var problems: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                if try importOne(url) { added += 1 }
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        save()
        if let first = problems.first {
            lastImportMessage = problems.count == 1 ? first : "\(first) (and \(problems.count - 1) more)"
        } else if added > 0 {
            lastImportMessage = added == 1 ? "Added 1 game." : "Added \(added) games."
        } else {
            lastImportMessage = "Those games are already on your shelf."
        }
        return added
    }

    private func importOne(_ url: URL) throws -> Bool {
        let name = url.lastPathComponent
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw ImportError.unreadable(name) }
        if url.pathExtension.lowercased() == "zip" || ZipArchive.isZip(data) { return try importZip(data, named: name) }
        // Largest real cartridges: 512 MB (DS), 64 MB (N64), 32 MB (GBA), 8 MB (SNES), a few MB for the rest.
        guard data.count >= 16, data.count <= 512 * 1024 * 1024,
              let system = CoreFactory.detect(rom: data, fileExtension: url.pathExtension),
              system == .ds || data.count <= (system == .n64 ? 64 : 32) * 1024 * 1024 else {
            throw ImportError.notAGame(name)
        }
        guard system.isAvailableInThisBuild else { throw ImportError.notInThisVersion(name, system) }
        let id = Self.gameID(data)
        if games.contains(where: { $0.id == id }) { return false }
        let fileName = try write(data, named: name, system: system)
        games.append(GameRecord(id: id, title: Self.title(fromFileName: name), system: system,
                                fileName: fileName, added: Date()))
        return true
    }

    /// A zip holding one game imports that game (Apple's Compression inflates it; nothing
    /// third-party). Extracted to a temporary folder, imported as if picked, then removed.
    private func importZip(_ data: Data, named name: String) throws -> Bool {
        do {
            let extensions = Set(SystemID.allCases.flatMap(\.fileExtensions))
            let entry = try ZipArchive.gameEntry(in: ZipArchive.entries(data), extensions: extensions)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent(entry.fileName)
            try ZipArchive.extract(entry, from: data, to: file)
            return try importOne(file)
        } catch let e as ZipArchive.ZipError {
            throw ImportError.zip(name, e.errorDescription ?? "couldn't be opened.")
        }
    }

    private static func gameID(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes the file into Games/<system>/ under a free name; returns the name used.
    private func write(_ data: Data, named name: String, system: SystemID) throws -> String {
        let folder = gamesDir.appendingPathComponent(folderName(system), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = (name as NSString).pathExtension
        var fileName = name
        var dest = folder.appendingPathComponent(fileName)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = (name as NSString).deletingPathExtension
            fileName = "\(base) (\(n)).\(ext)"
            dest = folder.appendingPathComponent(fileName)
            n += 1
        }
        try data.write(to: dest, options: .atomic)
        return fileName
    }

    // MARK: demos

    /// The free homebrew demos in the app bundle (App/Resources/Demos, credits in About).
    /// The Release ROM check in project.yml allows exactly these files.
    static let demoTitles: [String: String] = [
        "ucity.gbc": "µCity",
        "libbet.gb": "Libbet and the Magic Floor",
        "thwaite.nes": "Thwaite",
        "croom.nes": "Concentration Room",
        "alexvsbus-pre3.md": "Alex vs Bus: The Race",
    ]

    private var seededDemosURL: URL { documents.appendingPathComponent(".seeded-demos.json") }

    /// Copies each bundled demo onto the shelf once. A demo the player deletes is never seeded again
    /// (its id stays in .seeded-demos.json).
    private func seedDemos() {
        guard let dir = Bundle.main.url(forResource: "Demos", withExtension: nil) else { return }
        var seeded = Set((try? JSONDecoder().decode([String].self, from: Data(contentsOf: seededDemosURL))) ?? [])
        let before = seeded.count
        var added = false
        for (fileName, title) in Self.demoTitles.sorted(by: { $0.key < $1.key }) {
            let url = dir.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: url),
                  let system = CoreFactory.detect(rom: data, fileExtension: url.pathExtension),
                  system.isAvailableInThisBuild else { continue }
            let id = Self.gameID(data)
            guard !seeded.contains(id) else { continue }
            seeded.insert(id)
            if games.contains(where: { $0.id == id }) { continue }
            guard let stored = try? write(data, named: fileName, system: system) else { continue }
            games.append(GameRecord(id: id, title: title, system: system, fileName: stored, added: Date(), demo: true))
            added = true
        }
        if added { save() }
        if seeded.count != before, let out = try? JSONEncoder().encode(seeded.sorted()) {
            try? out.write(to: seededDemosURL, options: .atomic)
        }
    }

    /// "super_game_(v1.1).nes" → "Super Game"
    static func title(fromFileName name: String) -> String {
        var base = (name as NSString).deletingPathExtension
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let r = base.range(of: open), let e = base.range(of: close, range: r.upperBound..<base.endIndex) {
                base.removeSubrange(r.lowerBound..<e.upperBound)
            }
        }
        base = base.replacingOccurrences(of: "_", with: " ")
        let words = base.split(separator: " ").map { w -> String in
            let s = String(w)
            return s == s.lowercased() ? s.prefix(1).uppercased() + s.dropFirst() : s
        }
        let t = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? name : t
    }

    /// Files dropped into Documents/Inbox (AirDrop, "Open in", the Files app) are imported at launch.
    func scanInbox() {
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil),
              !files.isEmpty else { return }
        importFiles(files)
        for f in files { try? FileManager.default.removeItem(at: f) }
    }

    func openURL(_ url: URL) {
        importFiles([url])
        // "Open in" copies land in Documents/Inbox: don't import them again next launch.
        if url.path.contains("/Documents/Inbox/") { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: edits

    func markPlayed(_ id: String, seconds: Double) {
        guard let i = games.firstIndex(where: { $0.id == id }) else { return }
        games[i].lastPlayed = Date()
        games[i].playSeconds += seconds
        save()
    }

    func rename(_ id: String, to title: String) {
        guard let i = games.firstIndex(where: { $0.id == id }) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        games[i].title = t
        save()
    }

    /// Moves the file to Documents/Recently Deleted (kept until the user empties it in Files).
    func delete(_ id: String) {
        guard let i = games.firstIndex(where: { $0.id == id }) else { return }
        let game = games[i]
        if !game.isBundledTestCart {
            let trash = documents.appendingPathComponent("Recently Deleted", isDirectory: true)
            try? FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: romURL(for: game),
                                              to: trash.appendingPathComponent(game.fileName))
        }
        games.remove(at: i)
        save()
    }

    #if DEBUG
    /// Our own test ROMs (TestROMs/build), copied into Debug builds only.
    private func addBundledTestCarts() {
        let dir = Bundle.main.bundleURL.appendingPathComponent("TestCarts")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let names: [String: String] = [
            "demo.nes": "Test Cart: Hills", "cpu_selftest.nes": "Test Cart: CPU Check",
            "gb_demo.gbc": "Test Cart: Pocket Hills", "gb_demo_dmg.gb": "Test Cart: Pocket Hills (mono)",
            "gb_selftest.gb": "Test Cart: Pocket CPU Check", "gb_cgbtest.gbc": "Test Cart: Pocket Colour Check",
            "mmc1_probe.nes": "Test Cart: MMC1 Probe", "uxrom_probe.nes": "Test Cart: UxROM Probe",
            "cnrom_probe.nes": "Test Cart: CNROM Probe", "mmc3_probe.nes": "Test Cart: MMC3 Probe",
            "mmc2_probe.nes": "Test Cart: MMC2 Probe", "mmc4_probe.nes": "Test Cart: MMC4 Probe",
            "colordreams_probe.nes": "Test Cart: Color Dreams Probe", "gxrom_probe.nes": "Test Cart: GxROM Probe",
            "fme7_probe.nes": "Test Cart: FME-7 Probe",
            "gba_demo.gba": "Test Cart: Advance Square", "ares_snes_demo.sfc": "Test Cart: Sixteen Blue",
            "ares_md_demo.md": "Test Cart: Mega Tone", "ds_demo.nds": "Test Cart: Double Screen",
            "n64_demo.z64": "Test Cart: Sixty-Four Square",
        ]
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: url),
                  let system = CoreFactory.detect(rom: data, fileExtension: url.pathExtension) else { continue }
            let id = "testcart-" + url.lastPathComponent
            if games.contains(where: { $0.id == id }) { continue }
            games.append(GameRecord(id: id, title: names[url.lastPathComponent] ?? url.lastPathComponent,
                                    system: system, fileName: url.lastPathComponent, added: Date(),
                                    isBundledTestCart: true))
        }
    }
    #endif
}
