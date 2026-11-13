import CoreKit
@testable import DuoEmulator
import Foundation
import Testing

/// Zip import through the real GameStore (stored entries built here; inflate is covered by CoreKit).
@MainActor
@Suite struct ZipImportTests {
    static func storedZip(_ files: [(String, Data)]) -> Data {
        var out = Data(), dir = Data()
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16 & 0xFFFF) }
        for (name, data) in files {
            let n = Array(name.utf8), offset = out.count
            let common = le16(20) + le16(0) + le16(0) + le16(0) + le16(0)
                + le32(Int(CRC32.checksum(data))) + le32(data.count) + le32(data.count) + le16(n.count) + le16(0)
            out.append(contentsOf: le32(0x0403_4B50) + common + n)
            out.append(data)
            dir.append(contentsOf: le32(0x0201_4B50) + le16(20) + common + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + n)
        }
        let at = out.count
        out.append(dir)
        out.append(contentsOf: le32(0x0605_4B50) + le16(0) + le16(0) + le16(files.count) + le16(files.count)
                   + le32(dir.count) + le32(at) + le16(0))
        return out
    }

    @Test func zipWithOneGameImportsIt() throws {
        let docs = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: docs) }
        let store = GameStore(documents: docs)
        let rom = try Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("TestCarts/cpu_selftest.nes"))
        var patched = rom
        patched[patched.count - 1] ^= 0x5A    // a different id from the bundled test cart
        let zipURL = docs.appendingPathComponent("My Game (v1).zip")
        try Self.storedZip([("__MACOSX/._x.nes", Data([0])), ("My Game.nes", patched)]).write(to: zipURL)
        let before = store.games.count
        #expect(store.importFiles([zipURL]) == 1)
        #expect(store.games.count == before + 1)
        let added = try #require(store.games.first { $0.fileName == "My Game.nes" })
        #expect(added.system == .nes)
        #expect(try Data(contentsOf: store.romURL(for: added)) == patched)

        let two = docs.appendingPathComponent("two.zip")
        try Self.storedZip([("a.nes", rom), ("b.nes", rom)]).write(to: two)
        #expect(store.importFiles([two]) == 0)
        #expect(store.lastImportMessage?.contains("contains 2 games") == true)
    }
}
