import Compression
import Foundation

/// Just enough of the zip format to take one game out of an archive: the central directory,
/// stored and deflated entries, CRC-checked. Inflate is Apple's Compression framework
/// (`COMPRESSION_ZLIB` is raw DEFLATE); no third-party code. Zip64, encryption and other
/// methods are refused with a message.
public enum ZipArchive {
    public struct Entry: Sendable, Equatable {
        public var name: String
        public var method: UInt16
        public var flags: UInt16
        public var crc32: UInt32
        public var compressedSize: Int
        public var uncompressedSize: Int
        public var localHeaderOffset: Int

        public var isDirectory: Bool { name.hasSuffix("/") }
        public var fileName: String { (name as NSString).lastPathComponent }
        /// macOS resource forks, hidden files and folders.
        public var isJunk: Bool {
            isDirectory || name.hasPrefix("__MACOSX/") || name.contains("/__MACOSX/") || fileName.hasPrefix(".")
        }
    }

    public enum ZipError: LocalizedError, Equatable {
        case notAZip
        case damaged(String)
        case unsupported(String)
        case noGame
        case severalGames([String])

        public var errorDescription: String? {
            switch self {
            case .notAZip: "isn't a zip archive."
            case .damaged(let why): "is damaged (\(why))."
            case .unsupported(let what): "uses \(what), which this app can't open. Unzip it in the Files app first."
            case .noGame: "doesn't contain a game file."
            case .severalGames(let names): "contains \(names.count) games. Unzip it in the Files app and add them one by one."
            }
        }
    }

    public static func isZip(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4).elementsEqual([0x50, 0x4B, 0x03, 0x04])
    }

    /// Reads the central directory.
    public static func entries(_ data: Data) throws -> [Entry] {
        let b = data
        let n = b.count
        func u16(_ i: Int) -> Int { Int(b[b.startIndex + i]) | Int(b[b.startIndex + i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        guard isZip(b), n >= 22 else { throw ZipError.notAZip }
        // The end-of-central-directory record is in the last 22 + 65,535 bytes.
        var eocd = -1
        var i = n - 22
        let floor = max(0, n - 22 - 0xFFFF)
        while i >= floor {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.damaged("no directory") }
        let count = u16(eocd + 10)
        let dirSize = u32(eocd + 12)
        let dirOffset = u32(eocd + 16)
        if count == 0xFFFF || dirOffset == 0xFFFF_FFFF || dirSize == 0xFFFF_FFFF { throw ZipError.unsupported("Zip64") }
        guard dirOffset + dirSize <= eocd else { throw ZipError.damaged("directory out of range") }
        var out: [Entry] = []
        var p = dirOffset
        for _ in 0..<count {
            guard p + 46 <= eocd, u32(p) == 0x0201_4B50 else { throw ZipError.damaged("bad directory entry") }
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
            guard p + 46 + nameLen <= eocd else { throw ZipError.damaged("bad name") }
            let nameBytes = b[(b.startIndex + p + 46)..<(b.startIndex + p + 46 + nameLen)]
            let name = String(decoding: nameBytes, as: UTF8.self)
            let e = Entry(name: name, method: UInt16(u16(p + 10)), flags: UInt16(u16(p + 8)),
                          crc32: UInt32(u32(p + 16)), compressedSize: u32(p + 20), uncompressedSize: u32(p + 24),
                          localHeaderOffset: u32(p + 42))
            if e.compressedSize == 0xFFFF_FFFF || e.uncompressedSize == 0xFFFF_FFFF || e.localHeaderOffset == 0xFFFF_FFFF {
                throw ZipError.unsupported("Zip64")
            }
            out.append(e)
            p += 46 + nameLen + extraLen + commentLen
        }
        return out
    }

    /// The one game in the archive (by file extension), ignoring folders and macOS clutter.
    public static func gameEntry(in entries: [Entry], extensions: Set<String>) throws -> Entry {
        let games = entries.filter { !$0.isJunk && extensions.contains(($0.fileName as NSString).pathExtension.lowercased()) }
        if games.count == 1 { return games[0] }
        if games.isEmpty { throw ZipError.noGame }
        throw ZipError.severalGames(games.map(\.fileName))
    }

    /// Extracts an entry to `url`, streaming (a DS game can be hundreds of MB). Checks the size
    /// and CRC; on any failure the partial file is removed.
    public static func extract(_ e: Entry, from data: Data, to url: URL, maxSize: Int = 512 * 1024 * 1024) throws {
        guard e.flags & 1 == 0 else { throw ZipError.unsupported("encryption") }
        guard e.method == 0 || e.method == 8 else { throw ZipError.unsupported("compression method \(e.method)") }
        guard e.uncompressedSize <= maxSize else { throw ZipError.unsupported("a file larger than 512 MB") }
        let b = data
        func u16(_ i: Int) -> Int { Int(b[b.startIndex + i]) | Int(b[b.startIndex + i + 1]) << 8 }
        let h = e.localHeaderOffset
        guard h + 30 <= b.count, u16(h) | u16(h + 2) << 16 == 0x0403_4B50 else { throw ZipError.damaged("bad entry header") }
        let start = h + 30 + u16(h + 26) + u16(h + 28)
        guard start + e.compressedSize <= b.count else { throw ZipError.damaged("entry runs past the end") }

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let out = try FileHandle(forWritingTo: url)
        var ok = false
        defer {
            try? out.close()
            if !ok { try? FileManager.default.removeItem(at: url) }
        }
        var crc = CRC32.Running()
        var written = 0
        let source = b[(b.startIndex + start)..<(b.startIndex + start + e.compressedSize)]   // no copy
        func emit(_ chunk: UnsafeBufferPointer<UInt8>) throws {
            written += chunk.count
            guard written <= e.uncompressedSize else { throw ZipError.damaged("more data than it says") }
            crc.update(chunk)
            try out.write(contentsOf: Data(buffer: chunk))
        }
        if e.method == 0 {
            guard e.compressedSize == e.uncompressedSize else { throw ZipError.damaged("stored size mismatch") }
            try source.withUnsafeBytes { raw in
                let all = raw.bindMemory(to: UInt8.self)
                var off = 0
                while off < all.count {
                    let len = min(1 << 20, all.count - off)
                    try emit(UnsafeBufferPointer(rebasing: all[off..<(off + len)]))
                    off += len
                }
            }
        } else {
            try inflate(source, emit: emit)
        }
        guard written == e.uncompressedSize else { throw ZipError.damaged("size mismatch") }
        guard crc.value == e.crc32 else { throw ZipError.damaged("checksum mismatch") }
        ok = true
    }

    private static func inflate(_ src: Data, emit: (UnsafeBufferPointer<UInt8>) throws -> Void) throws {
        let dstSize = 1 << 18
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstSize)
        defer { dst.deallocate() }
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        guard compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw ZipError.damaged("inflate failed to start")
        }
        defer { compression_stream_destroy(streamPtr) }
        try src.withUnsafeBytes { raw in
            let input = raw.bindMemory(to: UInt8.self)
            streamPtr.pointee.src_ptr = input.baseAddress ?? UnsafePointer(dst)
            streamPtr.pointee.src_size = input.count
            while true {
                streamPtr.pointee.dst_ptr = dst
                streamPtr.pointee.dst_size = dstSize
                let status = compression_stream_process(streamPtr, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = dstSize - streamPtr.pointee.dst_size
                if produced > 0 { try emit(UnsafeBufferPointer(start: dst, count: produced)) }
                switch status {
                case COMPRESSION_STATUS_OK:
                    if produced == 0 && streamPtr.pointee.src_size == 0 { throw ZipError.damaged("truncated data") }
                case COMPRESSION_STATUS_END: return
                default: throw ZipError.damaged("bad compressed data")
                }
            }
        }
    }
}

extension CRC32 {
    /// A CRC-32 fed in pieces.
    public struct Running: Sendable {
        private var c: UInt32 = 0xFFFF_FFFF
        public init() {}
        public mutating func update(_ bytes: UnsafeBufferPointer<UInt8>) { c = CRC32.continue(c, bytes) }
        public var value: UInt32 { c ^ 0xFFFF_FFFF }
    }
}
