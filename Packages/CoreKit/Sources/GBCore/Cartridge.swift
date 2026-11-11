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

    func loadBattery(_ data: Data) {
        let n = min(data.count, ramSize)
        guard n > 0 else { return }
        data.withUnsafeBytes { raw in ram.update(from: raw.bindMemory(to: UInt8.self).baseAddress!, count: n) }
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
            if ramBank <= 12 { rtc[ramBank - 8] = v; rtcLatched[ramBank - 8] = v }
        default:
            guard ramSize > 0 else { return }
            ram[(ramOff + Int(addr & 0x1FFF)) & (ramSize - 1)] = v
        }
    }

    func sync(_ st: inout StateCoder) {
        st.section("CART")
        st.sync(&bankLo); st.sync(&bankHi); st.sync(&mode); st.sync(&ramBank)
        st.sync(&ramOn); st.sync(&latchPrev)
        st.array(&rtc); st.array(&rtcLatched)
        if ramSize > 0 { st.bytes(ram, count: ramSize) }
        if st.isReading { update() }
    }
}
