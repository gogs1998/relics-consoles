import Foundation

/// One function serialises *and* restores a component, so the two directions can't drift apart:
///
///     func sync(_ s: inout StateCoder) { s.sync(&a); s.sync(&x); s.bytes(ram, count: 0x800) }
public struct StateCoder {
    public enum Mode: Sendable { case write, read }
    public let mode: Mode
    public private(set) var data: [UInt8]
    private var pos = 0
    public private(set) var failed: String?

    public static func writer() -> StateCoder { StateCoder(mode: .write, data: []) }
    public static func reader(_ data: Data) -> StateCoder { StateCoder(mode: .read, data: [UInt8](data)) }

    private init(mode: Mode, data: [UInt8]) {
        self.mode = mode
        self.data = data
        if mode == .write { self.data.reserveCapacity(32 * 1024) }
    }

    public var isReading: Bool { mode == .read }

    /// Bytes left to read (for an optional trailing section older states don't have).
    public var remaining: Int { mode == .read ? data.count - pos : 0 }

    private mutating func take(_ n: Int) -> Int? {
        guard failed == nil else { return nil }
        guard pos + n <= data.count else { failed = "state ends early"; return nil }
        defer { pos += n }
        return pos
    }

    /// A 4-character section tag. Catches layout drift instead of loading garbage.
    public mutating func section(_ tag: StaticString) {
        let bytes = Array(UnsafeBufferPointer(start: tag.utf8Start, count: tag.utf8CodeUnitCount))
        switch mode {
        case .write: data.append(contentsOf: bytes)
        case .read:
            guard let p = take(bytes.count) else { return }
            if Array(data[p..<p + bytes.count]) != bytes { failed = "section \(tag) out of place" }
        }
    }

    public mutating func sync(_ v: inout UInt8) {
        switch mode {
        case .write: data.append(v)
        case .read: if let p = take(1) { v = data[p] }
        }
    }

    public mutating func sync(_ v: inout Bool) {
        var b: UInt8 = v ? 1 : 0
        sync(&b)
        v = b != 0
    }

    public mutating func sync(_ v: inout Int8) {
        var b = UInt8(bitPattern: v)
        sync(&b)
        v = Int8(bitPattern: b)
    }

    public mutating func sync(_ v: inout UInt16) {
        var w = UInt64(v)
        syncFixed(&w, bytes: 2)
        v = UInt16(truncatingIfNeeded: w)
    }

    public mutating func sync(_ v: inout UInt32) {
        var w = UInt64(v)
        syncFixed(&w, bytes: 4)
        v = UInt32(truncatingIfNeeded: w)
    }

    public mutating func sync(_ v: inout UInt64) { syncFixed(&v, bytes: 8) }

    public mutating func sync(_ v: inout Int) {
        var w = UInt64(bitPattern: Int64(v))
        syncFixed(&w, bytes: 8)
        v = Int(Int64(bitPattern: w))
    }

    public mutating func sync(_ v: inout Int32) {
        var w = UInt64(UInt32(bitPattern: v))
        syncFixed(&w, bytes: 4)
        v = Int32(bitPattern: UInt32(truncatingIfNeeded: w))
    }

    public mutating func sync(_ v: inout Double) {
        var w = v.bitPattern
        syncFixed(&w, bytes: 8)
        v = Double(bitPattern: w)
    }

    public mutating func sync(_ v: inout Float) {
        var w = UInt64(v.bitPattern)
        syncFixed(&w, bytes: 4)
        v = Float(bitPattern: UInt32(truncatingIfNeeded: w))
    }

    private mutating func syncFixed(_ v: inout UInt64, bytes: Int) {
        switch mode {
        case .write:
            for i in 0..<bytes { data.append(UInt8(truncatingIfNeeded: v >> (8 * UInt64(i)))) }
        case .read:
            guard let p = take(bytes) else { return }
            var w: UInt64 = 0
            for i in 0..<bytes { w |= UInt64(data[p + i]) << (8 * UInt64(i)) }
            v = w
        }
    }

    /// Raw memory, e.g. RAM. The length is part of the format: a mismatch fails the load.
    public mutating func bytes(_ p: UnsafeMutablePointer<UInt8>, count: Int) {
        var n = UInt32(count)
        sync(&n)
        switch mode {
        case .write:
            data.append(contentsOf: UnsafeBufferPointer(start: p, count: count))
        case .read:
            guard Int(n) == count else { failed = failed ?? "memory block size \(n) != \(count)"; return }
            guard let at = take(count) else { return }
            data.withUnsafeBufferPointer { src in
                p.update(from: src.baseAddress! + at, count: count)
            }
        }
    }

    public mutating func array<T: FixedWidthInteger>(_ a: inout [T]) {
        var n = UInt32(a.count)
        sync(&n)
        if mode == .read, Int(n) != a.count { failed = failed ?? "array size \(n) != \(a.count)"; return }
        for i in 0..<a.count {
            var w = UInt64(truncatingIfNeeded: a[i])
            syncFixed(&w, bytes: MemoryLayout<T>.size)
            a[i] = T(truncatingIfNeeded: w)
        }
    }

    public var result: Data { Data(data) }
}

/// The file-level wrapper around a core's payload: magic, versions, system, ROM checksum.
public struct StateContainer: Sendable {
    public static let magic: [UInt8] = Array("FBST".utf8)
    public static let containerVersion: UInt16 = 1

    public var system: SystemID
    public var coreStateVersion: UInt32
    public var romCRC: UInt32
    public var created: Date
    public var payload: Data

    public init(system: SystemID, coreStateVersion: UInt32, romCRC: UInt32, created: Date = Date(), payload: Data) {
        self.system = system
        self.coreStateVersion = coreStateVersion
        self.romCRC = romCRC
        self.created = created
        self.payload = payload
    }

    public func encoded() -> Data {
        var out = Data(Self.magic)
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        put(Self.containerVersion)
        let sys = Array(system.rawValue.utf8)
        put(UInt8(sys.count))
        out.append(contentsOf: sys)
        put(coreStateVersion)
        put(romCRC)
        put(UInt64(created.timeIntervalSince1970))
        put(UInt32(payload.count))
        out.append(payload)
        return out
    }

    public static func decode(_ data: Data) throws -> StateContainer {
        let b = [UInt8](data)
        var i = 0
        func need(_ n: Int) throws { if i + n > b.count { throw CoreError.stateMismatch("the file is truncated") } }
        func get<T: FixedWidthInteger>(_: T.Type) throws -> T {
            try need(MemoryLayout<T>.size)
            var v: T = 0
            for k in 0..<MemoryLayout<T>.size { v |= T(b[i + k]) << (8 * k) }
            i += MemoryLayout<T>.size
            return v
        }
        try need(4)
        guard Array(b[0..<4]) == magic else { throw CoreError.stateMismatch("it isn't a save state") }
        i = 4
        let version = try get(UInt16.self)
        guard version == containerVersion else { throw CoreError.stateMismatch("it was made by a newer version of the app") }
        let n = Int(try get(UInt8.self))
        try need(n)
        guard let sys = SystemID(rawValue: String(decoding: b[i..<i + n], as: UTF8.self)) else {
            throw CoreError.stateMismatch("unknown system")
        }
        i += n
        let coreVersion = try get(UInt32.self)
        let crc = try get(UInt32.self)
        let created = Date(timeIntervalSince1970: TimeInterval(try get(UInt64.self)))
        let len = Int(try get(UInt32.self))
        try need(len)
        return StateContainer(system: sys, coreStateVersion: coreVersion, romCRC: crc, created: created,
                              payload: Data(b[i..<i + len]))
    }
}

public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func `continue`(_ crc: UInt32, _ bytes: UnsafeBufferPointer<UInt8>) -> UInt32 {
        var c = crc
        for byte in bytes { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c
    }

    public static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { raw in
            for byte in raw.bindMemory(to: UInt8.self) {
                c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
            }
        }
        return c ^ 0xFFFFFFFF
    }
}
