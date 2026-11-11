import CoreKit
import Foundation

enum Mirroring: UInt8 {
    case horizontal, vertical, singleLow, singleHigh, fourScreen
}

/// iNES cartridge: PRG ROM, CHR ROM or RAM, PRG RAM, and the bank tables mappers edit.
///
/// The CPU and PPU read through 8 KB PRG and 1 KB CHR bank offsets, so the hot path never
/// calls the mapper; mappers only run on writes and once per scanline.
final class Cartridge {
    let prg: UnsafeMutablePointer<UInt8>
    let prgSize: Int
    let chr: UnsafeMutablePointer<UInt8>
    let chrSize: Int
    let chrIsRAM: Bool
    let prgRAM: UnsafeMutablePointer<UInt8>
    let prgRAMSize = 0x2000
    let hasBattery: Bool
    let mapperNumber: Int
    let headerMirroring: Mirroring
    let crc: UInt32

    /// Offsets into `prg` for $8000, $A000, $C000, $E000.
    var prgBank: (Int, Int, Int, Int) = (0, 0, 0, 0)
    /// Offsets into `chr` for each 1 KB of $0000-$1FFF.
    let chrBank: UnsafeMutablePointer<Int> = {
        let p = UnsafeMutablePointer<Int>.allocate(capacity: 8)
        p.initialize(repeating: 0, count: 8)
        return p
    }()
    var prgRAMEnabled = true
    var prgRAMWritable = true
    var mirroring: Mirroring

    init(rom data: Data) throws {
        let b = [UInt8](data)
        guard b.count >= 16, b[0] == 0x4E, b[1] == 0x45, b[2] == 0x53, b[3] == 0x1A else {
            throw CoreError.unrecognisedFile
        }
        let isNES2 = (b[7] & 0x0C) == 0x08
        var prgUnits = Int(b[4])
        var chrUnits = Int(b[5])
        if isNES2 {
            prgUnits |= Int(b[9] & 0x0F) << 8
            chrUnits |= Int(b[9] & 0xF0) << 4
        }
        let flags6 = b[6]
        // Old dumps carry junk ("DiskDude!") in bytes 7-15: ignore the high nibble then.
        let junk = !isNES2 && b[12...15].contains { $0 != 0 }
        mapperNumber = Int(flags6 >> 4) | (junk ? 0 : Int(b[7] & 0xF0))
        hasBattery = (flags6 & 0x02) != 0
        if (flags6 & 0x08) != 0 {
            headerMirroring = .fourScreen
        } else {
            headerMirroring = (flags6 & 0x01) != 0 ? .vertical : .horizontal
        }
        mirroring = headerMirroring
        let trainer = (flags6 & 0x04) != 0 ? 512 : 0
        prgSize = prgUnits * 0x4000
        let chrROMSize = chrUnits * 0x2000
        let start = 16 + trainer
        guard prgSize > 0, b.count >= start + prgSize else { throw CoreError.corruptFile("program data is missing") }
        let chrAvailable = min(chrROMSize, b.count - start - prgSize)

        let prgSizeLocal = prgSize
        let prgMem = UnsafeMutablePointer<UInt8>.allocate(capacity: prgSizeLocal)
        b.withUnsafeBufferPointer { src in prgMem.update(from: src.baseAddress! + start, count: prgSizeLocal) }
        prg = prgMem

        chrIsRAM = chrROMSize == 0
        chrSize = chrIsRAM ? 0x2000 : chrROMSize
        let chrMem = UnsafeMutablePointer<UInt8>.allocate(capacity: chrSize)
        chrMem.initialize(repeating: 0, count: chrSize)
        if chrROMSize > 0, chrAvailable > 0 {
            b.withUnsafeBufferPointer { src in chrMem.update(from: src.baseAddress! + start + prgSizeLocal, count: chrAvailable) }
        }
        chr = chrMem
        prgRAM = .allocate(capacity: prgRAMSize)
        prgRAM.initialize(repeating: 0, count: prgRAMSize)
        crc = CRC32.checksum(Data(b[start..<(start + prgSize)]))
    }

    deinit {
        prg.deallocate()
        chr.deallocate()
        prgRAM.deallocate()
        chrBank.deallocate()
    }

    // MARK: bank helpers (sizes in bytes; negative index counts from the end)

    func prgOffset8K(_ bank: Int) -> Int {
        let count = max(1, prgSize / 0x2000)
        let n = ((bank % count) + count) % count
        return n * 0x2000
    }

    func setPRG8K(_ slot: Int, _ bank: Int) {
        let off = prgOffset8K(bank)
        switch slot {
        case 0: prgBank.0 = off
        case 1: prgBank.1 = off
        case 2: prgBank.2 = off
        default: prgBank.3 = off
        }
    }

    func setPRG16K(_ slot: Int, _ bank: Int) {
        setPRG8K(slot * 2, bank * 2)
        setPRG8K(slot * 2 + 1, bank * 2 + 1)
    }

    func setPRG32K(_ bank: Int) {
        for i in 0..<4 { setPRG8K(i, bank * 4 + i) }
    }

    func setCHR1K(_ slot: Int, _ bank: Int) {
        let count = max(1, chrSize / 0x400)
        chrBank[slot] = (((bank % count) + count) % count) * 0x400
    }

    func setCHR2K(_ slot: Int, _ bank: Int) {
        setCHR1K(slot * 2, bank * 2)
        setCHR1K(slot * 2 + 1, bank * 2 + 1)
    }

    func setCHR4K(_ slot: Int, _ bank: Int) {
        for i in 0..<4 { setCHR1K(slot * 4 + i, bank * 4 + i) }
    }

    func setCHR8K(_ bank: Int) {
        for i in 0..<8 { setCHR1K(i, bank * 8 + i) }
    }

    @inline(__always)
    func readPRG(_ addr: UInt16) -> UInt8 {
        let a = Int(addr & 0x1FFF)
        switch addr >> 13 {
        case 4: return prg[prgBank.0 + a]
        case 5: return prg[prgBank.1 + a]
        case 6: return prg[prgBank.2 + a]
        default: return prg[prgBank.3 + a]
        }
    }

    @inline(__always)
    func readCHR(_ addr: UInt16) -> UInt8 {
        chr[chrBank[Int(addr >> 10) & 7] + Int(addr & 0x3FF)]
    }

    @inline(__always)
    func writeCHR(_ addr: UInt16, _ value: UInt8) {
        guard chrIsRAM else { return }
        chr[chrBank[Int(addr >> 10) & 7] + Int(addr & 0x3FF)] = value
    }

    func sync(_ s: inout StateCoder) {
        s.section("CART")
        var p0 = prgBank.0, p1 = prgBank.1, p2 = prgBank.2, p3 = prgBank.3
        s.sync(&p0); s.sync(&p1); s.sync(&p2); s.sync(&p3)
        prgBank = (p0, p1, p2, p3)
        for i in 0..<8 { s.sync(&chrBank[i]) }
        s.sync(&prgRAMEnabled)
        s.sync(&prgRAMWritable)
        var m = mirroring.rawValue
        s.sync(&m)
        mirroring = Mirroring(rawValue: m) ?? headerMirroring
        s.bytes(prgRAM, count: prgRAMSize)
        if chrIsRAM { s.bytes(chr, count: chrSize) }
    }
}

/// Cartridge logic that runs on CPU writes to $6000-$FFFF and once per rendered scanline.
class Mapper {
    unowned let cart: Cartridge
    var irqAsserted = false

    init(cart: Cartridge) {
        self.cart = cart
        cart.setPRG32K(0)
        cart.setCHR8K(0)
    }

    /// Called for writes to $8000-$FFFF. `cycle` is the CPU cycle count.
    func write(_ addr: UInt16, _ value: UInt8, cycle: UInt64) {}
    /// Called near dot 260 of each rendered line while rendering is on (MMC3's counter).
    func scanline() {}
    func sync(_ s: inout StateCoder) {}

    static func make(for cart: Cartridge) throws -> Mapper {
        switch cart.mapperNumber {
        case 0: return NROM(cart: cart)
        case 1: return MMC1(cart: cart)
        case 2: return UxROM(cart: cart)
        case 3: return CNROM(cart: cart)
        case 4: return MMC3(cart: cart)
        case 7: return AxROM(cart: cart)
        default: throw CoreError.unsupportedMapper(cart.mapperNumber)
        }
    }
}

/// Mapper 0. 16 KB carts mirror the bank at $C000.
final class NROM: Mapper {
    override init(cart: Cartridge) {
        super.init(cart: cart)
        cart.setPRG16K(0, 0)
        cart.setPRG16K(1, -1)
    }
}

/// Mapper 2: switchable 16 KB at $8000, last bank fixed at $C000.
final class UxROM: Mapper {
    var bank: UInt8 = 0
    override init(cart: Cartridge) {
        super.init(cart: cart)
        cart.setPRG16K(0, 0)
        cart.setPRG16K(1, -1)
    }
    override func write(_ addr: UInt16, _ value: UInt8, cycle: UInt64) {
        bank = value
        cart.setPRG16K(0, Int(value))
    }
    override func sync(_ s: inout StateCoder) {
        s.section("UXRM")
        s.sync(&bank)
        if s.isReading { cart.setPRG16K(0, Int(bank)) }
    }
}

/// Mapper 3: 8 KB CHR bank select.
final class CNROM: Mapper {
    var bank: UInt8 = 0
    override init(cart: Cartridge) {
        super.init(cart: cart)
        cart.setPRG16K(0, 0)
        cart.setPRG16K(1, -1)
    }
    override func write(_ addr: UInt16, _ value: UInt8, cycle: UInt64) {
        bank = value
        cart.setCHR8K(Int(value))
    }
    override func sync(_ s: inout StateCoder) {
        s.section("CNRM")
        s.sync(&bank)
        if s.isReading { cart.setCHR8K(Int(bank)) }
    }
}

/// Mapper 7: 32 KB PRG banks, single-screen mirroring.
final class AxROM: Mapper {
    var reg: UInt8 = 0
    override init(cart: Cartridge) {
        super.init(cart: cart)
        apply()
    }
    override func write(_ addr: UInt16, _ value: UInt8, cycle: UInt64) {
        reg = value
        apply()
    }
    private func apply() {
        cart.setPRG32K(Int(reg & 0x07))
        cart.mirroring = (reg & 0x10) != 0 ? .singleHigh : .singleLow
    }
    override func sync(_ s: inout StateCoder) {
        s.section("AXRM")
        s.sync(&reg)
        if s.isReading { apply() }
    }
}

/// Mapper 1 (MMC1): a 5-bit serial port into four registers.
final class MMC1: Mapper {
    var shift: UInt8 = 0x10
    var control: UInt8 = 0x0C
    var chr0: UInt8 = 0
    var chr1: UInt8 = 0
    var prgReg: UInt8 = 0
    var lastWriteCycle: UInt64 = 0

    override init(cart: Cartridge) {
        super.init(cart: cart)
        apply()
    }

    override func write(_ addr: UInt16, _ value: UInt8, cycle: UInt64) {
        // Writes on consecutive cycles (read-modify-write instructions) are ignored.
        defer { lastWriteCycle = cycle }
        if cycle &- lastWriteCycle < 2 { return }
        if (value & 0x80) != 0 {
            shift = 0x10
            control |= 0x0C
            apply()
            return
        }
        let complete = (shift & 1) != 0
        shift = (shift >> 1) | ((value & 1) << 4)
        if complete {
            switch (addr >> 13) & 3 {
            case 0: control = shift
            case 1: chr0 = shift
            case 2: chr1 = shift
            default: prgReg = shift
            }
            shift = 0x10
            apply()
        }
    }

    private func apply() {
        switch control & 3 {
        case 0: cart.mirroring = .singleLow
        case 1: cart.mirroring = .singleHigh
        case 2: cart.mirroring = .vertical
        default: cart.mirroring = .horizontal
        }
        // 512 KB carts (SUROM) use CHR bit 4 as the outer PRG bank.
        let outer = cart.prgSize > 0x40000 ? Int(chr0 & 0x10) : 0
        let bank = Int(prgReg & 0x0F) | outer
        switch (control >> 2) & 3 {
        case 0, 1: cart.setPRG32K(bank >> 1)
        case 2:
            cart.setPRG16K(0, outer)
            cart.setPRG16K(1, bank)
        default:
            cart.setPRG16K(0, bank)
            cart.setPRG16K(1, outer | 0x0F)
        }
        if (control & 0x10) != 0 {
            cart.setCHR4K(0, Int(chr0))
            cart.setCHR4K(1, Int(chr1))
        } else {
            cart.setCHR8K(Int(chr0 >> 1))
        }
        cart.prgRAMEnabled = (prgReg & 0x10) == 0
    }

    override func sync(_ s: inout StateCoder) {
        s.section("MMC1")
        s.sync(&shift); s.sync(&control); s.sync(&chr0); s.sync(&chr1); s.sync(&prgReg)
        s.sync(&lastWriteCycle)
        if s.isReading { apply() }
    }
}

/// Mapper 4 (MMC3): eight bank registers and a scanline counter IRQ.
final class MMC3: Mapper {
    var bankSelect: UInt8 = 0
    var regs = [UInt8](repeating: 0, count: 8)
    var mirrorReg: UInt8 = 0
    var ramProtect: UInt8 = 0x80
    var irqLatch: UInt8 = 0
    var irqCounter: UInt8 = 0
    var irqReload = false
    var irqEnabled = false

    override init(cart: Cartridge) {
        super.init(cart: cart)
        regs = [0, 2, 4, 5, 6, 7, 0, 1]
        apply()
    }

    override func write(_ addr: UInt16, _ value: UInt8, cycle: UInt64) {
        let even = (addr & 1) == 0
        switch addr & 0xE000 {
        case 0x8000:
            if even { bankSelect = value } else { regs[Int(bankSelect & 7)] = value }
            apply()
        case 0xA000:
            if even {
                mirrorReg = value
                if cart.headerMirroring != .fourScreen {
                    cart.mirroring = (value & 1) != 0 ? .horizontal : .vertical
                }
            } else {
                ramProtect = value
                cart.prgRAMEnabled = (value & 0x80) != 0
                cart.prgRAMWritable = (value & 0x40) == 0
            }
        case 0xC000:
            if even { irqLatch = value } else { irqCounter = 0; irqReload = true }
        default:
            if even { irqEnabled = false; irqAsserted = false } else { irqEnabled = true }
        }
    }

    private func apply() {
        let prgMode = (bankSelect & 0x40) != 0
        cart.setPRG8K(prgMode ? 2 : 0, Int(regs[6]))
        cart.setPRG8K(1, Int(regs[7]))
        cart.setPRG8K(prgMode ? 0 : 2, -2)
        cart.setPRG8K(3, -1)
        let chrInvert = (bankSelect & 0x80) != 0
        let base2K = chrInvert ? 4 : 0
        let base1K = chrInvert ? 0 : 4
        cart.setCHR1K(base2K + 0, Int(regs[0] & 0xFE))
        cart.setCHR1K(base2K + 1, Int(regs[0] | 0x01))
        cart.setCHR1K(base2K + 2, Int(regs[1] & 0xFE))
        cart.setCHR1K(base2K + 3, Int(regs[1] | 0x01))
        cart.setCHR1K(base1K + 0, Int(regs[2]))
        cart.setCHR1K(base1K + 1, Int(regs[3]))
        cart.setCHR1K(base1K + 2, Int(regs[4]))
        cart.setCHR1K(base1K + 3, Int(regs[5]))
    }

    override func scanline() {
        if irqCounter == 0 || irqReload {
            irqCounter = irqLatch
            irqReload = false
        } else {
            irqCounter &-= 1
        }
        if irqCounter == 0 && irqEnabled {
            irqAsserted = true
        }
    }

    override func sync(_ s: inout StateCoder) {
        s.section("MMC3")
        s.sync(&bankSelect); s.array(&regs); s.sync(&mirrorReg); s.sync(&ramProtect)
        s.sync(&irqLatch); s.sync(&irqCounter); s.sync(&irqReload); s.sync(&irqEnabled); s.sync(&irqAsserted)
        if s.isReading { apply() }
    }
}
