import Compression
@testable import CoreKit
import Foundation
import Testing

/// Zip import: archives built here by hand (stored and deflated with Apple's Compression).
@Suite struct ZipTests {
    struct Item { var name: String; var data: Data; var deflate: Bool }

    static func deflate(_ d: Data) -> Data {
        let cap = d.count + 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer { dst.deallocate() }
        let n = d.withUnsafeBytes { raw in
            compression_encode_buffer(dst, cap, raw.bindMemory(to: UInt8.self).baseAddress!, d.count, nil, COMPRESSION_ZLIB)
        }
        return Data(bytes: dst, count: n)
    }

    static func zip(_ items: [Item]) -> Data {
        var out = Data(), dir = Data()
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16 & 0xFFFF) }
        for it in items {
            let body = it.deflate ? deflate(it.data) : it.data
            let crc = Int(CRC32.checksum(it.data))
            let name = Array(it.name.utf8)
            let offset = out.count
            let common = le16(20) + le16(0) + le16(it.deflate ? 8 : 0) + le16(0) + le16(0)
                + le32(crc) + le32(body.count) + le32(it.data.count) + le16(name.count) + le16(0)
            out.append(contentsOf: le32(0x0403_4B50) + common + name)
            out.append(body)
            dir.append(contentsOf: le32(0x0201_4B50) + le16(20) + common + le16(0) + le16(0) + le16(0) + le32(0)
                       + le32(offset) + name)
        }
        let dirOffset = out.count
        out.append(dir)
        out.append(contentsOf: le32(0x0605_4B50) + le16(0) + le16(0) + le16(items.count) + le16(items.count)
                   + le32(dir.count) + le32(dirOffset) + le16(0))
        return out
    }

    func tempURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    let exts: Set<String> = ["nes", "gb", "nds"]

    @Test func extractsTheOneGameDeflatedAndStored() throws {
        let rom = try testROM("demo.nes")
        for deflate in [true, false] {
            let z = Self.zip([Item(name: "__MACOSX/._demo.nes", data: Data([1, 2, 3]), deflate: false),
                              Item(name: "readme.txt", data: Data("hello".utf8), deflate: true),
                              Item(name: "Games/demo.nes", data: rom, deflate: deflate)])
            #expect(ZipArchive.isZip(z))
            let e = try ZipArchive.gameEntry(in: ZipArchive.entries(z), extensions: exts)
            #expect(e.fileName == "demo.nes")
            let url = tempURL()
            defer { try? FileManager.default.removeItem(at: url) }
            try ZipArchive.extract(e, from: z, to: url)
            #expect(try Data(contentsOf: url) == rom)
        }
    }

    @Test func bigEntryStreams() throws {
        // 3 MB of patterned data: several inflate output chunks.
        let big = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31 ^ ($0 >> 9)) })
        let z = Self.zip([Item(name: "big.nds", data: big, deflate: true)])
        let e = try ZipArchive.gameEntry(in: ZipArchive.entries(z), extensions: exts)
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try ZipArchive.extract(e, from: z, to: url)
        #expect(try Data(contentsOf: url) == big)
    }

    @Test func refusesNoneSeveralAndDamaged() throws {
        let z0 = Self.zip([Item(name: "notes.txt", data: Data("x".utf8), deflate: false)])
        #expect(throws: ZipArchive.ZipError.noGame) { try ZipArchive.gameEntry(in: ZipArchive.entries(z0), extensions: exts) }
        let z2 = Self.zip([Item(name: "a.nes", data: Data([1]), deflate: false), Item(name: "b.gb", data: Data([2]), deflate: false)])
        #expect(throws: ZipArchive.ZipError.severalGames(["a.nes", "b.gb"])) {
            try ZipArchive.gameEntry(in: ZipArchive.entries(z2), extensions: exts)
        }
        // A flipped byte in the payload fails the CRC and leaves no file behind.
        var bad = Self.zip([Item(name: "x.nes", data: Data(repeating: 7, count: 100), deflate: false)])
        bad[40] ^= 0xFF
        let e = try ZipArchive.entries(bad)[0]
        let url = tempURL()
        #expect(throws: ZipArchive.ZipError.self) { try ZipArchive.extract(e, from: bad, to: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(throws: ZipArchive.ZipError.notAZip) { try ZipArchive.entries(Data("hello world, not a zip".utf8)) }
    }
}
