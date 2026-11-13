import CoreKit
import Foundation

/// A Game Boy cartridge: ROM, optional RAM, and the bank controller (none, MBC1, MBC2, MBC3, MBC5).
///
/// The CPU reads ROM through two precomputed byte offsets (`lo` for $0000-$3FFF, `hi` for
/// $4000-$7FFF), so a bank switch costs a little work on the write and nothing on the read.
final class Cartridge {
    enum Kind: UInt8 { case none, mbc1, mbc2, mbc3, mbc5 }

    let kind: Kind
    let rom: UnsafeMutablePointer<UInt8>
    let romSize: Int
    let romBankMask: Int
    let ram: UnsafeMutablePointer<UInt8>
    let ramSize: Int
    let hasBattery: Bool
    let hasRTC: Bool
    let isCGB: Bool
    let crc: UInt32

    // mapping
    var lo = 0
    var hi = 0x4000
    var ramOn = false
    var ramOff = 0

    // controller registers
    var bankLo: Int = 1     // MBC1 5-bit / MBC2 4-bit / MBC3 7-bit / MBC5 low 8 bits
    var bankHi: Int = 0     // MBC1 2-bit upper / MBC5 bit 8
    var mode: UInt8 = 0     // MBC1 banking mode
    var ramBank: Int = 0    // MBC3 0-3 RAM, 8-12 RTC; MBC5 0-15
    var latchPrev: UInt8 = 0xFF
    var rtc = [UInt8](repeating: 0, count: 5)
    var rtcLatched = [UInt8](repeating: 0, count: 5)
    /// Sub-second progress of the MBC3 clock, in microseconds.
    var rtcSub = 0
    static let rtcUnitsPerSecond = 1_000_000
    /// The clock's time source (seconds since 1970). The MBC3 crystal keeps real time whatever the
    /// emulator does (paused, fast-forward, rewind), so the clock follows the wall clock.
    var wallClock: () -> Double = { Date().timeIntervalSince1970 }
    /// When the clock last caught up with `wallClock`.
    var rtcLastWall: Double = 0

    init(rom data: Data) throws {
        guard data.count >= 0x150 else { throw CoreError.corruptFile("too short for a Game Boy cartridge") }
        let header = [UInt8](data.prefix(0x150))
        let type = header[0x147]
        var battery = false, rtc = false, hasRAM = false
        switch type {
        case 0x00: kind = .none
        case 0x08: kind = .none; hasRAM = true
        case 0x09: kind = .none; hasRAM = true; battery = true
        case 0x01: kind = .mbc1
        case 0x02: kind = .mbc1; hasRAM = true
        case 0x03: kind = .mbc1; hasRAM = true; battery = true
        case 0x05: kind = .mbc2
        case 0x06: kind = .mbc2; battery = true
        case 0x0F: kind = .mbc3; rtc = true; battery = true
        case 0x10: kind = .mbc3; rtc = true; battery = true; hasRAM = true
        case 0x11: kind = .mbc3
        case 0x12: kind = .mbc3; hasRAM = true
        case 0x13: kind = .mbc3; hasRAM = true; battery = true
        case 0x19, 0x1C: kind = .mbc5
        case 0x1A, 0x1D: kind = .mbc5; hasRAM = true
        case 0x1B, 0x1E: kind = .mbc5; hasRAM = true; battery = true
        default: throw CoreError.unsupportedMapper(Int(type))
        }
        hasBattery = battery
        hasRTC = rtc
        isCGB = (header[0x143] & 0x80) != 0

        // ROM: padded up to a power of two of 16 KB banks (at least two).
        var banks = 2
        while banks * 0x4000 < data.count { banks *= 2 }
        romSize = banks * 0x4000
        romBankMask = banks - 1
        let romBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: banks * 0x4000)
        romBuf.initialize(repeating: 0xFF, count: banks * 0x4000)
        data.withUnsafeBytes { raw in
            romBuf.update(from: raw.bindMemory(to: UInt8.self).baseAddress!, count: data.count)
        }
        rom = romBuf

        if kind == .mbc2 {
            ramSize = 512
        } else if hasRAM {
            switch header[0x149] {
            case 0x01: ramSize = 0x800
            case 0x02: ramSize = 0x2000
            case 0x03: ramSize = 0x8000
            case 0x04: ramSize = 0x20000
            case 0x05: ramSize = 0x10000
            default: ramSize = 0x2000   // header says none but the type has RAM: be generous
            }
        } else {
            ramSize = 0
        }
        ram = .allocate(capacity: max(ramSize, 1))
        ram.initialize(repeating: 0xFF, count: max(ramSize, 1))
        crc = CRC32.checksum(data)
        rtcLastWall = wallClock()
        reset()
    }

    deinit {
        rom.deallocate()
        ram.deallocate()
    }

    func reset() {
        bankLo = 1
        bankHi = 0
        mode = 0
        ramBank = 0
        latchPrev = 0xFF
        ramOn = kind == .none && ramSize > 0
        if kind == .mbc5 { bankLo = 1 }
        update()
    }

    func loadBattery(_ data: Data, now: Date? = nil) {
        let now = now ?? Date(timeIntervalSince1970: wallClock())
        let n = min(data.count, ramSize)
        if n > 0 {
            data.withUnsafeBytes { raw in ram.update(from: raw.bindMemory(to: UInt8.self).baseAddress!, count: n) }
        }
        // The widely used RTC footer after the RAM: 5 registers and 5 latched registers as 32-bit
        // little-endian words, then a 64-bit (or 32-bit) Unix timestamp of when it was saved.
        let footer = data.count - ramSize
        guard hasRTC, footer == 48 || footer == 44 else { return }
        let b = [UInt8](data.suffix(footer))
        func word(_ i: Int) -> UInt8 { b[i * 4] }
        for i in 0..<5 { rtc[i] = word(i); rtcLatched[i] = word(5 + i) }
        var stamp: UInt64 = 0
        for i in 0..<(footer - 40) { stamp |= UInt64(b[40 + i]) << (8 * UInt64(i)) }
        let elapsed = Int(now.timeIntervalSince1970) - Int(stamp)
        if stamp > 0, elapsed > 0 { advanceRTC(seconds: min(elapsed, Self.maxCatchUp)) }
        rtcLastWall = now.timeIntervalSince1970
    }

    /// Longest stretch of real time the clock catches up in one go (ten years).
    static let maxCatchUp = 10 * 365 * 86_400

    /// Battery contents: RAM, plus the RTC footer for clock cartridges (the format VBA-M, BGB and
    /// mGBA share: 5 registers then 5 latched registers as 32-bit little-endian words, then the
    /// 64-bit little-endian Unix time of the save).
    func batteryData(now: Date? = nil) -> Data? {
        let now = now ?? Date(timeIntervalSince1970: wallClock())
        guard hasBattery else { return nil }
        var d = ramSize > 0 ? Data(bytes: ram, count: ramSize) : Data()
        if hasRTC {
            for v in rtc + rtcLatched { d.append(contentsOf: [v, 0, 0, 0]) }
            var t = UInt64(max(0, now.timeIntervalSince1970))
            for _ in 0..<8 { d.append(UInt8(t & 0xFF)); t >>= 8 }
        }
        return d.isEmpty ? nil : d
    }

    /// Catches the clock up with real time (called once per frame). Time while halted is lost,
    /// as on the cartridge; a wall clock set backwards is ignored.
    func tickRTC() {
        guard hasRTC else { return }
        let now = wallClock()
        let dt = now - rtcLastWall
        rtcLastWall = now
        guard dt > 0, dt.isFinite else { return }
        addRTC(microseconds: Int((min(dt, Double(Self.maxCatchUp)) * 1_000_000).rounded()))
    }

    func addRTC(microseconds: Int) {
        guard (rtc[4] & 0x40) == 0, microseconds > 0 else { return }
        rtcSub += microseconds
        if rtcSub >= Self.rtcUnitsPerSecond {
            let secs = rtcSub / Self.rtcUnitsPerSecond
            rtcSub -= secs * Self.rtcUnitsPerSecond
            advanceRTC(seconds: secs)
        }
    }

    /// Save states carry the wall time they were made; loading one catches the clock up by the
    /// real time since (the cartridge's crystal never stopped). States without it just carry on.
    func syncRTCWallTime(_ st: inout StateCoder) {
        guard hasRTC else { return }
        if st.isReading {
            let now = wallClock()
            rtcSub = min(max(rtcSub, 0), Self.rtcUnitsPerSecond - 1)
            if st.remaining >= 12 {
                st.section("RTCW")
                var stamp = 0.0
                st.sync(&stamp)
                let elapsed = now - stamp
                if st.failed == nil, stamp > 0, elapsed > 0, elapsed.isFinite {
                    addRTC(microseconds: Int((min(elapsed, Double(Self.maxCatchUp)) * 1_000_000).rounded()))
                }
            }
            rtcLastWall = now
        } else {
            st.section("RTCW")
            var stamp = wallClock()
            st.sync(&stamp)
        }
    }

    func advanceRTC(seconds: Int) {
        guard (rtc[4] & 0x40) == 0, seconds > 0 else { return }
        var s = Int(rtc[0] & 0x3F) + seconds
        var m = Int(rtc[1] & 0x3F) + s / 60
        s %= 60
        var h = Int(rtc[2] & 0x1F) + m / 60
        m %= 60
        var day = (Int(rtc[4] & 1) << 8 | Int(rtc[3])) + h / 24
        h %= 24
        var carry = (rtc[4] & 0x80) != 0
        if day > 511 { carry = true; day %= 512 }
        rtc[0] = UInt8(s); rtc[1] = UInt8(m); rtc[2] = UInt8(h)
        rtc[3] = UInt8(day & 0xFF)
        rtc[4] = (rtc[4] & 0x40) | UInt8(day >> 8) | (carry ? 0x80 : 0)
    }

    private func update() {
        switch kind {
        case .none:
            lo = 0; hi = 0x4000; ramOff = 0
        case .mbc1:
            hi = (((bankHi << 5) | bankLo) & romBankMask) * 0x4000
            lo = mode == 1 ? (((bankHi << 5) & romBankMask) * 0x4000) : 0
            ramOff = mode == 1 && ramSize > 0x2000 ? (bankHi * 0x2000) & (ramSize - 1) : 0
        case .mbc2:
            lo = 0; hi = (bankLo & romBankMask) * 0x4000; ramOff = 0
        case .mbc3:
            lo = 0; hi = (bankLo & romBankMask) * 0x4000
            ramOff = ramSize > 0 ? ((ramBank & 3) * 0x2000) & (ramSize - 1) : 0
        case .mbc5:
            lo = 0; hi = (((bankHi << 8) | bankLo) & romBankMask) * 0x4000
            ramOff = ramSize > 0 ? (ramBank * 0x2000) & (ramSize - 1) : 0
        }
    }

    /// A write to $0000-$7FFF: bank controller registers.
    func writeROM(_ addr: UInt16, _ v: UInt8) {
        switch kind {
        case .none:
            return
        case .mbc1:
            switch addr >> 13 {
            case 0: ramOn = (v & 0x0F) == 0x0A
            case 1: bankLo = Int(v & 0x1F); if bankLo == 0 { bankLo = 1 }
            case 2: bankHi = Int(v & 3)
            default: mode = v & 1
            }
        case .mbc2:
            guard addr < 0x4000 else { return }
            if (addr & 0x100) == 0 {
                ramOn = (v & 0x0F) == 0x0A
            } else {
                bankLo = Int(v & 0x0F); if bankLo == 0 { bankLo = 1 }
            }
        case .mbc3:
            switch addr >> 13 {
            case 0: ramOn = (v & 0x0F) == 0x0A
            case 1: bankLo = Int(v & 0x7F); if bankLo == 0 { bankLo = 1 }
            case 2: ramBank = Int(v & 0x0F)
            default:
                if latchPrev == 0 && v == 1 { rtcLatched = rtc }
                latchPrev = v
            }
        case .mbc5:
            switch addr >> 12 {
            case 0, 1: ramOn = (v & 0x0F) == 0x0A
            case 2: bankLo = Int(v)
            case 3: bankHi = Int(v & 1)
            case 4, 5: ramBank = Int(v & 0x0F)
            default: break
            }
        }
        update()
    }

    @inline(__always)
    func readRAM(_ addr: UInt16) -> UInt8 {
        guard ramOn else { return 0xFF }
        switch kind {
        case .mbc2:
            return ram[Int(addr & 0x1FF)] | 0xF0
        case .mbc3 where ramBank >= 8:
            return ramBank <= 12 ? rtcLatched[ramBank - 8] : 0xFF
        default:
            guard ramSize > 0 else { return 0xFF }
            return ram[(ramOff + Int(addr & 0x1FFF)) & (ramSize - 1)]
        }
    }

    @inline(__always)
    func writeRAM(_ addr: UInt16, _ v: UInt8) {
        guard ramOn else { return }
        switch kind {
        case .mbc2:
            ram[Int(addr & 0x1FF)] = v | 0xF0
        case .mbc3 where ramBank >= 8:
            if ramBank <= 12 {
                let masks: [UInt8] = [0x3F, 0x3F, 0x1F, 0xFF, 0xC1]
                rtc[ramBank - 8] = v & masks[ramBank - 8]
                rtcLatched[ramBank - 8] = rtc[ramBank - 8]
                if ramBank == 8 { rtcSub = 0 }   // writing seconds resets the divider
            }
        default:
            guard ramSize > 0 else { return }
            ram[(ramOff + Int(addr & 0x1FFF)) & (ramSize - 1)] = v
        }
    }

    func sync(_ st: inout StateCoder) {
        st.section("CART")
        st.sync(&bankLo); st.sync(&bankHi); st.sync(&mode); st.sync(&ramBank)
        st.sync(&ramOn); st.sync(&latchPrev)
        st.array(&rtc); st.array(&rtcLatched); st.sync(&rtcSub)
        if ramSize > 0 { st.bytes(ram, count: ramSize) }
        if st.isReading { update() }
    }
}
