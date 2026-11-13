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
    /// $6000-$7FFF from PRG ROM at this offset (FME-7), or -1 for PRG RAM.
    var prgLowROM = -1

    /// MMC2 (9) / MMC4 (10) CHR latches: 0 when the mapper has none. A PPU fetch of tile $FD or
    /// $FE's upper plane flips the latch for that pattern table; the next fetch sees the new bank.
    var latchKind = 0
    var latch0: UInt8 = 0xFE
    var latch1: UInt8 = 0xFE
    /// 4 KB CHR banks: $0000 when latch 0 = FD, = FE; $1000 when latch 1 = FD, = FE.
    var latchBanks: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)

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
        let v = chr[chrBank[Int(addr >> 10) & 7] + Int(addr & 0x3FF)]
        if latchKind != 0 { latchFetched(addr) }
        return v
    }

    /// MMC2 watches $0FD8 / $0FE8 exactly for latch 0; MMC4 the whole rows $0FD8-$0FDF and
    /// $0FE8-$0FEF. Both watch $1FD8-$1FDF / $1FE8-$1FEF for latch 1.
    func latchFetched(_ addr: UInt16) {
        let a = addr & 0x1FFF
        if a < 0x1000 {
            let key = latchKind == 9 ? a : a & 0xFFF8
            if key == 0x0FD8 { latch0 = 0xFD } else if key == 0x0FE8 { latch0 = 0xFE } else { return }
        } else {
            switch a & 0xFFF8 {
            case 0x1FD8: latch1 = 0xFD
            case 0x1FE8: latch1 = 0xFE
            default: return
            }
        }
        applyLatches()
    }

    func applyLatches() {
        setCHR4K(0, Int(latch0 == 0xFD ? latchBanks.0 : latchBanks.1))
        setCHR4K(1, Int(latch1 == 0xFD ? latchBanks.2 : latchBanks.3))
    }

    @inline(__always)
    func readLow(_ addr: UInt16, openBus: UInt8) -> UInt8 {
        if prgLowROM >= 0 { return prg[prgLowROM + Int(addr & 0x1FFF)] }
        return prgRAMEnabled ? prgRAM[Int(addr & 0x1FFF)] : openBus
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
    /// True if `cpuCycle()` must run every CPU cycle (FME-7's IRQ counter).
    var clocksCPU: Bool { false }
    func cpuCycle() {}
    func sync(_ s: inout StateCoder) {}

    static func make(for cart: Cartridge) throws -> Mapper {
        switch cart.mapperNumber {
        case 0: return NROM(cart: cart)
        case 1: return MMC1(cart: cart)
        case 2: return UxROM(cart: cart)
        case 3: return CNROM(cart: cart)
        case 4: return MMC3(cart: cart)
        case 7: return AxROM(cart: cart)
        case 9: return MMC2(cart: cart, mmc4: false)
        case 10: return MMC2(cart: cart, mmc4: true)
        case 11: return ColorDreams(cart: cart)
        case 66: return GxROM(cart: cart)
        case 69: return FME7(cart: cart)
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

/// Mappers 9 (MMC2, PxROM) and 10 (MMC4, FxROM): PRG bank at $8000 (8 KB on MMC2, 16 KB on
/// MMC4), four 4 KB CHR registers chosen by the two latches, and a mirroring register.
final class MMC2: Mapper {
    let mmc4: Bool
    var prgReg: UInt8 = 0
    var mirror: UInt8 = 0
    var regs = [UInt8](repeating: 0, count: 4)

    init(cart: Cartridge, mmc4: Bool) {
        self.mmc4 = mmc4
        super.init(cart: cart)
        cart.latchKind = mmc4 ? 10 : 9
        cart.latch0 = 0xFE
        cart.latch1 = 0xFE
        apply()
    }

    override func write(_ addr: UInt16, _ value: UInt8, cycle: UInt64) {
        switch addr & 0xF000 {
        case 0xA000: prgReg = value & 0x0F
        case 0xB000: regs[0] = value & 0x1F
        case 0xC000: regs[1] = value & 0x1F
        case 0xD000: regs[2] = value & 0x1F
        case 0xE000: regs[3] = value & 0x1F
        case 0xF000: mirror = value & 1
        default: return
        }
        apply()
    }

    private func apply() {
        if mmc4 {
            cart.setPRG16K(0, Int(prgReg))
            cart.setPRG16K(1, -1)
        } else {
            cart.setPRG8K(0, Int(prgReg))
            cart.setPRG8K(1, -3)
            cart.setPRG8K(2, -2)
            cart.setPRG8K(3, -1)
        }
        cart.latchBanks = (regs[0], regs[1], regs[2], regs[3])
        cart.applyLatches()
        if cart.headerMirroring != .fourScreen { cart.mirroring = mirror == 1 ? .horizontal : .vertical }
    }

    override func sync(_ s: inout StateCoder) {
        s.section("MMC2")
        s.sync(&prgReg); s.sync(&mirror); s.array(&regs)
        s.sync(&cart.latch0); s.sync(&cart.latch1)
        if s.isReading { apply() }
    }
}

/// Mapper 11 (Color Dreams): one register anywhere in $8000-$FFFF, 32 KB PRG in bits 0-1 and
/// 8 KB CHR in bits 4-7. The board has bus conflicts: the ROM byte under the write wins ties.
final class ColorDreams: Mapper {
    var reg: UInt8 = 0
    override init(cart: Cartridge) {
        super.init(cart: cart)
        apply()
    }
    override func write(_ addr: UInt16, _ value: UInt8, cycle: UInt64) {
        reg = value & cart.readPRG(addr)
        apply()
    }
    private func apply() {
        cart.setPRG32K(Int(reg & 0x03))
        cart.setCHR8K(Int(reg >> 4))
    }
    override func sync(_ s: inout StateCoder) {
        s.section("CDRM")
        s.sync(&reg)
        if s.isReading { apply() }
    }
}

/// Mapper 66 (GxROM / MHROM): 32 KB PRG in bits 4-5, 8 KB CHR in bits 0-1, bus conflicts.
final class GxROM: Mapper {
    var reg: UInt8 = 0
    override init(cart: Cartridge) {
        super.init(cart: cart)
        apply()
    }
    override func write(_ addr: UInt16, _ value: UInt8, cycle: UInt64) {
        reg = value & cart.readPRG(addr)
        apply()
    }
    private func apply() {
        cart.setPRG32K(Int((reg >> 4) & 0x03))
        cart.setCHR8K(Int(reg & 0x03))
    }
    override func sync(_ s: inout StateCoder) {
        s.section("GXRM")
        s.sync(&reg)
        if s.isReading { apply() }
    }
}

/// Mapper 69 (Sunsoft FME-7): a command register ($8000) and its parameter ($A000). Commands 0-7
/// are 1 KB CHR banks, 8 the $6000 window (ROM bank, or RAM when bit 6 is set, enabled by bit 7),
/// 9-B 8 KB PRG banks at $8000/$A000/$C000 ($E000 is the last bank), C mirroring, D IRQ control,
/// E/F the 16-bit counter, which counts down every CPU cycle and raises the IRQ as it wraps
/// from $0000 to $FFFF. The 5B sound chip ($C000/$E000) is not emulated.
final class FME7: Mapper {
    var command: UInt8 = 0
    var regs = [UInt8](repeating: 0, count: 16)
    var irqEnabled = false
    var counterEnabled = false
    var counter: UInt16 = 0

    override init(cart: Cartridge) {
        super.init(cart: cart)
        for c in 0..<0x0D { apply(UInt8(c)) }
    }

    override var clocksCPU: Bool { true }

    override func write(_ addr: UInt16, _ value: UInt8, cycle: UInt64) {
        switch addr & 0xE000 {
        case 0x8000:
            command = value & 0x0F
        case 0xA000:
            regs[Int(command)] = value
            switch command {
            case 0x0D:
                irqEnabled = (value & 0x01) != 0
                counterEnabled = (value & 0x80) != 0
                irqAsserted = false
            case 0x0E: counter = (counter & 0xFF00) | UInt16(value)
            case 0x0F: counter = (counter & 0x00FF) | UInt16(value) << 8
            default: apply(command)
            }
        default:
            break   // 5B audio registers
        }
    }

    private func apply(_ c: UInt8) {
        let v = regs[Int(c)]
        switch c {
        case 0...7: cart.setCHR1K(Int(c), Int(v))
        case 8:
            if (v & 0x40) != 0 {
                cart.prgLowROM = -1
                cart.prgRAMEnabled = (v & 0x80) != 0
                cart.prgRAMWritable = cart.prgRAMEnabled
            } else {
                cart.prgLowROM = cart.prgOffset8K(Int(v & 0x3F))
            }
        case 9, 0x0A, 0x0B:
            cart.setPRG8K(Int(c) - 9, Int(v & 0x3F))
            cart.setPRG8K(3, -1)
        case 0x0C:
            switch v & 3 {
            case 0: cart.mirroring = .vertical
            case 1: cart.mirroring = .horizontal
            case 2: cart.mirroring = .singleLow
            default: cart.mirroring = .singleHigh
            }
        default: break
        }
    }

    @inline(__always)
    override func cpuCycle() {
        guard counterEnabled else { return }
        counter &-= 1
        if counter == 0xFFFF && irqEnabled { irqAsserted = true }
    }

    override func sync(_ s: inout StateCoder) {
        s.section("FME7")
        s.sync(&command); s.array(&regs)
        s.sync(&irqEnabled); s.sync(&counterEnabled); s.sync(&counter); s.sync(&irqAsserted)
        if s.isReading { for c in 0..<0x0D { apply(UInt8(c)) } }
    }
}
