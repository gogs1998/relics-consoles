import CoreKit
import Foundation

/// The Game Boy / Game Boy Color: an SM83 CPU wired to the PPU, APU, timer, joypad and cartridge.
///
/// Every CPU memory access (and every internal delay cycle) advances the rest of the machine by
/// one M-cycle, so instruction timing falls out of each instruction's real access pattern.
/// There is no boot ROM: the machine starts in the documented post-boot state at $0100.
/// CGB mode is used when the cartridge header says the game supports it (bit 7 of $0143).
public final class GBSystem: EmulatorCore {
    public let system: SystemID
    public let videoSize = VideoSize(width: PPU.width, height: PPU.height)
    public let pixelAspect = 1.0
    public let frameRate = 4_194_304.0 / 70_224.0
    public let audioSampleRate = 48_000.0
    public let stateVersion: UInt32 = 1

    let cart: Cartridge
    let ppu: PPU
    let apu = APU()
    let cgb: Bool
    let wram: UnsafeMutablePointer<UInt8>   // 32 KB (8 banks on CGB, 2 used on DMG)
    let hram: UnsafeMutablePointer<UInt8>   // 127 bytes

    // CPU registers
    var a: UInt8 = 0, f: UInt8 = 0, b: UInt8 = 0, c: UInt8 = 0
    var d: UInt8 = 0, e: UInt8 = 0, h: UInt8 = 0, l: UInt8 = 0
    var sp: UInt16 = 0, pc: UInt16 = 0
    var ime = false
    var imeEnableAfterThis = false   // EI takes effect after the following instruction
    var eiPending = false
    var halted = false
    var haltBug = false
    /// True while executing the instruction after EI (IME turns on at its end).
    var imeTurningOn = false
    var stopped = false
    var locked = false               // an illegal opcode hangs the CPU
    var cycles: UInt64 = 0           // M-cycles since power on

    // interrupts
    var ifReg: UInt8 = 0
    var ie: UInt8 = 0

    // timer
    var sysCounter: UInt16 = 0       // DIV is the top 8 bits
    var tima: UInt8 = 0, tma: UInt8 = 0, tac: UInt8 = 0
    var timaReload = false
    var timerMask: UInt16 = 0        // the DIV-counter bit whose falling edge clocks TIMA (0 = off)
    var fsMask: UInt16 = 1 << 12     // the bit whose falling edge clocks the APU frame sequencer

    // speed
    var doubleSpeed = false
    var speedPrepare = false
    var dotsPerM = 4

    // joypad, serial
    var padState: UInt8 = 0          // bit 0-3 A B Select Start, bit 4-7 Right Left Up Down (1 = pressed)
    var p1Select: UInt8 = 0x30
    var sb: UInt8 = 0, sc: UInt8 = 0
    /// Bytes sent out of the serial port (test ROMs print results there). Not part of save states.
    public internal(set) var serialLog: [UInt8] = []

    // memory banking
    var wramOff = 0x1000
    var svbk: UInt8 = 1

    // OAM DMA
    var dmaActive = false
    var dmaSource: UInt16 = 0
    var dmaIndex = 0
    var dmaReg: UInt8 = 0xFF
    /// M-cycles until a newly written DMA starts copying (a running one keeps going meanwhile).
    var dmaStartDelay = 0
    var dmaLastByte: UInt8 = 0xFF
    var dmaPendingSource: UInt16 = 0

    // CGB HDMA
    var hdmaSrc: UInt16 = 0
    var hdmaDst: UInt16 = 0
    var hdmaLen: UInt8 = 0x7F
    var hdmaActive = false
    var hdmaBlockPending = false

    static let fZ: UInt8 = 0x80, fN: UInt8 = 0x40, fH: UInt8 = 0x20, fC: UInt8 = 0x10

    public init(rom: Data, battery: Data?) throws {
        cart = try Cartridge(rom: rom)
        cgb = cart.isCGB
        system = cgb ? .gbc : .gb
        ppu = PPU(cgb: cgb)
        wram = .allocate(capacity: 0x8000)
        wram.initialize(repeating: 0, count: 0x8000)
        hram = .allocate(capacity: 0x7F)
        hram.initialize(repeating: 0, count: 0x7F)
        if let battery, cart.hasBattery { cart.loadBattery(battery) }
        reset()
    }

    deinit {
        wram.deallocate()
        hram.deallocate()
    }

    public var romCRC: UInt32 { cart.crc }

    public func reset() {
        cart.reset()
        ppu.reset()
        apu.reset()
        wram.update(repeating: 0, count: 0x8000)
        hram.update(repeating: 0, count: 0x7F)
        if cgb {
            a = 0x11; f = 0x80; b = 0x00; c = 0x00; d = 0xFF; e = 0x56; h = 0x00; l = 0x0D
        } else {
            a = 0x01; f = 0xB0; b = 0x00; c = 0x13; d = 0x00; e = 0xD8; h = 0x01; l = 0x4D
        }
        sp = 0xFFFE; pc = 0x0100
        ime = false; imeEnableAfterThis = false; eiPending = false
        halted = false; haltBug = false; stopped = false; locked = false
        cycles = 0
        ifReg = 0xE1 & 0x1F; ie = 0
        sysCounter = cgb ? 0x1EA0 : 0xABCC
        tima = 0; tma = 0; tac = 0xF8
        timaReload = false
        doubleSpeed = false; speedPrepare = false
        p1Select = 0x30; sb = 0; sc = 0x7E
        svbk = 1; wramOff = 0x1000
        dmaActive = false; dmaSource = 0; dmaIndex = 0; dmaReg = 0xFF; dmaStartDelay = 0
        hdmaSrc = 0; hdmaDst = 0; hdmaLen = 0x7F; hdmaActive = false; hdmaBlockPending = false
        ppu.lcdc = 0x91
        ppu.statSel = 0
        ppu.bgp = 0xFC
        refreshDerived()
    }

    private func refreshDerived() {
        dotsPerM = doubleSpeed ? 2 : 4
        fsMask = doubleSpeed ? 1 << 13 : 1 << 12
        timerMask = timerBit()
    }

    private func timerBit() -> UInt16 {
        guard (tac & 4) != 0 else { return 0 }
        switch tac & 3 {
        case 0: return 1 << 9
        case 1: return 1 << 3
        case 2: return 1 << 5
        default: return 1 << 7
        }
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
        if i.contains(.right) { p |= 0x10 }
        if i.contains(.left) { p |= 0x20 }
        if i.contains(.up) { p |= 0x40 }
        if i.contains(.down) { p |= 0x80 }
        if (p & ~padState) != 0 {
            ifReg |= 0x10
            stopped = false
        }
        padState = p
        ppu.frameComplete = false
        // A frame normally ends at line 144. With the LCD being switched on and off the frame
        // boundary moves, so never run much more than one frame's worth of cycles.
        let start = cycles
        let limit: UInt64 = doubleSpeed ? 35_112 + 600 : 17_556 + 300
        while !ppu.frameComplete && cycles &- start < limit {
            step()
        }
        // The MBC3 clock runs from its own crystal: count real time, not CPU speed.
        let m = Int(cycles &- start)
        cart.tickRTC(units: doubleSpeed ? m : m * 2)
    }

    public func drainAudio(into ring: AudioRing) {
        apu.decimator.drain(into: ring)
    }

    public func discardAudio() { apu.decimator.discard() }

    public var batteryRAM: Data? {
        cart.batteryData()
    }

    public func saveState() -> Data {
        var st = StateCoder.writer()
        sync(&st)
        return st.result
    }

    public func loadState(_ data: Data) throws {
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
        st.section("GBCP")
        var mode: UInt8 = cgb ? 1 : 0
        st.sync(&mode)
        if st.isReading && mode != (cgb ? 1 : 0) { st.section("MODE") }  // forces a mismatch failure
        st.sync(&a); st.sync(&f); st.sync(&b); st.sync(&c); st.sync(&d); st.sync(&e); st.sync(&h); st.sync(&l)
        st.sync(&sp); st.sync(&pc)
        st.sync(&ime); st.sync(&imeEnableAfterThis); st.sync(&eiPending)
        st.sync(&halted); st.sync(&haltBug); st.sync(&stopped); st.sync(&locked); st.sync(&cycles)
        st.sync(&ifReg); st.sync(&ie)
        st.sync(&sysCounter); st.sync(&tima); st.sync(&tma); st.sync(&tac); st.sync(&timaReload)
        st.sync(&doubleSpeed); st.sync(&speedPrepare)
        st.sync(&padState); st.sync(&p1Select); st.sync(&sb); st.sync(&sc)
        st.sync(&svbk); st.sync(&wramOff)
        st.sync(&dmaActive); st.sync(&dmaSource); st.sync(&dmaIndex); st.sync(&dmaReg)
        st.sync(&dmaStartDelay); st.sync(&dmaPendingSource); st.sync(&dmaLastByte)
        st.sync(&hdmaSrc); st.sync(&hdmaDst); st.sync(&hdmaLen); st.sync(&hdmaActive); st.sync(&hdmaBlockPending)
        st.bytes(wram, count: 0x8000)
        st.bytes(hram, count: 0x7F)
        cart.sync(&st)
        ppu.sync(&st)
        apu.sync(&st)
        if st.isReading {
            refreshDerived()
            apu.decimator.setInputRate(1_048_576)
        }
    }

    // MARK: clock

    /// One M-cycle of everything except the CPU.
    @inline(__always)
    private func tick() {
        cycles &+= 1
        // timer
        let old = sysCounter
        sysCounter &+= 4
        if timaReload {
            timaReload = false
            tima = tma
            ifReg |= 0x04
        }
        let fell = old & ~sysCounter
        if (fell & (timerMask | fsMask)) != 0 { counterEdges(fell) }
        // video
        ppu.dot &+= dotsPerM
        if ppu.dot >= ppu.nextEvent {
            ifReg |= ppu.runEvents()
            if ppu.hblankStarted {
                ppu.hblankStarted = false
                if hdmaActive && ppu.ly < 144 { hdmaBlockPending = true }
            }
        }
        // sound
        apu.step(dotsPerM)
        // OAM DMA: one byte per M-cycle
        if dmaActive {
            dmaLastByte = busRead(dmaSource &+ UInt16(dmaIndex))
            ppu.oam[dmaIndex] = dmaLastByte
            dmaIndex += 1
            if dmaIndex >= 0xA0 { dmaActive = false }
        }
        if dmaStartDelay > 0 {
            dmaStartDelay -= 1
            if dmaStartDelay == 0 {
                dmaSource = dmaPendingSource
                dmaIndex = 0
                dmaActive = true
            }
        }
    }

    private func counterEdges(_ fell: UInt16) {
        if (fell & timerMask) != 0 { incrementTIMA() }
        if (fell & fsMask) != 0 { apu.frameSequencer() }
    }

    private func incrementTIMA() {
        if tima == 0xFF {
            tima = 0
            timaReload = true
        } else {
            tima &+= 1
        }
    }

    // MARK: bus

    @inline(__always)
    private func read(_ addr: UInt16) -> UInt8 {
        tick()
        // While OAM DMA owns the bus, the CPU only reaches I/O and high RAM.
        if dmaActive && addr < 0xFF00 {
            if addr >= 0xFE00 { return 0xFF }
            // Same bus as the DMA source: the CPU sees the byte being copied; other bus: normal.
            let cpuVideo = addr >= 0x8000 && addr < 0xA000
            let dmaVideo = dmaSource >= 0x8000 && dmaSource < 0xA000
            if cpuVideo == dmaVideo { return dmaLastByte }
            return busRead(addr)
        }
        return busRead(addr)
    }

    @inline(__always)
    private func write(_ addr: UInt16, _ v: UInt8) {
        tick()
        busWrite(addr, v)
    }

    @inline(__always)
    private func busRead(_ addr: UInt16) -> UInt8 {
        let a = Int(addr)
        if a < 0x4000 { return cart.rom[cart.lo + a] }
        if a < 0x8000 { return cart.rom[cart.hi + a - 0x4000] }
        if a < 0xA000 { return ppu.vram[ppu.vramBankOff + a - 0x8000] }
        if a < 0xC000 { return cart.readRAM(addr) }
        if a < 0xD000 { return wram[a - 0xC000] }
        if a < 0xE000 { return wram[wramOff + a - 0xD000] }
        if a < 0xF000 { return wram[a - 0xE000] }
        if a < 0xFE00 { return wram[wramOff + a - 0xF000] }
        if a < 0xFEA0 { return ppu.oam[a - 0xFE00] }
        if a < 0xFF00 { return cgb ? 0x00 : 0xFF }
        if a >= 0xFF80 { return a == 0xFFFF ? ie : hram[a - 0xFF80] }
        return readIO(a)
    }

    @inline(__always)
    private func busWrite(_ addr: UInt16, _ v: UInt8) {
        let a = Int(addr)
        if a < 0x8000 { cart.writeROM(addr, v); return }
        if a < 0xA000 { ppu.vram[ppu.vramBankOff + a - 0x8000] = v; return }
        if a < 0xC000 { cart.writeRAM(addr, v); return }
        if a < 0xD000 { wram[a - 0xC000] = v; return }
        if a < 0xE000 { wram[wramOff + a - 0xD000] = v; return }
        if a < 0xF000 { wram[a - 0xE000] = v; return }
        if a < 0xFE00 { wram[wramOff + a - 0xF000] = v; return }
        if a < 0xFEA0 { ppu.oam[a - 0xFE00] = v; return }
        if a < 0xFF00 { return }
        if a >= 0xFF80 {
            if a == 0xFFFF { ie = v } else { hram[a - 0xFF80] = v }
            return
        }
        writeIO(a, v)
    }

    private func readIO(_ a: Int) -> UInt8 {
        switch a {
        case 0xFF00:
            var r: UInt8 = 0xC0 | p1Select | 0x0F
            if (p1Select & 0x10) == 0 { r &= ~(padState >> 4) }
            if (p1Select & 0x20) == 0 { r &= ~(padState & 0x0F) }
            return r
        case 0xFF01: return sb
        case 0xFF02: return sc | (cgb ? 0x7C : 0x7E)
        case 0xFF04: return UInt8(sysCounter >> 8)
        case 0xFF05: return tima
        case 0xFF06: return tma
        case 0xFF07: return tac | 0xF8
        case 0xFF0F: return ifReg | 0xE0
        case 0xFF10...0xFF3F: return apu.read(UInt16(a))
        case 0xFF40: return ppu.lcdc
        case 0xFF41: return ppu.statValue
        case 0xFF42: return ppu.scy
        case 0xFF43: return ppu.scx
        case 0xFF44: return ppu.ly
        case 0xFF45: return ppu.lyc
        case 0xFF46: return dmaReg
        case 0xFF47: return ppu.bgp
        case 0xFF48: return ppu.obp0
        case 0xFF49: return ppu.obp1
        case 0xFF4A: return ppu.wy
        case 0xFF4B: return ppu.wx
        default: break
        }
        guard cgb else { return 0xFF }
        switch a {
        case 0xFF4D: return (doubleSpeed ? 0x80 : 0) | 0x7E | (speedPrepare ? 1 : 0)
        case 0xFF4F: return 0xFE | UInt8(ppu.vramBankOff >> 13)
        case 0xFF55: return hdmaActive ? hdmaLen : (0x80 | hdmaLen)
        case 0xFF68: return ppu.bcps | 0x40
        case 0xFF69: return ppu.bgPal[Int(ppu.bcps & 0x3F)]
        case 0xFF6A: return ppu.ocps | 0x40
        case 0xFF6B: return ppu.objPal[Int(ppu.ocps & 0x3F)]
        case 0xFF70: return svbk | 0xF8
        default: return 0xFF
        }
    }

    private func writeIO(_ a: Int, _ v: UInt8) {
        switch a {
        case 0xFF00: p1Select = v & 0x30
        case 0xFF01: sb = v
        case 0xFF02:
            sc = v
            // No link partner: an internally clocked transfer completes at once and reads $FF.
            if (v & 0x81) == 0x81 {
                if serialLog.count < 4096 { serialLog.append(sb) }   // test ROMs report here
                sb = 0xFF
                sc &= 0x7F
                ifReg |= 0x08
            }
        case 0xFF04:
            let old = sysCounter
            sysCounter = 0
            if (old & (timerMask | fsMask)) != 0 { counterEdges(old) }
        case 0xFF05:
            tima = v
            timaReload = false
        case 0xFF06: tma = v
        case 0xFF07:
            let oldSignal = (sysCounter & timerMask) != 0
            tac = v & 7
            timerMask = timerBit()
            if oldSignal && (sysCounter & timerMask) == 0 { incrementTIMA() }
        case 0xFF0F: ifReg = v & 0x1F
        case 0xFF10...0xFF3F: apu.write(UInt16(a), v)
        case 0xFF40: ifReg |= ppu.writeLCDC(v)
        case 0xFF41: ppu.statSel = v & 0x78; ifReg |= ppu.updateStat()
        case 0xFF42: ppu.scy = v
        case 0xFF43: ppu.scx = v
        case 0xFF45: ppu.lyc = v; ifReg |= ppu.updateStat()
        case 0xFF46:
            dmaReg = v
            var src = UInt16(v) << 8
            if src >= 0xE000 { src &-= 0x2000 }
            dmaPendingSource = src
            dmaStartDelay = 2
        case 0xFF47: ppu.bgp = v
        case 0xFF48: ppu.obp0 = v
        case 0xFF49: ppu.obp1 = v
        case 0xFF4A: ppu.wy = v
        case 0xFF4B: ppu.wx = v
        default:
            guard cgb else { return }
            switch a {
            case 0xFF4D: speedPrepare = (v & 1) != 0
            case 0xFF4F: ppu.vramBankOff = Int(v & 1) << 13
            case 0xFF51: hdmaSrc = (hdmaSrc & 0x00FF) | (UInt16(v) << 8)
            case 0xFF52: hdmaSrc = (hdmaSrc & 0xFF00) | UInt16(v & 0xF0)
            case 0xFF53: hdmaDst = (hdmaDst & 0x00FF) | (UInt16(v & 0x1F) << 8)
            case 0xFF54: hdmaDst = (hdmaDst & 0xFF00) | UInt16(v & 0xF0)
            case 0xFF55: startHDMA(v)
            case 0xFF68: ppu.bcps = v & 0xBF
            case 0xFF69: ppu.writeBCPD(v)
            case 0xFF6A: ppu.ocps = v & 0xBF
            case 0xFF6B: ppu.writeOCPD(v)
            case 0xFF70:
                svbk = v & 7
                wramOff = Int(svbk == 0 ? 1 : svbk) * 0x1000
            default: break
            }
        }
    }

    // MARK: CGB VRAM DMA

    private func startHDMA(_ v: UInt8) {
        if hdmaActive && (v & 0x80) == 0 {
            hdmaActive = false        // cancel; $FF55 then reads $80 | remaining
            hdmaBlockPending = false
            return
        }
        hdmaLen = v & 0x7F
        if (v & 0x80) != 0 {
            hdmaActive = true
            if (ppu.lcdc & 0x80) == 0 || ppu.mode == 0 { hdmaBlockPending = true }
        } else {
            // General-purpose DMA: everything now, CPU stalled.
            let blocks = Int(hdmaLen) + 1
            for _ in 0..<blocks { copyHDMABlock() }
            for _ in 0..<(blocks * (doubleSpeed ? 16 : 8)) { tick() }
            hdmaLen = 0x7F
            hdmaActive = false
        }
    }

    private func copyHDMABlock() {
        for _ in 0..<16 {
            ppu.vram[ppu.vramBankOff + Int(hdmaDst & 0x1FFF)] = busRead(hdmaSrc)
            hdmaSrc &+= 1
            hdmaDst = (hdmaDst &+ 1) & 0x1FFF
        }
    }

    private func runHDMABlock() {
        hdmaBlockPending = false
        guard hdmaActive else { return }
        copyHDMABlock()
        for _ in 0..<(doubleSpeed ? 16 : 8) { tick() }
        if hdmaLen == 0 {
            hdmaLen = 0x7F
            hdmaActive = false
        } else {
            hdmaLen &-= 1
        }
    }

    // MARK: registers

    var bc: UInt16 {
        @inline(__always) get { UInt16(b) << 8 | UInt16(c) }
        @inline(__always) set { b = UInt8(newValue >> 8); c = UInt8(truncatingIfNeeded: newValue) }
    }
    var de: UInt16 {
        @inline(__always) get { UInt16(d) << 8 | UInt16(e) }
        @inline(__always) set { d = UInt8(newValue >> 8); e = UInt8(truncatingIfNeeded: newValue) }
    }
    var hl: UInt16 {
        @inline(__always) get { UInt16(h) << 8 | UInt16(l) }
        @inline(__always) set { h = UInt8(newValue >> 8); l = UInt8(truncatingIfNeeded: newValue) }
    }
    var af: UInt16 {
        @inline(__always) get { UInt16(a) << 8 | UInt16(f) }
        @inline(__always) set { a = UInt8(newValue >> 8); f = UInt8(truncatingIfNeeded: newValue) & 0xF0 }
    }

    @inline(__always) private func fetch() -> UInt8 { let v = read(pc); pc &+= 1; return v }
    @inline(__always) private func fetch16() -> UInt16 { let lo = UInt16(fetch()); return lo | UInt16(fetch()) << 8 }

    @inline(__always)
    private func push16(_ v: UInt16) {
        sp &-= 1; write(sp, UInt8(v >> 8))
        sp &-= 1; write(sp, UInt8(truncatingIfNeeded: v))
    }

    @inline(__always)
    private func pop16() -> UInt16 {
        let lo = UInt16(read(sp)); sp &+= 1
        let hi = UInt16(read(sp)); sp &+= 1
        return lo | hi << 8
    }

    @inline(__always)
    private func r8(_ i: UInt8) -> UInt8 {
        switch i {
        case 0: return b
        case 1: return c
        case 2: return d
        case 3: return e
        case 4: return h
        case 5: return l
        case 6: return read(hl)
        default: return a
        }
    }

    @inline(__always)
    private func setR8(_ i: UInt8, _ v: UInt8) {
        switch i {
        case 0: b = v
        case 1: c = v
        case 2: d = v
        case 3: e = v
        case 4: h = v
        case 5: l = v
        case 6: write(hl, v)
        default: a = v
        }
    }

    @inline(__always)
    private func cond(_ op: UInt8) -> Bool {
        switch (op >> 3) & 3 {
        case 0: return (f & GBSystem.fZ) == 0
        case 1: return (f & GBSystem.fZ) != 0
        case 2: return (f & GBSystem.fC) == 0
        default: return (f & GBSystem.fC) != 0
        }
    }

    // MARK: ALU

    @inline(__always)
    private func alu(_ op: UInt8, _ v: UInt8) {
        switch op {
        case 0, 1:
            let cin: UInt8 = op == 1 && (f & GBSystem.fC) != 0 ? 1 : 0
            let r = UInt16(a) + UInt16(v) + UInt16(cin)
            let res = UInt8(truncatingIfNeeded: r)
            var fl: UInt8 = res == 0 ? GBSystem.fZ : 0
            if (a & 0xF) + (v & 0xF) + cin > 0xF { fl |= GBSystem.fH }
            if r > 0xFF { fl |= GBSystem.fC }
            f = fl
            a = res
        case 2, 3, 7:
            let cin: Int = op == 3 && (f & GBSystem.fC) != 0 ? 1 : 0
            let r = Int(a) - Int(v) - cin
            let res = UInt8(truncatingIfNeeded: r)
            var fl: UInt8 = GBSystem.fN | (res == 0 ? GBSystem.fZ : 0)
            if Int(a & 0xF) - Int(v & 0xF) - cin < 0 { fl |= GBSystem.fH }
            if r < 0 { fl |= GBSystem.fC }
            f = fl
            if op != 7 { a = res }
        case 4:
            a &= v; f = GBSystem.fH | (a == 0 ? GBSystem.fZ : 0)
        case 5:
            a ^= v; f = a == 0 ? GBSystem.fZ : 0
        default:
            a |= v; f = a == 0 ? GBSystem.fZ : 0
        }
    }

    @inline(__always)
    private func inc8(_ v: UInt8) -> UInt8 {
        let r = v &+ 1
        f = (f & GBSystem.fC) | (r == 0 ? GBSystem.fZ : 0) | ((v & 0xF) == 0xF ? GBSystem.fH : 0)
        return r
    }

    @inline(__always)
    private func dec8(_ v: UInt8) -> UInt8 {
        let r = v &- 1
        f = (f & GBSystem.fC) | GBSystem.fN | (r == 0 ? GBSystem.fZ : 0) | ((v & 0xF) == 0 ? GBSystem.fH : 0)
        return r
    }

    @inline(__always)
    private func addHL(_ v: UInt16) {
        let x = hl
        let r = UInt32(x) + UInt32(v)
        f = (f & GBSystem.fZ) | ((x & 0xFFF) + (v & 0xFFF) > 0xFFF ? GBSystem.fH : 0) | (r > 0xFFFF ? GBSystem.fC : 0)
        hl = UInt16(truncatingIfNeeded: r)
        tick()
    }

    /// SP + signed immediate, with the flags ADD SP,e and LD HL,SP+e set.
    @inline(__always)
    private func spPlusImm() -> UInt16 {
        let e8 = fetch()
        let u = UInt16(e8)
        f = ((sp & 0xF) + (u & 0xF) > 0xF ? GBSystem.fH : 0) | ((sp & 0xFF) + u > 0xFF ? GBSystem.fC : 0)
        return sp &+ UInt16(bitPattern: Int16(Int8(bitPattern: e8)))
    }

    @inline(__always)
    private func shiftOp(_ op: UInt8, _ v: UInt8) -> UInt8 {
        let cin: UInt8 = (f & GBSystem.fC) != 0 ? 1 : 0
        var r: UInt8
        var carry: UInt8
        switch op {
        case 0: carry = v >> 7; r = (v << 1) | carry                 // RLC
        case 1: carry = v & 1; r = (v >> 1) | (carry << 7)           // RRC
        case 2: carry = v >> 7; r = (v << 1) | cin                   // RL
        case 3: carry = v & 1; r = (v >> 1) | (cin << 7)             // RR
        case 4: carry = v >> 7; r = v << 1                           // SLA
        case 5: carry = v & 1; r = (v >> 1) | (v & 0x80)             // SRA
        case 6: carry = 0; r = (v << 4) | (v >> 4)                   // SWAP
        default: carry = v & 1; r = v >> 1                           // SRL
        }
        f = (r == 0 ? GBSystem.fZ : 0) | (carry != 0 ? GBSystem.fC : 0)
        return r
    }

    private func daa() {
        var v = a
        if (f & GBSystem.fN) == 0 {
            var carry = (f & GBSystem.fC) != 0
            if carry || v > 0x99 { v &+= 0x60; carry = true }
            if (f & GBSystem.fH) != 0 || (v & 0x0F) > 0x09 { v &+= 0x06 }
            f = (carry ? GBSystem.fC : 0)
        } else {
            if (f & GBSystem.fC) != 0 { v &-= 0x60 }
            if (f & GBSystem.fH) != 0 { v &-= 0x06 }
            f = GBSystem.fN | (f & GBSystem.fC)
        }
        a = v
        if v == 0 { f |= GBSystem.fZ }
    }

    // MARK: the instruction loop

    @inline(__always)
    func step() {
        if hdmaBlockPending { runHDMABlock() }
        if halted || stopped || locked {
            if !locked && (ie & ifReg & 0x1F) != 0 && !stopped {
                halted = false
            } else {
                tick()
                return
            }
        }
        if ime && (ie & ifReg & 0x1F) != 0 {
            dispatchInterrupt()
            return
        }
        let enable = imeEnableAfterThis
        imeEnableAfterThis = false
        let op = read(pc)
        if haltBug { haltBug = false } else { pc &+= 1 }
        imeTurningOn = enable && eiPending
        execute(op)
        imeTurningOn = false
        if enable && eiPending { ime = true; eiPending = false }
        if eiPending && !enable { imeEnableAfterThis = true }
    }

    private func dispatchInterrupt() {
        ime = false
        haltBug = false
        tick(); tick()
        sp &-= 1; write(sp, UInt8(pc >> 8))
        let pending = ie & ifReg & 0x1F      // decided after the high byte is pushed
        sp &-= 1; write(sp, UInt8(truncatingIfNeeded: pc))
        if pending == 0 {
            pc = 0
        } else {
            let bit = pending.trailingZeroBitCount
            ifReg &= ~(1 << UInt8(bit))
            pc = 0x40 + UInt16(bit) * 8
        }
        tick()
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    @inline(__always)
    private func execute(_ op: UInt8) {
        switch op {
        case 0x00: break
        case 0x01: bc = fetch16()
        case 0x11: de = fetch16()
        case 0x21: hl = fetch16()
        case 0x31: sp = fetch16()
        case 0x02: write(bc, a)
        case 0x12: write(de, a)
        case 0x22: write(hl, a); hl &+= 1
        case 0x32: write(hl, a); hl &-= 1
        case 0x0A: a = read(bc)
        case 0x1A: a = read(de)
        case 0x2A: a = read(hl); hl &+= 1
        case 0x3A: a = read(hl); hl &-= 1
        case 0x03: bc &+= 1; tick()
        case 0x13: de &+= 1; tick()
        case 0x23: hl &+= 1; tick()
        case 0x33: sp &+= 1; tick()
        case 0x0B: bc &-= 1; tick()
        case 0x1B: de &-= 1; tick()
        case 0x2B: hl &-= 1; tick()
        case 0x3B: sp &-= 1; tick()
        case 0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x3C:
            let r = (op >> 3) & 7; setR8(r, inc8(r8(r)))
        case 0x34:
            let addr = hl; write(addr, inc8(read(addr)))
        case 0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x3D:
            let r = (op >> 3) & 7; setR8(r, dec8(r8(r)))
        case 0x35:
            let addr = hl; write(addr, dec8(read(addr)))
        case 0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E:
            let v = fetch(); setR8((op >> 3) & 7, v)
        case 0x07: a = shiftOp(0, a); f &= GBSystem.fC
        case 0x0F: a = shiftOp(1, a); f &= GBSystem.fC
        case 0x17: a = shiftOp(2, a); f &= GBSystem.fC
        case 0x1F: a = shiftOp(3, a); f &= GBSystem.fC
        case 0x08:
            let addr = fetch16()
            write(addr, UInt8(truncatingIfNeeded: sp))
            write(addr &+ 1, UInt8(sp >> 8))
        case 0x09: addHL(bc)
        case 0x19: addHL(de)
        case 0x29: addHL(hl)
        case 0x39: addHL(sp)
        case 0x10: stop()
        case 0x18:
            let off = Int8(bitPattern: fetch())
            pc = UInt16(bitPattern: Int16(bitPattern: pc) &+ Int16(off)); tick()
        case 0x20, 0x28, 0x30, 0x38:
            let off = Int8(bitPattern: fetch())
            if cond(op) { pc = UInt16(bitPattern: Int16(bitPattern: pc) &+ Int16(off)); tick() }
        case 0x27: daa()
        case 0x2F: a = ~a; f |= GBSystem.fN | GBSystem.fH
        case 0x37: f = (f & GBSystem.fZ) | GBSystem.fC
        case 0x3F: f = (f & (GBSystem.fZ | GBSystem.fC)) ^ GBSystem.fC
        case 0x76: halt()
        case 0x40...0x7F:
            setR8((op >> 3) & 7, r8(op & 7))
        case 0x80...0xBF:
            alu((op >> 3) & 7, r8(op & 7))
        case 0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE:
            alu((op >> 3) & 7, fetch())
        case 0xC0, 0xC8, 0xD0, 0xD8:
            tick()
            if cond(op) { pc = pop16(); tick() }
        case 0xC9: pc = pop16(); tick()
        case 0xD9: pc = pop16(); tick(); ime = true
        case 0xC1: bc = pop16()
        case 0xD1: de = pop16()
        case 0xE1: hl = pop16()
        case 0xF1: af = pop16()
        case 0xC5: tick(); push16(bc)
        case 0xD5: tick(); push16(de)
        case 0xE5: tick(); push16(hl)
        case 0xF5: tick(); push16(af)
        case 0xC3: pc = fetch16(); tick()
        case 0xC2, 0xCA, 0xD2, 0xDA:
            let t = fetch16()
            if cond(op) { pc = t; tick() }
        case 0xE9: pc = hl
        case 0xCD:
            let t = fetch16(); tick(); push16(pc); pc = t
        case 0xC4, 0xCC, 0xD4, 0xDC:
            let t = fetch16()
            if cond(op) { tick(); push16(pc); pc = t }
        case 0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF:
            tick(); push16(pc); pc = UInt16(op & 0x38)
        case 0xCB: executeCB()
        case 0xE0: let n = fetch(); write(0xFF00 | UInt16(n), a)
        case 0xF0: let n = fetch(); a = read(0xFF00 | UInt16(n))
        case 0xE2: write(0xFF00 | UInt16(c), a)
        case 0xF2: a = read(0xFF00 | UInt16(c))
        case 0xEA: write(fetch16(), a)
        case 0xFA: a = read(fetch16())
        case 0xE8: sp = spPlusImm(); tick(); tick()
        case 0xF8: hl = spPlusImm(); tick()
        case 0xF9: sp = hl; tick()
        case 0xF3: ime = false; eiPending = false; imeEnableAfterThis = false
        case 0xFB: if !ime { eiPending = true }
        default:
            locked = true   // D3 DB DD E3 E4 EB EC ED F4 FC FD
        }
    }

    @inline(__always)
    private func executeCB() {
        let op = fetch()
        let r = op & 7
        let bit = (op >> 3) & 7
        switch op >> 6 {
        case 0:
            let v = r8(r); setR8(r, shiftOp(bit, v))
        case 1:
            let v = r8(r)
            f = (f & GBSystem.fC) | GBSystem.fH | ((v >> bit) & 1 == 0 ? GBSystem.fZ : 0)
        case 2:
            let v = r8(r); setR8(r, v & ~(1 << bit))
        default:
            let v = r8(r); setR8(r, v | (1 << bit))
        }
    }

    private func halt() {
        // EI;HALT with an interrupt pending: IME is on by the time HALT ends, so no bug.
        if !ime && !imeTurningOn && (ie & ifReg & 0x1F) != 0 {
            haltBug = true          // the next opcode byte is read twice
        } else {
            halted = true
        }
    }

    private func stop() {
        pc &+= 1                    // STOP is two bytes
        if cgb && speedPrepare {
            doubleSpeed.toggle()
            speedPrepare = false
            sysCounter = 0
            refreshDerived()
            for _ in 0..<64 { tick() }
        } else {
            stopped = true
            sysCounter = 0
        }
    }

    // MARK: test hooks

    /// Reads memory as the CPU would, without advancing time. For tests and the debugger.
    public func debugPeek(_ addr: UInt16) -> UInt8 { busRead(addr) }
    public var debugPC: UInt16 { pc }
    public var debugCycles: UInt64 { cycles }
    /// Pending audio for tests.
    public var debugPendingAudio: UnsafeBufferPointer<Float> { apu.decimator.pending }
}
