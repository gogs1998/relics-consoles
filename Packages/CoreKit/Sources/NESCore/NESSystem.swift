import CoreKit
import Foundation

/// The console: a 6502 (2A03, no decimal mode) wired to the PPU, APU, controllers and cartridge.
///
/// Every CPU bus access advances the rest of the machine by one CPU cycle (three PPU dots),
/// so timing falls out of the instruction's real access pattern, dummy reads included.
public final class NESSystem: EmulatorCore {
    public let system: SystemID = .nes
    public let videoSize = VideoSize(width: PPU.width, height: PPU.height)
    public let pixelAspect = 8.0 / 7.0
    public let frameRate = 1_789_773.0 / 29_780.5
    public let audioSampleRate = 48_000.0
    public let stateVersion: UInt32 = 1

    let cart: Cartridge
    let mapper: Mapper
    let ppu = PPU()
    let apu = APU()
    let ram: UnsafeMutablePointer<UInt8>

    // CPU registers
    var a: UInt8 = 0
    var x: UInt8 = 0
    var y: UInt8 = 0
    var s: UInt8 = 0xFD
    var pc: UInt16 = 0
    var fC = false, fZ = false, fI = true, fD = false, fV = false, fN = false

    var cycles: UInt64 = 0
    var nmiPending = false
    var prevNMILine = false
    var jammed = false

    // controllers
    var padState: UInt8 = 0
    var padShift: UInt8 = 0
    var padStrobe = false
    var openBus: UInt8 = 0

    public init(rom: Data, battery: Data?) throws {
        cart = try Cartridge(rom: rom)
        mapper = try Mapper.make(for: cart)
        ram = .allocate(capacity: 0x800)
        ram.initialize(repeating: 0, count: 0x800)
        if let battery, cart.hasBattery {
            battery.withUnsafeBytes { raw in
                let n = min(raw.count, cart.prgRAMSize)
                if n > 0 { cart.prgRAM.update(from: raw.bindMemory(to: UInt8.self).baseAddress!, count: n) }
            }
        }
        ppu.cart = cart
        ppu.mapper = mapper
        apu.dmcRead = { [unowned self] addr in self.peek(addr) }
        reset()
    }

    deinit { ram.deallocate() }

    public var romCRC: UInt32 { cart.crc }

    public func reset() {
        apu.reset()
        ppu.reset()
        s = s &- 3
        fI = true
        jammed = false
        pc = UInt16(peek(0xFFFC)) | (UInt16(peek(0xFFFD)) << 8)
        cycles = 7
    }

    // MARK: EmulatorCore

    public var framebuffer: UnsafeBufferPointer<UInt32> {
        UnsafeBufferPointer(start: ppu.pixels, count: PPU.width * PPU.height)
    }

    public func runFrame(input: InputState) {
        let i = input.sanitised
        var p: UInt8 = 0
        if i.contains(.a) { p |= 0x01 }
        if i.contains(.b) { p |= 0x02 }
        if i.contains(.select) { p |= 0x04 }
        if i.contains(.start) { p |= 0x08 }
        if i.contains(.up) { p |= 0x10 }
        if i.contains(.down) { p |= 0x20 }
        if i.contains(.left) { p |= 0x40 }
        if i.contains(.right) { p |= 0x80 }
        padState = p
        ppu.frameComplete = false
        var guardCycles = 0
        while !ppu.frameComplete && guardCycles < 40_000 {
            let before = cycles
            stepInstruction()
            guardCycles += Int(cycles &- before)
        }
    }

    public func drainAudio(into ring: AudioRing) {
        apu.decimator.drain(into: ring)
    }

    public func discardAudio() { apu.decimator.discard() }

    public var batteryRAM: Data? {
        cart.hasBattery ? Data(bytes: cart.prgRAM, count: cart.prgRAMSize) : nil
    }

    public func saveState() -> Data {
        var st = StateCoder.writer()
        sync(&st)
        return st.result
    }

    public func loadState(_ data: Data) throws {
        // Validate on a dry run first so a bad state can't leave the machine half-loaded.
        let backup = saveState()
        var st = StateCoder.reader(data)
        sync(&st)
        if let failure = st.failed {
            var restore = StateCoder.reader(backup)
            sync(&restore)
            throw CoreError.stateMismatch(failure)
        }
    }

    private func sync(_ st: inout StateCoder) {
        st.section("CPU ")
        st.sync(&a); st.sync(&x); st.sync(&y); st.sync(&s); st.sync(&pc)
        st.sync(&fC); st.sync(&fZ); st.sync(&fI); st.sync(&fD); st.sync(&fV); st.sync(&fN)
        st.sync(&cycles); st.sync(&nmiPending); st.sync(&prevNMILine); st.sync(&jammed)
        st.sync(&padShift); st.sync(&padStrobe); st.sync(&openBus)
        st.bytes(ram, count: 0x800)
        cart.sync(&st)
        mapper.sync(&st)
        ppu.sync(&st)
        apu.sync(&st)
    }

    // MARK: bus

    /// One CPU cycle of everything else.
    @inline(__always)
    private func tick() {
        ppu.step(); ppu.step(); ppu.step()
        if ppu.nmiLine && !prevNMILine { nmiPending = true }
        prevNMILine = ppu.nmiLine
        apu.step()
        cycles &+= 1
    }

    @inline(__always)
    func read(_ addr: UInt16) -> UInt8 {
        if apu.cpuStall > 0 {
            let n = apu.cpuStall
            apu.cpuStall = 0
            for _ in 0..<n { tick() }
        }
        tick()
        let v = busRead(addr)
        openBus = v
        return v
    }

    @inline(__always)
    func write(_ addr: UInt16, _ value: UInt8) {
        tick()
        openBus = value
        busWrite(addr, value)
    }

    /// A read without side effects on the clock (DMC fetches, reset vector).
    func peek(_ addr: UInt16) -> UInt8 {
        switch addr {
        case 0x0000..<0x2000: return ram[Int(addr & 0x7FF)]
        case 0x6000..<0x8000: return cart.prgRAMEnabled ? cart.prgRAM[Int(addr & 0x1FFF)] : openBus
        case 0x8000...0xFFFF: return cart.readPRG(addr)
        default: return openBus
        }
    }

    @inline(__always)
    private func busRead(_ addr: UInt16) -> UInt8 {
        if addr < 0x2000 { return ram[Int(addr & 0x7FF)] }
        if addr >= 0x8000 { return cart.readPRG(addr) }
        if addr < 0x4000 { return ppu.readRegister(addr) }
        if addr >= 0x6000 { return cart.prgRAMEnabled ? cart.prgRAM[Int(addr & 0x1FFF)] : openBus }
        switch addr {
        case 0x4015:
            return apu.readStatus() | (openBus & 0x20)
        case 0x4016:
            let bit: UInt8
            if padStrobe {
                bit = padState & 1
            } else {
                bit = padShift & 1
                padShift = (padShift >> 1) | 0x80
            }
            return (openBus & 0xE0) | bit
        case 0x4017:
            return (openBus & 0xE0)
        default:
            return openBus
        }
    }

    @inline(__always)
    private func busWrite(_ addr: UInt16, _ value: UInt8) {
        if addr < 0x2000 { ram[Int(addr & 0x7FF)] = value; return }
        if addr < 0x4000 { ppu.writeRegister(addr, value); return }
        if addr >= 0x8000 { mapper.write(addr, value, cycle: cycles); return }
        if addr >= 0x6000 {
            if cart.prgRAMEnabled && cart.prgRAMWritable { cart.prgRAM[Int(addr & 0x1FFF)] = value }
            return
        }
        switch addr {
        case 0x4014:
            oamDMA(page: value)
        case 0x4016:
            let newStrobe = (value & 1) != 0
            if padStrobe && !newStrobe { padShift = padState }
            padStrobe = newStrobe
            if padStrobe { padShift = padState }
        case 0x4000...0x4013, 0x4015, 0x4017:
            apu.writeRegister(addr, value)
        default:
            break
        }
    }

    private func oamDMA(page: UInt8) {
        tick()                              // halt cycle
        if (cycles & 1) != 0 { tick() }     // alignment
        let base = UInt16(page) << 8
        for i in 0..<256 {
            let v = read(base | UInt16(i))
            tick()
            ppu.oam[Int(ppu.oamAddr &+ UInt8(i))] = v
        }
    }

    // MARK: flags and stack

    @inline(__always) private func setZN(_ v: UInt8) { fZ = v == 0; fN = (v & 0x80) != 0 }

    @inline(__always)
    private func packFlags(brk: Bool) -> UInt8 {
        var p: UInt8 = 0x20
        if fC { p |= 0x01 }
        if fZ { p |= 0x02 }
        if fI { p |= 0x04 }
        if fD { p |= 0x08 }
        if brk { p |= 0x10 }
        if fV { p |= 0x40 }
        if fN { p |= 0x80 }
        return p
    }

    @inline(__always)
    private func unpackFlags(_ p: UInt8) {
        fC = (p & 0x01) != 0; fZ = (p & 0x02) != 0; fI = (p & 0x04) != 0
        fD = (p & 0x08) != 0; fV = (p & 0x40) != 0; fN = (p & 0x80) != 0
    }

    @inline(__always) private func push(_ v: UInt8) { write(0x0100 | UInt16(s), v); s &-= 1 }
    @inline(__always) private func pull() -> UInt8 { s &+= 1; return read(0x0100 | UInt16(s)) }

    // MARK: addressing (each performs the real reads, including dummy ones)

    @inline(__always) private func fetch() -> UInt8 { let v = read(pc); pc &+= 1; return v }
    @inline(__always) private func fetch16() -> UInt16 { let lo = UInt16(fetch()); return lo | (UInt16(fetch()) << 8) }

    @inline(__always) private func zp() -> UInt16 { UInt16(fetch()) }
    @inline(__always) private func zpx() -> UInt16 { let b = fetch(); _ = read(UInt16(b)); return UInt16(b &+ x) }
    @inline(__always) private func zpy() -> UInt16 { let b = fetch(); _ = read(UInt16(b)); return UInt16(b &+ y) }
    @inline(__always) private func abs() -> UInt16 { fetch16() }

    @inline(__always)
    private func absIndexed(_ index: UInt8, alwaysDummy: Bool) -> UInt16 {
        let base = fetch16()
        let addr = base &+ UInt16(index)
        if alwaysDummy || (base & 0xFF00) != (addr & 0xFF00) {
            _ = read((base & 0xFF00) | (addr & 0x00FF))
        }
        return addr
    }

    @inline(__always)
    private func izx() -> UInt16 {
        let p = fetch()
        _ = read(UInt16(p))
        let q = p &+ x
        return UInt16(read(UInt16(q))) | (UInt16(read(UInt16(q &+ 1))) << 8)
    }

    @inline(__always)
    private func izy(alwaysDummy: Bool) -> UInt16 {
        let p = fetch()
        let base = UInt16(read(UInt16(p))) | (UInt16(read(UInt16(p &+ 1))) << 8)
        let addr = base &+ UInt16(y)
        if alwaysDummy || (base & 0xFF00) != (addr & 0xFF00) {
            _ = read((base & 0xFF00) | (addr & 0x00FF))
        }
        return addr
    }

    // MARK: operations

    @inline(__always) private func lda(_ v: UInt8) { a = v; setZN(v) }
    @inline(__always) private func ldx(_ v: UInt8) { x = v; setZN(v) }
    @inline(__always) private func ldy(_ v: UInt8) { y = v; setZN(v) }
    @inline(__always) private func ora(_ v: UInt8) { a |= v; setZN(a) }
    @inline(__always) private func and(_ v: UInt8) { a &= v; setZN(a) }
    @inline(__always) private func eor(_ v: UInt8) { a ^= v; setZN(a) }

    @inline(__always)
    private func adc(_ v: UInt8) {
        let sum = UInt16(a) + UInt16(v) + (fC ? 1 : 0)
        let r = UInt8(truncatingIfNeeded: sum)
        fV = ((a ^ r) & (v ^ r) & 0x80) != 0
        fC = sum > 0xFF
        a = r
        setZN(r)
    }

    @inline(__always) private func sbc(_ v: UInt8) { adc(~v) }

    @inline(__always)
    private func compare(_ reg: UInt8, _ v: UInt8) {
        let r = reg &- v
        fC = reg >= v
        setZN(r)
    }

    @inline(__always)
    private func bit(_ v: UInt8) {
        fZ = (a & v) == 0
        fV = (v & 0x40) != 0
        fN = (v & 0x80) != 0
    }

    @inline(__always) private func asl(_ v: UInt8) -> UInt8 { fC = (v & 0x80) != 0; let r = v << 1; setZN(r); return r }
    @inline(__always) private func lsr(_ v: UInt8) -> UInt8 { fC = (v & 1) != 0; let r = v >> 1; setZN(r); return r }
    @inline(__always) private func rol(_ v: UInt8) -> UInt8 {
        let r = (v << 1) | (fC ? 1 : 0); fC = (v & 0x80) != 0; setZN(r); return r
    }
    @inline(__always) private func ror(_ v: UInt8) -> UInt8 {
        let r = (v >> 1) | (fC ? 0x80 : 0); fC = (v & 1) != 0; setZN(r); return r
    }
    @inline(__always) private func inc(_ v: UInt8) -> UInt8 { let r = v &+ 1; setZN(r); return r }
    @inline(__always) private func dec(_ v: UInt8) -> UInt8 { let r = v &- 1; setZN(r); return r }

    /// Read-modify-write: read, write the old value back (a real 6502 does), write the new one.
    @inline(__always)
    private func rmw(_ addr: UInt16, _ op: (UInt8) -> UInt8) {
        let v = read(addr)
        write(addr, v)
        write(addr, op(v))
    }

    @inline(__always)
    private func branch(_ taken: Bool) {
        let offset = Int8(bitPattern: fetch())
        guard taken else { return }
        _ = read(pc)
        let target = UInt16(bitPattern: Int16(bitPattern: pc) &+ Int16(offset))
        if (target & 0xFF00) != (pc & 0xFF00) {
            _ = read((pc & 0xFF00) | (target & 0x00FF))
        }
        pc = target
    }

    private func interrupt(vector: UInt16, brk: Bool) {
        push(UInt8(pc >> 8))
        push(UInt8(pc & 0xFF))
        push(packFlags(brk: brk))
        fI = true
        // An NMI arriving during an IRQ/BRK sequence hijacks the vector.
        var vec = vector
        if vector != 0xFFFA && nmiPending {
            nmiPending = false
            vec = 0xFFFA
        }
        let lo = UInt16(read(vec))
        pc = lo | (UInt16(read(vec + 1)) << 8)
    }

    // MARK: the instruction loop

    func stepInstruction() {
        if jammed { tick(); return }
        let iBefore = fI
        let op = fetch()
        execute(op)
        // Interrupt polling. CLI, SEI and PLP change I one instruction "late".
        let iForPoll = (op == 0x58 || op == 0x78 || op == 0x28) ? iBefore : fI
        if nmiPending {
            nmiPending = false
            _ = read(pc); _ = read(pc)
            interrupt(vector: 0xFFFA, brk: false)
        } else if !iForPoll && (apu.irqLine || mapper.irqAsserted) {
            _ = read(pc); _ = read(pc)
            interrupt(vector: 0xFFFE, brk: false)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    @inline(__always)
    private func execute(_ op: UInt8) {
        switch op {
        // ---- loads
        case 0xA9: lda(fetch())
        case 0xA5: lda(read(zp()))
        case 0xB5: lda(read(zpx()))
        case 0xAD: lda(read(abs()))
        case 0xBD: lda(read(absIndexed(x, alwaysDummy: false)))
        case 0xB9: lda(read(absIndexed(y, alwaysDummy: false)))
        case 0xA1: lda(read(izx()))
        case 0xB1: lda(read(izy(alwaysDummy: false)))
        case 0xA2: ldx(fetch())
        case 0xA6: ldx(read(zp()))
        case 0xB6: ldx(read(zpy()))
        case 0xAE: ldx(read(abs()))
        case 0xBE: ldx(read(absIndexed(y, alwaysDummy: false)))
        case 0xA0: ldy(fetch())
        case 0xA4: ldy(read(zp()))
        case 0xB4: ldy(read(zpx()))
        case 0xAC: ldy(read(abs()))
        case 0xBC: ldy(read(absIndexed(x, alwaysDummy: false)))
        // ---- stores
        case 0x85: write(zp(), a)
        case 0x95: write(zpx(), a)
        case 0x8D: write(abs(), a)
        case 0x9D: write(absIndexed(x, alwaysDummy: true), a)
        case 0x99: write(absIndexed(y, alwaysDummy: true), a)
        case 0x81: write(izx(), a)
        case 0x91: write(izy(alwaysDummy: true), a)
        case 0x86: write(zp(), x)
        case 0x96: write(zpy(), x)
        case 0x8E: write(abs(), x)
        case 0x84: write(zp(), y)
        case 0x94: write(zpx(), y)
        case 0x8C: write(abs(), y)
        // ---- arithmetic and logic
        case 0x69: adc(fetch())
        case 0x65: adc(read(zp()))
        case 0x75: adc(read(zpx()))
        case 0x6D: adc(read(abs()))
        case 0x7D: adc(read(absIndexed(x, alwaysDummy: false)))
        case 0x79: adc(read(absIndexed(y, alwaysDummy: false)))
        case 0x61: adc(read(izx()))
        case 0x71: adc(read(izy(alwaysDummy: false)))
        case 0xE9, 0xEB: sbc(fetch())
        case 0xE5: sbc(read(zp()))
        case 0xF5: sbc(read(zpx()))
        case 0xED: sbc(read(abs()))
        case 0xFD: sbc(read(absIndexed(x, alwaysDummy: false)))
        case 0xF9: sbc(read(absIndexed(y, alwaysDummy: false)))
        case 0xE1: sbc(read(izx()))
        case 0xF1: sbc(read(izy(alwaysDummy: false)))
        case 0x29: and(fetch())
        case 0x25: and(read(zp()))
        case 0x35: and(read(zpx()))
        case 0x2D: and(read(abs()))
        case 0x3D: and(read(absIndexed(x, alwaysDummy: false)))
        case 0x39: and(read(absIndexed(y, alwaysDummy: false)))
        case 0x21: and(read(izx()))
        case 0x31: and(read(izy(alwaysDummy: false)))
        case 0x09: ora(fetch())
        case 0x05: ora(read(zp()))
        case 0x15: ora(read(zpx()))
        case 0x0D: ora(read(abs()))
        case 0x1D: ora(read(absIndexed(x, alwaysDummy: false)))
        case 0x19: ora(read(absIndexed(y, alwaysDummy: false)))
        case 0x01: ora(read(izx()))
        case 0x11: ora(read(izy(alwaysDummy: false)))
        case 0x49: eor(fetch())
        case 0x45: eor(read(zp()))
        case 0x55: eor(read(zpx()))
        case 0x4D: eor(read(abs()))
        case 0x5D: eor(read(absIndexed(x, alwaysDummy: false)))
        case 0x59: eor(read(absIndexed(y, alwaysDummy: false)))
        case 0x41: eor(read(izx()))
        case 0x51: eor(read(izy(alwaysDummy: false)))
        case 0xC9: compare(a, fetch())
        case 0xC5: compare(a, read(zp()))
        case 0xD5: compare(a, read(zpx()))
        case 0xCD: compare(a, read(abs()))
        case 0xDD: compare(a, read(absIndexed(x, alwaysDummy: false)))
        case 0xD9: compare(a, read(absIndexed(y, alwaysDummy: false)))
        case 0xC1: compare(a, read(izx()))
        case 0xD1: compare(a, read(izy(alwaysDummy: false)))
        case 0xE0: compare(x, fetch())
        case 0xE4: compare(x, read(zp()))
        case 0xEC: compare(x, read(abs()))
        case 0xC0: compare(y, fetch())
        case 0xC4: compare(y, read(zp()))
        case 0xCC: compare(y, read(abs()))
        case 0x24: bit(read(zp()))
        case 0x2C: bit(read(abs()))
        // ---- shifts, rotates, inc/dec on memory
        case 0x0A: _ = read(pc); a = asl(a)
        case 0x06: rmw(zp(), asl)
        case 0x16: rmw(zpx(), asl)
        case 0x0E: rmw(abs(), asl)
        case 0x1E: rmw(absIndexed(x, alwaysDummy: true), asl)
        case 0x4A: _ = read(pc); a = lsr(a)
        case 0x46: rmw(zp(), lsr)
        case 0x56: rmw(zpx(), lsr)
        case 0x4E: rmw(abs(), lsr)
        case 0x5E: rmw(absIndexed(x, alwaysDummy: true), lsr)
        case 0x2A: _ = read(pc); a = rol(a)
        case 0x26: rmw(zp(), rol)
        case 0x36: rmw(zpx(), rol)
        case 0x2E: rmw(abs(), rol)
        case 0x3E: rmw(absIndexed(x, alwaysDummy: true), rol)
        case 0x6A: _ = read(pc); a = ror(a)
        case 0x66: rmw(zp(), ror)
        case 0x76: rmw(zpx(), ror)
        case 0x6E: rmw(abs(), ror)
        case 0x7E: rmw(absIndexed(x, alwaysDummy: true), ror)
        case 0xE6: rmw(zp(), inc)
        case 0xF6: rmw(zpx(), inc)
        case 0xEE: rmw(abs(), inc)
        case 0xFE: rmw(absIndexed(x, alwaysDummy: true), inc)
        case 0xC6: rmw(zp(), dec)
        case 0xD6: rmw(zpx(), dec)
        case 0xCE: rmw(abs(), dec)
        case 0xDE: rmw(absIndexed(x, alwaysDummy: true), dec)
        // ---- register ops
        case 0xE8: _ = read(pc); x &+= 1; setZN(x)
        case 0xC8: _ = read(pc); y &+= 1; setZN(y)
        case 0xCA: _ = read(pc); x &-= 1; setZN(x)
        case 0x88: _ = read(pc); y &-= 1; setZN(y)
        case 0xAA: _ = read(pc); x = a; setZN(x)
        case 0xA8: _ = read(pc); y = a; setZN(y)
        case 0x8A: _ = read(pc); a = x; setZN(a)
        case 0x98: _ = read(pc); a = y; setZN(a)
        case 0xBA: _ = read(pc); x = s; setZN(x)
        case 0x9A: _ = read(pc); s = x
        case 0x18: _ = read(pc); fC = false
        case 0x38: _ = read(pc); fC = true
        case 0x58: _ = read(pc); fI = false
        case 0x78: _ = read(pc); fI = true
        case 0xB8: _ = read(pc); fV = false
        case 0xD8: _ = read(pc); fD = false
        case 0xF8: _ = read(pc); fD = true
        case 0xEA, 0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA: _ = read(pc)
        // ---- stack
        case 0x48: _ = read(pc); push(a)
        case 0x08: _ = read(pc); push(packFlags(brk: true))
        case 0x68: _ = read(pc); _ = read(0x0100 | UInt16(s)); a = pull(); setZN(a)
        case 0x28: _ = read(pc); _ = read(0x0100 | UInt16(s)); unpackFlags(pull())
        // ---- jumps and calls
        case 0x4C: pc = fetch16()
        case 0x6C:
            let ptr = fetch16()
            let lo = UInt16(read(ptr))
            let hi = UInt16(read((ptr & 0xFF00) | ((ptr &+ 1) & 0x00FF)))
            pc = lo | (hi << 8)
        case 0x20:
            let lo = UInt16(fetch())
            _ = read(0x0100 | UInt16(s))
            push(UInt8(pc >> 8))
            push(UInt8(pc & 0xFF))
            pc = lo | (UInt16(read(pc)) << 8)
        case 0x60:
            _ = read(pc)
            _ = read(0x0100 | UInt16(s))
            let lo = UInt16(pull())
            pc = lo | (UInt16(pull()) << 8)
            _ = read(pc)
            pc &+= 1
        case 0x40:
            _ = read(pc)
            _ = read(0x0100 | UInt16(s))
            unpackFlags(pull())
            let lo = UInt16(pull())
            pc = lo | (UInt16(pull()) << 8)
        case 0x00:
            _ = fetch()
            interrupt(vector: 0xFFFE, brk: true)
        // ---- branches
        case 0x10: branch(!fN)
        case 0x30: branch(fN)
        case 0x50: branch(!fV)
        case 0x70: branch(fV)
        case 0x90: branch(!fC)
        case 0xB0: branch(fC)
        case 0xD0: branch(!fZ)
        case 0xF0: branch(fZ)
        // ---- unofficial opcodes that real games use
        case 0x80, 0x82, 0x89, 0xC2, 0xE2: _ = fetch()                        // NOP #imm
        case 0x04, 0x44, 0x64: _ = read(zp())                                  // NOP zp
        case 0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4: _ = read(zpx())               // NOP zp,X
        case 0x0C: _ = read(abs())                                             // NOP abs
        case 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC: _ = read(absIndexed(x, alwaysDummy: false))
        case 0xA7: let v = read(zp()); a = v; x = v; setZN(v)                  // LAX
        case 0xB7: let v = read(zpy()); a = v; x = v; setZN(v)
        case 0xAF: let v = read(abs()); a = v; x = v; setZN(v)
        case 0xBF: let v = read(absIndexed(y, alwaysDummy: false)); a = v; x = v; setZN(v)
        case 0xA3: let v = read(izx()); a = v; x = v; setZN(v)
        case 0xB3: let v = read(izy(alwaysDummy: false)); a = v; x = v; setZN(v)
        case 0x87: write(zp(), a & x)                                          // SAX
        case 0x97: write(zpy(), a & x)
        case 0x8F: write(abs(), a & x)
        case 0x83: write(izx(), a & x)
        case 0xC7: rmwDCP(zp())                                                // DCP
        case 0xD7: rmwDCP(zpx())
        case 0xCF: rmwDCP(abs())
        case 0xDF: rmwDCP(absIndexed(x, alwaysDummy: true))
        case 0xDB: rmwDCP(absIndexed(y, alwaysDummy: true))
        case 0xC3: rmwDCP(izx())
        case 0xD3: rmwDCP(izy(alwaysDummy: true))
        case 0xE7: rmwISC(zp())                                                // ISC
        case 0xF7: rmwISC(zpx())
        case 0xEF: rmwISC(abs())
        case 0xFF: rmwISC(absIndexed(x, alwaysDummy: true))
        case 0xFB: rmwISC(absIndexed(y, alwaysDummy: true))
        case 0xE3: rmwISC(izx())
        case 0xF3: rmwISC(izy(alwaysDummy: true))
        case 0x07: rmwSLO(zp())                                                // SLO
        case 0x17: rmwSLO(zpx())
        case 0x0F: rmwSLO(abs())
        case 0x1F: rmwSLO(absIndexed(x, alwaysDummy: true))
        case 0x1B: rmwSLO(absIndexed(y, alwaysDummy: true))
        case 0x03: rmwSLO(izx())
        case 0x13: rmwSLO(izy(alwaysDummy: true))
        case 0x27: rmwRLA(zp())                                                // RLA
        case 0x37: rmwRLA(zpx())
        case 0x2F: rmwRLA(abs())
        case 0x3F: rmwRLA(absIndexed(x, alwaysDummy: true))
        case 0x3B: rmwRLA(absIndexed(y, alwaysDummy: true))
        case 0x23: rmwRLA(izx())
        case 0x33: rmwRLA(izy(alwaysDummy: true))
        case 0x47: rmwSRE(zp())                                                // SRE
        case 0x57: rmwSRE(zpx())
        case 0x4F: rmwSRE(abs())
        case 0x5F: rmwSRE(absIndexed(x, alwaysDummy: true))
        case 0x5B: rmwSRE(absIndexed(y, alwaysDummy: true))
        case 0x43: rmwSRE(izx())
        case 0x53: rmwSRE(izy(alwaysDummy: true))
        case 0x67: rmwRRA(zp())                                                // RRA
        case 0x77: rmwRRA(zpx())
        case 0x6F: rmwRRA(abs())
        case 0x7F: rmwRRA(absIndexed(x, alwaysDummy: true))
        case 0x7B: rmwRRA(absIndexed(y, alwaysDummy: true))
        case 0x63: rmwRRA(izx())
        case 0x73: rmwRRA(izy(alwaysDummy: true))
        case 0x0B, 0x2B: and(fetch()); fC = fN                                  // ANC
        case 0x4B: and(fetch()); a = lsr(a)                                     // ALR
        case 0x6B:                                                              // ARR
            and(fetch())
            a = (a >> 1) | (fC ? 0x80 : 0)
            setZN(a)
            fC = (a & 0x40) != 0
            fV = ((a >> 6) ^ (a >> 5)) & 1 != 0
        case 0xCB:                                                              // AXS
            let v = fetch()
            let ax = a & x
            fC = ax >= v
            x = ax &- v
            setZN(x)
        // ---- the "unstable" stores: value ANDed with (high byte of the base address + 1); on a
        //      page cross that value also replaces the high byte of the target (RP2A03G behaviour).
        case 0x9C: storeH(y, index: x, base: fetch16())                       // SHY abs,X
        case 0x9E: storeH(x, index: y, base: fetch16())                       // SHX abs,Y
        case 0x9F: storeH(a & x, index: y, base: fetch16())                   // SHA abs,Y
        case 0x93:                                                             // SHA (zp),Y
            let p = fetch()
            let base = UInt16(read(UInt16(p))) | (UInt16(read(UInt16(p &+ 1))) << 8)
            storeH(a & x, index: y, base: base)
        case 0x9B:                                                             // TAS abs,Y
            s = a & x
            storeH(s, index: y, base: fetch16())
        case 0xBB:                                                             // LAS abs,Y
            let v = read(absIndexed(y, alwaysDummy: false)) & s
            a = v; x = v; s = v; setZN(v)
        case 0x8B:                                                             // ANE (magic $EE)
            let v = fetch()
            a = (a | 0xEE) & x & v; setZN(a)
        case 0xAB:                                                             // LXA (magic $EE)
            let v = fetch()
            a = (a | 0xEE) & v; x = a; setZN(a)
        default:
            // KIL: freeze, as hardware does.
            jammed = true
        }
    }

    /// SHA/SHX/SHY/TAS store: always a dummy read, then `value & (H + 1)`.
    @inline(__always) private func storeH(_ value: UInt8, index: UInt8, base: UInt16) {
        var addr = base &+ UInt16(index)
        _ = read((base & 0xFF00) | (addr & 0x00FF))
        let v = value & (UInt8(base >> 8) &+ 1)
        if (base & 0xFF00) != (addr & 0xFF00) { addr = (UInt16(v) << 8) | (addr & 0x00FF) }
        write(addr, v)
    }

    @inline(__always) private func rmwDCP(_ addr: UInt16) {
        let v = read(addr); write(addr, v); let r = v &- 1; write(addr, r); compare(a, r)
    }
    @inline(__always) private func rmwISC(_ addr: UInt16) {
        let v = read(addr); write(addr, v); let r = v &+ 1; write(addr, r); sbc(r)
    }
    @inline(__always) private func rmwSLO(_ addr: UInt16) {
        let v = read(addr); write(addr, v); let r = asl(v); write(addr, r); ora(r)
    }
    @inline(__always) private func rmwRLA(_ addr: UInt16) {
        let v = read(addr); write(addr, v); let r = rol(v); write(addr, r); and(r)
    }
    @inline(__always) private func rmwSRE(_ addr: UInt16) {
        let v = read(addr); write(addr, v); let r = lsr(v); write(addr, r); eor(r)
    }
    @inline(__always) private func rmwRRA(_ addr: UInt16) {
        let v = read(addr); write(addr, v); let r = ror(v); write(addr, r); adc(r)
    }

    // MARK: test hooks

    /// Reads memory as the CPU would, without advancing time. For tests and the debugger.
    public func debugPeek(_ addr: UInt16) -> UInt8 { peek(addr) }
    public var debugPC: UInt16 { pc }
    public var debugCycles: UInt64 { cycles }
    /// Pending audio for tests.
    public var debugPendingAudio: UnsafeBufferPointer<Float> { apu.decimator.pending }
}
