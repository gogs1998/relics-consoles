import CoreKit

/// The 2C02 picture processor, stepped one dot at a time (three per CPU cycle).
///
/// Background: the usual loopy v/t/x registers and 16-bit shifters, fetched on the real
/// 8-dot schedule. Sprites: evaluated for the next line at dot 257, then drawn from eight
/// slots. Sprite-0 hit and overflow are flagged; the overflow hardware bug is not modelled.
final class PPU {
    static let width = 256
    static let height = 240

    unowned(unsafe) var cart: Cartridge!
    unowned(unsafe) var mapper: Mapper!

    // registers
    var ctrl: UInt8 = 0
    var mask: UInt8 = 0
    var status: UInt8 = 0
    var oamAddr: UInt8 = 0
    var v: UInt16 = 0
    var t: UInt16 = 0
    var fineX: UInt8 = 0
    var w = false
    var readBuffer: UInt8 = 0
    var openBus: UInt8 = 0

    // memory
    let oam: UnsafeMutablePointer<UInt8>
    let ciram: UnsafeMutablePointer<UInt8>       // 4 KB (2 KB used unless four-screen)
    let palette: UnsafeMutablePointer<UInt8>     // 32

    // timing
    var scanline = 261
    var dot = 0
    var oddFrame = false
    var frameComplete = false
    var nmiLine = false
    var suppressVBlank = false
    /// A rising NMI edge waiting for the CPU, and the delay before a VBlank-caused rise counts.
    var nmiEdge = false
    // MMC3-style scanline counting watches PPU address line A12.
    var trackA12 = false
    var a12High = false
    var a12LowSince: UInt64 = 0
    var dotClock: UInt64 = 0
    let spA12: UnsafeMutablePointer<Bool> = {
        let p = UnsafeMutablePointer<Bool>.allocate(capacity: 8)
        p.initialize(repeating: false, count: 8)
        return p
    }()
    var nmiRiseCountdown = 0
    /// Set by a $2002 read that races the VBlank flag; the CPU drops a just-detected NMI.
    var cancelNMI = false

    // background pipeline
    var bgLo: UInt16 = 0, bgHi: UInt16 = 0
    var atLo: UInt16 = 0, atHi: UInt16 = 0
    var ntLatch: UInt8 = 0, atLatch: UInt8 = 0, patLo: UInt8 = 0, patHi: UInt8 = 0

    // sprites for the current line
    var spriteCount = 0
    let spPatLo: UnsafeMutablePointer<UInt8>
    let spPatHi: UnsafeMutablePointer<UInt8>
    let spX: UnsafeMutablePointer<UInt8>
    let spAttr: UnsafeMutablePointer<UInt8>
    var spriteZeroOnLine = false

    // output
    let pixels: UnsafeMutablePointer<UInt32>
    let colours: UnsafeMutablePointer<UInt32>   // 64 x 8 emphasis variants

    init() {
        oam = .allocate(capacity: 256); oam.initialize(repeating: 0xFF, count: 256)
        ciram = .allocate(capacity: 0x1000); ciram.initialize(repeating: 0, count: 0x1000)
        palette = .allocate(capacity: 32)
        palette.initialize(repeating: 0x0F, count: 32)
        spPatLo = .allocate(capacity: 8); spPatLo.initialize(repeating: 0, count: 8)
        spPatHi = .allocate(capacity: 8); spPatHi.initialize(repeating: 0, count: 8)
        spX = .allocate(capacity: 8); spX.initialize(repeating: 0xFF, count: 8)
        spAttr = .allocate(capacity: 8); spAttr.initialize(repeating: 0, count: 8)
        pixels = .allocate(capacity: PPU.width * PPU.height)
        pixels.initialize(repeating: 0xFF000000, count: PPU.width * PPU.height)
        colours = .allocate(capacity: 64 * 8)
        NESPalette.fill(colours)
    }

    deinit {
        oam.deallocate(); ciram.deallocate(); palette.deallocate()
        spPatLo.deallocate(); spPatHi.deallocate(); spX.deallocate(); spAttr.deallocate()
        pixels.deallocate(); colours.deallocate(); spA12.deallocate()
    }

    func reset() {
        ctrl = 0; mask = 0; w = false; readBuffer = 0
        scanline = 261; dot = 0; oddFrame = false
        nmiLine = false
    }

    @inline(__always) var renderingEnabled: Bool { (mask & 0x18) != 0 }

    // MARK: memory map

    @inline(__always)
    func ntIndex(_ addr: UInt16) -> Int {
        let a = Int(addr & 0x0FFF)
        let table = a >> 10
        let off = a & 0x3FF
        switch cart.mirroring {
        case .vertical: return ((table & 1) << 10) | off
        case .horizontal: return ((table >> 1) << 10) | off
        case .singleLow: return off
        case .singleHigh: return 0x400 | off
        case .fourScreen: return a
        }
    }

    @inline(__always)
    func paletteIndex(_ addr: UInt16) -> Int {
        var i = Int(addr & 0x1F)
        if i >= 16 && (i & 3) == 0 { i -= 16 }
        return i
    }

    @inline(__always)
    func readVRAM(_ addr: UInt16) -> UInt8 {
        let a = addr & 0x3FFF
        if a < 0x2000 { return cart.readCHR(a) }
        if a < 0x3F00 { return ciram[ntIndex(a)] }
        return palette[paletteIndex(a)]
    }

    @inline(__always)
    func writeVRAM(_ addr: UInt16, _ value: UInt8) {
        let a = addr & 0x3FFF
        if a < 0x2000 { cart.writeCHR(a, value) }
        else if a < 0x3F00 { ciram[ntIndex(a)] = value }
        else { palette[paletteIndex(a)] = value & 0x3F }
    }

    /// Address line A12 changed (fetch or CPU access). A rise after it has been low for a few CPU
    /// cycles clocks the cartridge's counter.
    @inline(__always)
    func setA12(_ high: Bool) {
        if high == a12High { return }
        a12High = high
        if high {
            if dotClock &- a12LowSince >= 9 { mapper.scanline() }
        } else {
            a12LowSince = dotClock
        }
    }

    // MARK: CPU-facing registers

    func readRegister(_ addr: UInt16) -> UInt8 {
        switch addr & 7 {
        case 2:
            // The VBlank race: a read one dot before the flag sets sees it clear and stops it
            // (and the NMI) for this frame; a read on the dot it sets sees it but cancels the NMI.
            if scanline == 241 && dot == 1 { suppressVBlank = true }
            if scanline == 241 && (dot == 2 || dot == 3) { cancelNMI = true }
            let r = (status & 0xE0) | (openBus & 0x1F)
            status &= 0x7F
            w = false
            updateNMI(fromStatusRead: true)
            openBus = r
            return r
        case 4:
            openBus = oam[Int(oamAddr)]
            return openBus
        case 7:
            var r: UInt8
            if (v & 0x3FFF) < 0x3F00 {
                r = readBuffer
                readBuffer = readVRAM(v)
            } else {
                r = (palette[paletteIndex(v)] & 0x3F) | (openBus & 0xC0)
                readBuffer = readVRAM(v &- 0x1000)
            }
            incrementV()
            openBus = r
            return r
        default:
            return openBus
        }
    }

    func writeRegister(_ addr: UInt16, _ value: UInt8) {
        openBus = value
        switch addr & 7 {
        case 0:
            ctrl = value
            t = (t & 0xF3FF) | (UInt16(value & 0x03) << 10)
            updateNMI()
        case 1:
            mask = value
        case 3:
            oamAddr = value
        case 4:
            oam[Int(oamAddr)] = value
            oamAddr &+= 1
        case 5:
            if !w {
                t = (t & 0xFFE0) | UInt16(value >> 3)
                fineX = value & 7
            } else {
                t = (t & 0x8C1F) | (UInt16(value & 0x07) << 12) | (UInt16(value & 0xF8) << 2)
            }
            w.toggle()
        case 6:
            if !w {
                t = (t & 0x00FF) | (UInt16(value & 0x3F) << 8)
            } else {
                t = (t & 0xFF00) | UInt16(value)
                v = t
                if trackA12 { setA12((v & 0x1000) != 0) }
            }
            w.toggle()
        case 7:
            writeVRAM(v, value)
            incrementV()
        default:
            break
        }
    }

    @inline(__always)
    private func incrementV() {
        v = (v &+ ((ctrl & 0x04) != 0 ? 32 : 1)) & 0x7FFF
        if trackA12 && !(renderingEnabled && (scanline < 240 || scanline == 261)) { setA12((v & 0x1000) != 0) }
    }

    @inline(__always)
    /// Recomputes the NMI output. A rise caused by a register write is latched at once; a rise
    /// caused by VBlank starting is latched two dots later, so disabling NMI right after the
    /// flag sets still suppresses it.
    func updateNMI(fromVBlank: Bool = false, fromStatusRead: Bool = false) {
        let line = (status & 0x80) != 0 && (ctrl & 0x80) != 0
        if line && !nmiLine {
            nmiRiseCountdown = 2
        }
        // Disabling NMI cancels a rise not yet latched; a $2002 read only does inside the race
        // window (handled by `cancelNMI`).
        if !line && !fromStatusRead { nmiRiseCountdown = 0 }
        nmiLine = line
    }

    // MARK: scrolling helpers

    @inline(__always)
    private func incrementX() {
        if (v & 0x001F) == 31 {
            v &= ~0x001F
            v ^= 0x0400
        } else {
            v &+= 1
        }
    }

    @inline(__always)
    private func incrementY() {
        if (v & 0x7000) != 0x7000 {
            v &+= 0x1000
        } else {
            v &= ~0x7000
            var y = (v & 0x03E0) >> 5
            if y == 29 {
                y = 0
                v ^= 0x0800
            } else if y == 31 {
                y = 0
            } else {
                y += 1
            }
            v = (v & ~0x03E0) | (y << 5)
        }
    }

    @inline(__always)
    private func reloadShifters() {
        bgLo = (bgLo & 0xFF00) | UInt16(patLo)
        bgHi = (bgHi & 0xFF00) | UInt16(patHi)
        atLo = (atLo & 0xFF00) | ((atLatch & 1) != 0 ? 0xFF : 0)
        atHi = (atHi & 0xFF00) | ((atLatch & 2) != 0 ? 0xFF : 0)
    }

    @inline(__always)
    private func backgroundFetch() {
        if trackA12 {
            switch dot & 7 {
            case 1, 3: setA12(false)
            case 4: setA12((ctrl & 0x10) != 0)
            default: break
            }
        }
        switch dot & 7 {
        case 1:
            reloadShifters()
            ntLatch = ciram[ntIndex(0x2000 | (v & 0x0FFF))]
        case 3:
            let addr = 0x23C0 | (v & 0x0C00) | ((v >> 4) & 0x38) | ((v >> 2) & 0x07)
            let shift = ((v >> 4) & 4) | (v & 2)
            atLatch = (ciram[ntIndex(addr)] >> shift) & 3
        case 5:
            let base: UInt16 = (ctrl & 0x10) != 0 ? 0x1000 : 0
            patLo = cart.readCHR(base &+ UInt16(ntLatch) &* 16 &+ ((v >> 12) & 7))
        case 7:
            let base: UInt16 = (ctrl & 0x10) != 0 ? 0x1000 : 0
            patHi = cart.readCHR(base &+ UInt16(ntLatch) &* 16 &+ ((v >> 12) & 7) &+ 8)
        case 0:
            incrementX()
        default:
            break
        }
    }

    // MARK: the dot loop

    @inline(__always)
    func step() {
        if nmiRiseCountdown > 0 {
            nmiRiseCountdown -= 1
            if nmiRiseCountdown == 0 { nmiEdge = true }
        }
        let visible = scanline < 240
        let preRender = scanline == 261
        if renderingEnabled && (visible || preRender) {
            if (dot >= 2 && dot <= 257) || (dot >= 322 && dot <= 337) {
                bgLo <<= 1; bgHi <<= 1; atLo <<= 1; atHi <<= 1
            }
            if (dot >= 1 && dot <= 256) || (dot >= 321 && dot <= 337) {
                backgroundFetch()
            }
            if visible && dot >= 1 && dot <= 256 {
                renderPixel()
            }
            if dot == 256 { incrementY() }
            if dot == 257 {
                v = (v & ~0x041F) | (t & 0x041F)
                if visible { evaluateSprites() } else {
                    spriteCount = 0
                    let emptyA12 = (ctrl & 0x20) != 0 ? true : (ctrl & 0x08) != 0
                    for i in 0..<8 { spA12[i] = emptyA12 }
                }
            }
            if trackA12 && dot >= 257 && dot <= 320 {
                switch (dot - 257) & 7 {
                case 0: setA12(false)                     // garbage nametable fetch
                case 3: setA12(spA12[(dot - 257) >> 3])   // sprite pattern fetch
                default: break
                }
            }
            if trackA12 && (dot == 337 || dot == 339) { setA12(false) }
            if preRender && dot >= 280 && dot <= 304 {
                v = (v & ~0x7BE0) | (t & 0x7BE0)
            }
            if preRender && dot == 339 && oddFrame {
                dot = 340   // the skipped dot on odd frames
            }
        } else if visible && dot >= 1 && dot <= 256 {
            // Rendering off: the backdrop (or the palette entry v points at).
            let x = dot - 1
            let idx = (v & 0x3F00) == 0x3F00 ? paletteIndex(v) : 0
            pixels[scanline * PPU.width + x] = colours[Int(palette[idx] & 0x3F) | emphasis]
        }

        if scanline == 241 && dot == 1 {
            if !suppressVBlank { status |= 0x80 }
            suppressVBlank = false
            updateNMI(fromVBlank: true)
            frameComplete = true
        } else if preRender && dot == 1 {
            status &= 0x1F
            updateNMI()
        }

        dot += 1
        dotClock &+= 1
        if dot > 340 {
            dot = 0
            scanline += 1
            if scanline > 261 {
                scanline = 0
                oddFrame.toggle()
            }
        }
    }

    @inline(__always) private var emphasis: Int { Int(mask >> 5) << 6 }

    @inline(__always)
    private func renderPixel() {
        let x = dot - 1
        var bgPixel: UInt8 = 0
        var bgPal: UInt8 = 0
        if (mask & 0x08) != 0 && (x >= 8 || (mask & 0x02) != 0) {
            let bit: UInt16 = 0x8000 >> UInt16(fineX)
            bgPixel = ((bgLo & bit) != 0 ? 1 : 0) | ((bgHi & bit) != 0 ? 2 : 0)
            bgPal = ((atLo & bit) != 0 ? 1 : 0) | ((atHi & bit) != 0 ? 2 : 0)
        }
        var spPixel: UInt8 = 0
        var spPal: UInt8 = 0
        var spBehind = false
        if (mask & 0x10) != 0 && (x >= 8 || (mask & 0x04) != 0) {
            for i in 0..<spriteCount {
                let off = x - Int(spX[i])
                if off < 0 || off > 7 { continue }
                let shift = UInt8(7 - off)
                let p = ((spPatLo[i] >> shift) & 1) | (((spPatHi[i] >> shift) & 1) << 1)
                if p == 0 { continue }
                if i == 0 && spriteZeroOnLine && bgPixel != 0 && x != 255 {
                    status |= 0x40
                }
                spPixel = p
                spPal = (spAttr[i] & 3) + 4
                spBehind = (spAttr[i] & 0x20) != 0
                break
            }
        }
        var index: Int
        if bgPixel == 0 && spPixel == 0 {
            index = 0
        } else if bgPixel == 0 {
            index = Int(spPal) * 4 + Int(spPixel)
        } else if spPixel == 0 || spBehind {
            index = Int(bgPal) * 4 + Int(bgPixel)
        } else {
            index = Int(spPal) * 4 + Int(spPixel)
        }
        var colour = palette[paletteIndex(UInt16(0x3F00 + index))] & 0x3F
        if (mask & 0x01) != 0 { colour &= 0x30 }
        pixels[scanline * PPU.width + x] = colours[Int(colour) | emphasis]
    }

    /// Finds up to eight sprites on the *next* line and fetches their pattern rows.
    private func evaluateSprites() {
        let height = (ctrl & 0x20) != 0 ? 16 : 8
        // Empty slots still fetch tile $FF: from the sprite table (8x8) or $1000 (8x16).
        let emptyA12 = height == 16 ? true : (ctrl & 0x08) != 0
        for i in 0..<8 { spA12[i] = emptyA12 }
        spriteCount = 0
        spriteZeroOnLine = false
        let line = scanline
        var n = 0
        while n < 64 {
            let y = Int(oam[n * 4])
            let row = line - y
            if row >= 0 && row < height {
                if spriteCount == 8 {
                    status |= 0x20
                    break
                }
                let tile = oam[n * 4 + 1]
                let attr = oam[n * 4 + 2]
                let xPos = oam[n * 4 + 3]
                var r = row
                if (attr & 0x80) != 0 { r = height - 1 - r }
                var addr: UInt16
                if height == 16 {
                    let table: UInt16 = (tile & 1) != 0 ? 0x1000 : 0
                    var t = UInt16(tile & 0xFE)
                    if r >= 8 { t += 1; r -= 8 }
                    addr = table | (t << 4) | UInt16(r)
                } else {
                    let table: UInt16 = (ctrl & 0x08) != 0 ? 0x1000 : 0
                    addr = table | (UInt16(tile) << 4) | UInt16(r)
                }
                var lo = cart.readCHR(addr)
                var hi = cart.readCHR(addr &+ 8)
                if (attr & 0x40) != 0 { lo = lo.bitReversed; hi = hi.bitReversed }
                spPatLo[spriteCount] = lo
                spPatHi[spriteCount] = hi
                spX[spriteCount] = xPos
                spAttr[spriteCount] = attr
                spA12[spriteCount] = (addr & 0x1000) != 0
                if n == 0 { spriteZeroOnLine = true }
                spriteCount += 1
            }
            n += 1
        }
    }

    func sync(_ s: inout StateCoder) {
        s.section("PPU ")
        s.sync(&ctrl); s.sync(&mask); s.sync(&status); s.sync(&oamAddr)
        s.sync(&v); s.sync(&t); s.sync(&fineX); s.sync(&w); s.sync(&readBuffer); s.sync(&openBus)
        s.bytes(oam, count: 256)
        s.bytes(ciram, count: 0x1000)
        s.bytes(palette, count: 32)
        s.sync(&scanline); s.sync(&dot); s.sync(&oddFrame); s.sync(&nmiLine); s.sync(&suppressVBlank); s.sync(&nmiEdge); s.sync(&nmiRiseCountdown)
        s.sync(&a12High); s.sync(&a12LowSince); s.sync(&dotClock)
        s.sync(&bgLo); s.sync(&bgHi); s.sync(&atLo); s.sync(&atHi)
        s.sync(&ntLatch); s.sync(&atLatch); s.sync(&patLo); s.sync(&patHi)
        s.sync(&spriteCount); s.sync(&spriteZeroOnLine)
        s.bytes(spPatLo, count: 8); s.bytes(spPatHi, count: 8); s.bytes(spX, count: 8); s.bytes(spAttr, count: 8)
    }
}

extension UInt8 {
    @inline(__always)
    var bitReversed: UInt8 {
        var b = self
        b = (b & 0xF0) >> 4 | (b & 0x0F) << 4
        b = (b & 0xCC) >> 2 | (b & 0x33) << 2
        b = (b & 0xAA) >> 1 | (b & 0x55) << 1
        return b
    }
}
