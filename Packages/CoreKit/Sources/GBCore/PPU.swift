import CoreKit
import Foundation

/// The LCD controller. Event-driven: the system adds dots to `dot` every M-cycle and only calls
/// `runEvents()` when `dot` reaches `nextEvent` (a mode change). Each visible line is drawn in
/// one go at the start of mode 3, from the registers as they are at that moment.
final class PPU {
    static let width = 160
    static let height = 144

    /// Our own neutral, slightly warm 4-shade greyscale for original Game Boy games.
    static let dmgShades: [UInt32] = [0xFFF4_F1E8, 0xFFB4_AE9E, 0xFF6B_6758, 0xFF26_241F]

    let cgb: Bool
    let pixels: UnsafeMutablePointer<UInt32>
    let vram: UnsafeMutablePointer<UInt8>     // 2 x 8 KB (bank 1 on CGB only)
    let oam: UnsafeMutablePointer<UInt8>      // 160 bytes
    var vramBankOff = 0                        // CPU-side VRAM bank ($FF4F)

    // registers
    var lcdc: UInt8 = 0x91
    var statSel: UInt8 = 0                     // STAT bits 3-6
    var scy: UInt8 = 0, scx: UInt8 = 0
    var ly: UInt8 = 0, lyc: UInt8 = 0
    var bgp: UInt8 = 0xFC, obp0: UInt8 = 0xFF, obp1: UInt8 = 0xFF
    var wy: UInt8 = 0, wx: UInt8 = 0

    // timing
    var mode: UInt8 = 2
    var dot = 0
    var nextEvent = 80
    var statLine = false
    var windowLine = 0
    /// The window line counter as it was when mode 3 began (the line is drawn again at its end).
    var lineWindowStart = 0
    var wyHit = false
    var frameComplete = false
    var hblankStarted = false

    // CGB palettes
    let bgPal: UnsafeMutablePointer<UInt8>     // 64 bytes
    let objPal: UnsafeMutablePointer<UInt8>
    var bcps: UInt8 = 0, ocps: UInt8 = 0
    let bgColors: UnsafeMutablePointer<UInt32>  // 32 converted colours
    let objColors: UnsafeMutablePointer<UInt32>

    // per-line scratch
    private let lineIdx: UnsafeMutablePointer<UInt8>
    private let linePri: UnsafeMutablePointer<UInt8>
    private let claimed: UnsafeMutablePointer<UInt8>
    private let spriteList: UnsafeMutablePointer<Int>
    private var dmgBG: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)

    init(cgb: Bool) {
        self.cgb = cgb
        pixels = .allocate(capacity: PPU.width * PPU.height)
        pixels.initialize(repeating: PPU.dmgShades[0], count: PPU.width * PPU.height)
        vram = .allocate(capacity: 0x4000)
        vram.initialize(repeating: 0, count: 0x4000)
        oam = .allocate(capacity: 0xA0)
        oam.initialize(repeating: 0, count: 0xA0)
        bgPal = .allocate(capacity: 64)
        bgPal.initialize(repeating: 0xFF, count: 64)
        objPal = .allocate(capacity: 64)
        objPal.initialize(repeating: 0, count: 64)
        bgColors = .allocate(capacity: 32)
        bgColors.initialize(repeating: 0xFFFF_FFFF, count: 32)
        objColors = .allocate(capacity: 32)
        objColors.initialize(repeating: 0xFF00_0000, count: 32)
        lineIdx = .allocate(capacity: 168)
        lineIdx.initialize(repeating: 0, count: 168)
        linePri = .allocate(capacity: 168)
        linePri.initialize(repeating: 0, count: 168)
        claimed = .allocate(capacity: 168)
        claimed.initialize(repeating: 0, count: 168)
        spriteList = .allocate(capacity: 10)
        spriteList.initialize(repeating: 0, count: 10)
        reset()
    }

    deinit {
        pixels.deallocate(); vram.deallocate(); oam.deallocate()
        bgPal.deallocate(); objPal.deallocate(); bgColors.deallocate(); objColors.deallocate()
        lineIdx.deallocate(); linePri.deallocate(); claimed.deallocate(); spriteList.deallocate()
    }

    func reset() {
        vram.update(repeating: 0, count: 0x4000)
        oam.update(repeating: 0, count: 0xA0)
        bgPal.update(repeating: 0xFF, count: 64)
        objPal.update(repeating: 0, count: 64)
        refreshAllColors()
        vramBankOff = 0
        lcdc = 0x91; statSel = 0; scy = 0; scx = 0; ly = 0; lyc = 0
        bgp = 0xFC; obp0 = 0xFF; obp1 = 0xFF; wy = 0; wx = 0
        mode = 2; dot = 0; nextEvent = 80; statLine = false
        windowLine = 0; wyHit = false; frameComplete = false; hblankStarted = false
        bcps = 0; ocps = 0
    }

    // MARK: registers

    var statValue: UInt8 {
        let on = (lcdc & 0x80) != 0
        return 0x80 | statSel | (ly == lyc && on ? 4 : 0) | (on ? mode : 0)
    }

    /// Re-evaluates the STAT interrupt line; returns IF bits on a rising edge.
    @inline(__always)
    func updateStat() -> UInt8 {
        guard (lcdc & 0x80) != 0 else { statLine = false; return 0 }
        var line = (statSel & 0x40) != 0 && ly == lyc
        switch mode {
        case 0: line = line || (statSel & 0x08) != 0
        case 1: line = line || (statSel & 0x10) != 0
        case 2: line = line || (statSel & 0x20) != 0
        default: break
        }
        let rising = line && !statLine
        statLine = line
        return rising ? 2 : 0
    }

    func writeLCDC(_ v: UInt8) -> UInt8 {
        let wasOn = (lcdc & 0x80) != 0
        lcdc = v
        let on = (v & 0x80) != 0
        if wasOn && !on {
            ly = 0; mode = 0; dot = 0; nextEvent = 70224; statLine = false
            // a switched-off LCD shows a blank (lightest) screen
            pixels.update(repeating: cgb ? 0xFFFF_FFFF : PPU.dmgShades[0], count: PPU.width * PPU.height)
        } else if !wasOn && on {
            ly = 0; mode = 2; dot = 0; nextEvent = 80; windowLine = 0; wyHit = false
            return updateStat()
        }
        return 0
    }

    func writeBCPD(_ v: UInt8) {
        let i = Int(bcps & 0x3F)
        bgPal[i] = v
        bgColors[i >> 1] = PPU.convert(bgPal, i >> 1)
        if (bcps & 0x80) != 0 { bcps = 0x80 | ((bcps &+ 1) & 0x3F) }
    }

    func writeOCPD(_ v: UInt8) {
        let i = Int(ocps & 0x3F)
        objPal[i] = v
        objColors[i >> 1] = PPU.convert(objPal, i >> 1)
        if (ocps & 0x80) != 0 { ocps = 0x80 | ((ocps &+ 1) & 0x3F) }
    }

    private func refreshAllColors() {
        for i in 0..<32 {
            bgColors[i] = PPU.convert(bgPal, i)
            objColors[i] = PPU.convert(objPal, i)
        }
    }

    /// 15-bit BGR555 to 0xAARRGGBB with a mild colour correction (the CGB screen's colours bleed
    /// a little and its saturated primaries look softer than raw RGB).
    static func convert(_ pal: UnsafeMutablePointer<UInt8>, _ index: Int) -> UInt32 {
        let w = Int(pal[index * 2]) | (Int(pal[index * 2 + 1]) << 8)
        let r = Double(w & 31) / 31, g = Double((w >> 5) & 31) / 31, b = Double((w >> 10) & 31) / 31
        let rr = 0.84 * r + 0.12 * g + 0.04 * b
        let gg = 0.05 * r + 0.86 * g + 0.09 * b
        let bb = 0.04 * r + 0.12 * g + 0.84 * b
        func byte(_ x: Double) -> UInt32 { UInt32(max(0, min(255, (pow(x, 1.05) * 255).rounded()))) }
        return 0xFF00_0000 | (byte(rr) << 16) | (byte(gg) << 8) | byte(bb)
    }

    // MARK: timing

    /// Handles every mode change that `dot` has reached; returns IF bits to raise.
    func runEvents() -> UInt8 {
        var irq: UInt8 = 0
        while dot >= nextEvent {
            if (lcdc & 0x80) == 0 {
                dot -= 70224
                nextEvent = 70224
                frameComplete = true
                continue
            }
            switch mode {
            case 2:
                // Draw once now for the mode-3 length, then again when mode 3 ends, so register
                // writes made by LYC / mode-2 handlers during the line still land on it.
                mode = 3
                lineWindowStart = windowLine
                nextEvent = 80 + renderLine()
            case 3:
                windowLine = lineWindowStart
                _ = renderLine()
                mode = 0
                hblankStarted = true
                nextEvent = 456
            default:
                dot -= 456
                ly &+= 1
                if ly == 144 {
                    mode = 1
                    irq |= 1
                    frameComplete = true
                    nextEvent = 456
                } else if ly == 154 {
                    ly = 0
                    mode = 2
                    nextEvent = 80
                    windowLine = 0
                    wyHit = false
                } else if ly > 144 {
                    nextEvent = 456
                } else {
                    mode = 2
                    nextEvent = 80
                }
            }
            irq |= updateStat()
        }
        return irq
    }

    // MARK: rendering

    /// Draws line `ly`; returns the length of mode 3 in dots.
    private func renderLine() -> Int {
        if ly == wy { wyHit = true }
        let y = Int(ly)
        let row = pixels + y * PPU.width
        let masterBG = (lcdc & 1) != 0
        var penalty = Int(scx & 7)

        if !cgb {
            dmgBG = (PPU.dmgShades[Int(bgp & 3)], PPU.dmgShades[Int((bgp >> 2) & 3)],
                     PPU.dmgShades[Int((bgp >> 4) & 3)], PPU.dmgShades[Int((bgp >> 6) & 3)])
        }

        if cgb || masterBG {
            let bgMap = (lcdc & 0x08) != 0 ? 0x1C00 : 0x1800
            drawSpan(row: row, map: bgMap, srcX: Int(scx), srcY: (y + Int(scy)) & 255, from: 0, to: PPU.width)
            if (lcdc & 0x20) != 0 && wyHit && wx <= 166 {
                let start = Int(wx) - 7
                let winMap = (lcdc & 0x40) != 0 ? 0x1C00 : 0x1800
                if start < 0 {
                    drawSpan(row: row, map: winMap, srcX: -start, srcY: windowLine, from: 0, to: PPU.width)
                } else {
                    drawSpan(row: row, map: winMap, srcX: 0, srcY: windowLine, from: start, to: PPU.width)
                }
                windowLine += 1
                penalty += 6
            }
        } else {
            let c = PPU.dmgShades[0]
            for x in 0..<PPU.width { row[x] = c; lineIdx[x] = 0 }
        }

        if (lcdc & 0x02) != 0 {
            penalty += drawSprites(row: row, y: y)
        }
        return 172 + min(penalty, 117)
    }

    @inline(__always)
    private func drawSpan(row: UnsafeMutablePointer<UInt32>, map: Int, srcX: Int, srcY: Int, from x0: Int, to x1: Int) {
        var x = x0
        var sx = srcX & 255
        let mapRow = map + ((srcY >> 3) & 31) * 32
        let fineY = srcY & 7
        let unsignedTiles = (lcdc & 0x10) != 0
        while x < x1 {
            let mapAddr = mapRow + (sx >> 3)
            let tile = vram[mapAddr]
            var attr: UInt8 = 0
            if cgb { attr = vram[0x2000 + mapAddr] }
            let fy = (attr & 0x40) != 0 ? 7 - fineY : fineY
            var addr = unsignedTiles ? Int(tile) * 16 : 0x1000 + Int(Int8(bitPattern: tile)) * 16
            addr += fy * 2
            if (attr & 0x08) != 0 { addr += 0x2000 }
            let lo = vram[addr], hi = vram[addr + 1]
            let flip = (attr & 0x20) != 0
            let pri = attr & 0x80
            let palBase = Int(attr & 7) * 4
            var fx = sx & 7
            while fx < 8 && x < x1 {
                let bit = UInt8(flip ? fx : 7 - fx)
                let idx = ((lo >> bit) & 1) | (((hi >> bit) & 1) << 1)
                lineIdx[x] = idx
                linePri[x] = pri
                if cgb {
                    row[x] = bgColors[palBase + Int(idx)]
                } else {
                    switch idx {
                    case 0: row[x] = dmgBG.0
                    case 1: row[x] = dmgBG.1
                    case 2: row[x] = dmgBG.2
                    default: row[x] = dmgBG.3
                    }
                }
                x += 1; fx += 1; sx += 1
            }
            sx &= 255
        }
    }

    /// Returns the mode-3 penalty for the sprites on this line.
    private func drawSprites(row: UnsafeMutablePointer<UInt32>, y: Int) -> Int {
        let height = (lcdc & 0x04) != 0 ? 16 : 8
        var count = 0
        for i in 0..<40 {
            let sy = Int(oam[i * 4]) - 16
            if y >= sy && y < sy + height {
                spriteList[count] = i
                count += 1
                if count == 10 { break }
            }
        }
        guard count > 0 else { return 0 }
        if !cgb {
            // DMG: lower X wins, then lower OAM index (stable insertion sort by X).
            var i = 1
            while i < count {
                let s = spriteList[i]
                let sx = oam[s * 4 + 1]
                var j = i - 1
                while j >= 0 && oam[spriteList[j] * 4 + 1] > sx {
                    spriteList[j + 1] = spriteList[j]
                    j -= 1
                }
                spriteList[j + 1] = s
                i += 1
            }
        }
        claimed.update(repeating: 0, count: PPU.width)
        let masterBG = (lcdc & 1) != 0
        let obj0 = (PPU.dmgShades[Int((obp0 >> 2) & 3)], PPU.dmgShades[Int((obp0 >> 4) & 3)],
                    PPU.dmgShades[Int((obp0 >> 6) & 3)])
        let obj1 = (PPU.dmgShades[Int((obp1 >> 2) & 3)], PPU.dmgShades[Int((obp1 >> 4) & 3)],
                    PPU.dmgShades[Int((obp1 >> 6) & 3)])
        for k in 0..<count {
            let o = spriteList[k] * 4
            let sy = Int(oam[o]) - 16
            let sx = Int(oam[o + 1]) - 8
            var tile = Int(oam[o + 2])
            let attr = oam[o + 3]
            var line = y - sy
            if (attr & 0x40) != 0 { line = height - 1 - line }
            if height == 16 { tile &= 0xFE }
            var addr = tile * 16 + line * 2
            if cgb && (attr & 0x08) != 0 { addr += 0x2000 }
            let lo = vram[addr], hi = vram[addr + 1]
            let flip = (attr & 0x20) != 0
            let behind = (attr & 0x80) != 0
            let palBase = Int(attr & 7) * 4
            let useObp1 = (attr & 0x10) != 0
            for px in 0..<8 {
                let x = sx + px
                if x < 0 || x >= PPU.width || claimed[x] != 0 { continue }
                let bit = UInt8(flip ? px : 7 - px)
                let idx = ((lo >> bit) & 1) | (((hi >> bit) & 1) << 1)
                if idx == 0 { continue }
                claimed[x] = 1
                if cgb {
                    if masterBG && lineIdx[x] != 0 && (linePri[x] != 0 || behind) { continue }
                    row[x] = objColors[palBase + Int(idx)]
                } else {
                    if behind && lineIdx[x] != 0 { continue }
                    let p = useObp1 ? obj1 : obj0
                    row[x] = idx == 1 ? p.0 : (idx == 2 ? p.1 : p.2)
                }
            }
        }
        return count * 6
    }

    // MARK: state

    func sync(_ st: inout StateCoder) {
        st.section("PPU ")
        st.sync(&vramBankOff)
        st.sync(&lcdc); st.sync(&statSel); st.sync(&scy); st.sync(&scx); st.sync(&ly); st.sync(&lyc)
        st.sync(&bgp); st.sync(&obp0); st.sync(&obp1); st.sync(&wy); st.sync(&wx)
        st.sync(&mode); st.sync(&dot); st.sync(&nextEvent); st.sync(&statLine)
        st.sync(&windowLine); st.sync(&lineWindowStart); st.sync(&wyHit); st.sync(&hblankStarted)
        st.sync(&bcps); st.sync(&ocps)
        st.bytes(vram, count: 0x4000)
        st.bytes(oam, count: 0xA0)
        st.bytes(bgPal, count: 64)
        st.bytes(objPal, count: 64)
        let n = PPU.width * PPU.height * 4
        pixels.withMemoryRebound(to: UInt8.self, capacity: n) { st.bytes($0, count: n) }
        if st.isReading { refreshAllColors() }
    }
}
