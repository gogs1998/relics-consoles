import CoreKit
import Foundation

/// Square channel (channel 1 has the frequency sweep on top).
struct Square {
    var on = false, dac = false
    var duty = 0, pos = 0, timer = 0, freq = 0
    var length = 0, lengthOn = false
    var vol = 0, envInit = 0, envUp = false, envPeriod = 0, envTimer = 0

    static let dutyBits: (UInt8, UInt8, UInt8, UInt8) = (0b0000_0001, 0b1000_0001, 0b1000_0111, 0b0111_1110)

    @inline(__always)
    mutating func step(_ n: Int) {
        timer -= n
        while timer <= 0 {
            timer += (2048 - freq) * 4
            pos = (pos + 1) & 7
        }
    }

    @inline(__always)
    var output: Int {
        guard on else { return 0 }
        let pattern: UInt8
        switch duty {
        case 0: pattern = Square.dutyBits.0
        case 1: pattern = Square.dutyBits.1
        case 2: pattern = Square.dutyBits.2
        default: pattern = Square.dutyBits.3
        }
        return (pattern >> UInt8(pos)) & 1 != 0 ? vol : 0
    }

    mutating func clockLength() {
        if lengthOn && length > 0 {
            length -= 1
            if length == 0 { on = false }
        }
    }

    mutating func clockEnvelope() {
        guard envPeriod != 0 else { return }
        envTimer -= 1
        if envTimer <= 0 {
            envTimer = envPeriod
            if envUp && vol < 15 { vol += 1 } else if !envUp && vol > 0 { vol -= 1 }
        }
    }

    mutating func writeEnvelope(_ v: UInt8) {
        envInit = Int(v >> 4)
        envUp = (v & 8) != 0
        envPeriod = Int(v & 7)
        dac = (v & 0xF8) != 0
        if !dac { on = false }
    }

    mutating func trigger() {
        on = dac
        if length == 0 { length = 64 }
        timer = (2048 - freq) * 4
        vol = envInit
        envTimer = envPeriod == 0 ? 8 : envPeriod
    }

    mutating func sync(_ st: inout StateCoder) {
        st.sync(&on); st.sync(&dac); st.sync(&duty); st.sync(&pos); st.sync(&timer); st.sync(&freq)
        st.sync(&length); st.sync(&lengthOn); st.sync(&vol); st.sync(&envInit); st.sync(&envUp)
        st.sync(&envPeriod); st.sync(&envTimer)
    }
}

/// The four-channel sound unit, mixed to mono and decimated to 48 kHz.
///
/// `step` takes clocks of the 4.19 MHz base clock (2 per M-cycle in double speed, 4 otherwise);
/// a sample is pushed to the decimator every 4 base clocks (1,048,576 Hz).
final class APU {
    var decimator = Decimator(inputRate: 1_048_576)
    var power = true
    let regs: UnsafeMutablePointer<UInt8>   // raw $FF10-$FF3F
    var wave: UnsafeMutablePointer<UInt8> { regs + 0x20 }

    var sq1 = Square(), sq2 = Square()
    // sweep
    var swPeriod = 0, swNeg = false, swShift = 0, swTimer = 0, swShadow = 0, swEnabled = false
    // wave
    var wOn = false, wDac = false, wLength = 0, wLengthOn = false, wFreq = 0, wTimer = 0, wPos = 0, wShift = 4
    var wSample: UInt8 = 0
    // noise
    var nOn = false, nDac = false, nLength = 0, nLengthOn = false
    var nVol = 0, nEnvInit = 0, nEnvUp = false, nEnvPeriod = 0, nEnvTimer = 0
    var nTimer = 0, nPeriod = 8, nLFSR: UInt16 = 0x7FFF, nWidth7 = false, nClocked = true
    // mixer
    var nr50: UInt8 = 0x77, nr51: UInt8 = 0xF3
    var fsStep = 0
    var phase = 0

    static let readMask: [UInt8] = [
        0x80, 0x3F, 0x00, 0xFF, 0xBF,   // NR10-NR14
        0xFF, 0x3F, 0x00, 0xFF, 0xBF,   // NR20-NR24
        0x7F, 0xFF, 0x9F, 0xFF, 0xBF,   // NR30-NR34
        0xFF, 0xFF, 0x00, 0x00, 0xBF,   // NR40-NR44
        0x00, 0x00, 0x70,               // NR50-NR52
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    ]
    static let noiseDivisors: [Int] = [8, 16, 32, 48, 64, 80, 96, 112]

    init() {
        regs = .allocate(capacity: 0x30)
        regs.initialize(repeating: 0, count: 0x30)
    }

    deinit {
        regs.deallocate()
        decimator.deallocate()
    }

    /// Post-boot register values.
    func reset() {
        powerOff()
        regs.update(repeating: 0, count: 0x30)
        power = true
        let boot: [(UInt16, UInt8)] = [
            (0xFF10, 0x80), (0xFF11, 0xBF), (0xFF12, 0xF3), (0xFF13, 0xFF), (0xFF14, 0x3F),
            (0xFF16, 0x3F), (0xFF17, 0x00), (0xFF18, 0xFF), (0xFF19, 0x3F),
            (0xFF1A, 0x7F), (0xFF1B, 0xFF), (0xFF1C, 0x9F), (0xFF1D, 0xFF), (0xFF1E, 0x3F),
            (0xFF20, 0xFF), (0xFF21, 0x00), (0xFF22, 0x00), (0xFF23, 0x3F),
            (0xFF24, 0x77), (0xFF25, 0xF3),
        ]
        for (a, v) in boot { write(a, v) }
        fsStep = 0
        phase = 0
    }

    private func powerOff() {
        for i in 0..<0x16 { regs[i] = 0 }
        sq1 = Square(); sq2 = Square()
        swPeriod = 0; swNeg = false; swShift = 0; swTimer = 0; swShadow = 0; swEnabled = false
        wOn = false; wDac = false; wLength = 0; wLengthOn = false; wFreq = 0; wTimer = 0; wPos = 0; wShift = 4
        nOn = false; nDac = false; nLength = 0; nLengthOn = false
        nVol = 0; nEnvInit = 0; nEnvUp = false; nEnvPeriod = 0; nEnvTimer = 0
        nTimer = 0; nPeriod = 8; nLFSR = 0x7FFF; nWidth7 = false; nClocked = true
        nr50 = 0; nr51 = 0
        power = false
    }

    // MARK: clocking

    @inline(__always)
    func step(_ n: Int) {
        if power {
            sq1.step(n)
            sq2.step(n)
            if wOn {
                wTimer -= n
                while wTimer <= 0 {
                    wTimer += (2048 - wFreq) * 2
                    wPos = (wPos + 1) & 31
                    let byte = wave[wPos >> 1]
                    wSample = (wPos & 1) == 0 ? byte >> 4 : byte & 0x0F
                }
            }
            if nOn && nClocked {
                nTimer -= n
                while nTimer <= 0 {
                    nTimer += nPeriod
                    let x = (nLFSR ^ (nLFSR >> 1)) & 1
                    nLFSR = (nLFSR >> 1) | (x << 14)
                    if nWidth7 { nLFSR = (nLFSR & ~0x40) | (x << 6) }
                }
            }
        }
        phase += n
        if phase >= 4 {
            phase -= 4
            decimator.push(power ? mix() : 0)
        }
    }

    @inline(__always)
    private func mix() -> Float {
        let s1 = sq1.output
        let s2 = sq2.output
        let s3 = wOn ? Int(wSample >> UInt8(wShift)) : 0
        let s4 = nOn && (nLFSR & 1) == 0 ? nVol : 0
        let m = nr51
        var left = 0, right = 0
        if (m & 0x10) != 0 { left += s1 }
        if (m & 0x20) != 0 { left += s2 }
        if (m & 0x40) != 0 { left += s3 }
        if (m & 0x80) != 0 { left += s4 }
        if (m & 0x01) != 0 { right += s1 }
        if (m & 0x02) != 0 { right += s2 }
        if (m & 0x04) != 0 { right += s3 }
        if (m & 0x08) != 0 { right += s4 }
        let lv = Int((nr50 >> 4) & 7) + 1, rv = Int(nr50 & 7) + 1
        return Float(left * lv + right * rv) * (1.0 / 1024.0)
    }

    /// The 512 Hz frame sequencer (clocked by a falling edge of DIV bit 4, bit 5 in double speed).
    func frameSequencer() {
        guard power else { return }
        if (fsStep & 1) == 0 {
            sq1.clockLength(); sq2.clockLength()
            if wLengthOn && wLength > 0 { wLength -= 1; if wLength == 0 { wOn = false } }
            if nLengthOn && nLength > 0 { nLength -= 1; if nLength == 0 { nOn = false } }
        }
        if fsStep == 2 || fsStep == 6 { clockSweep() }
        if fsStep == 7 {
            sq1.clockEnvelope(); sq2.clockEnvelope()
            if nEnvPeriod != 0 {
                nEnvTimer -= 1
                if nEnvTimer <= 0 {
                    nEnvTimer = nEnvPeriod
                    if nEnvUp && nVol < 15 { nVol += 1 } else if !nEnvUp && nVol > 0 { nVol -= 1 }
                }
            }
        }
        fsStep = (fsStep + 1) & 7
    }

    private func sweepCalc() -> Int {
        let delta = swShadow >> swShift
        let f = swNeg ? swShadow - delta : swShadow + delta
        if f > 2047 { sq1.on = false }
        return f
    }

    private func clockSweep() {
        swTimer -= 1
        guard swTimer <= 0 else { return }
        swTimer = swPeriod == 0 ? 8 : swPeriod
        guard swEnabled && swPeriod != 0 else { return }
        let f = sweepCalc()
        if f <= 2047 && swShift != 0 {
            swShadow = f
            sq1.freq = f
            _ = sweepCalc()
        }
    }

    // MARK: registers

    func read(_ addr: UInt16) -> UInt8 {
        let i = Int(addr) - 0xFF10
        if i >= 0x20 { return regs[i] }
        if i == 0x16 {
            var v: UInt8 = power ? 0xF0 : 0x70
            if sq1.on { v |= 1 }
            if sq2.on { v |= 2 }
            if wOn { v |= 4 }
            if nOn { v |= 8 }
            return v
        }
        return regs[i] | APU.readMask[i]
    }

    func write(_ addr: UInt16, _ v: UInt8) {
        let i = Int(addr) - 0xFF10
        if i >= 0x20 { regs[i] = v; return }
        if i == 0x16 {
            let on = (v & 0x80) != 0
            if power && !on { powerOff() } else if !power && on { power = true; fsStep = 0 }
            return
        }
        guard power else { return }
        regs[i] = v
        switch i {
        case 0x00:
            swPeriod = Int((v >> 4) & 7); swNeg = (v & 8) != 0; swShift = Int(v & 7)
        case 0x01:
            sq1.duty = Int(v >> 6); sq1.length = 64 - Int(v & 0x3F)
        case 0x02:
            sq1.writeEnvelope(v)
        case 0x03:
            sq1.freq = (sq1.freq & 0x700) | Int(v)
        case 0x04:
            sq1.freq = (sq1.freq & 0xFF) | (Int(v & 7) << 8)
            sq1.lengthOn = (v & 0x40) != 0
            if (v & 0x80) != 0 {
                sq1.trigger()
                swShadow = sq1.freq
                swTimer = swPeriod == 0 ? 8 : swPeriod
                swEnabled = swPeriod != 0 || swShift != 0
                if swShift != 0 { _ = sweepCalc() }
            }
        case 0x06:
            sq2.duty = Int(v >> 6); sq2.length = 64 - Int(v & 0x3F)
        case 0x07:
            sq2.writeEnvelope(v)
        case 0x08:
            sq2.freq = (sq2.freq & 0x700) | Int(v)
        case 0x09:
            sq2.freq = (sq2.freq & 0xFF) | (Int(v & 7) << 8)
            sq2.lengthOn = (v & 0x40) != 0
            if (v & 0x80) != 0 { sq2.trigger() }
        case 0x0A:
            wDac = (v & 0x80) != 0
            if !wDac { wOn = false }
        case 0x0B:
            wLength = 256 - Int(v)
        case 0x0C:
            switch (v >> 5) & 3 {
            case 0: wShift = 4
            case 1: wShift = 0
            case 2: wShift = 1
            default: wShift = 2
            }
        case 0x0D:
            wFreq = (wFreq & 0x700) | Int(v)
        case 0x0E:
            wFreq = (wFreq & 0xFF) | (Int(v & 7) << 8)
            wLengthOn = (v & 0x40) != 0
            if (v & 0x80) != 0 {
                wOn = wDac
                if wLength == 0 { wLength = 256 }
                wTimer = (2048 - wFreq) * 2 + 6
                wPos = 0
            }
        case 0x10:
            nLength = 64 - Int(v & 0x3F)
        case 0x11:
            nEnvInit = Int(v >> 4); nEnvUp = (v & 8) != 0; nEnvPeriod = Int(v & 7)
            nDac = (v & 0xF8) != 0
            if !nDac { nOn = false }
        case 0x12:
            let shift = Int(v >> 4)
            nWidth7 = (v & 8) != 0
            nPeriod = APU.noiseDivisors[Int(v & 7)] << shift
            nClocked = shift < 14
        case 0x13:
            nLengthOn = (v & 0x40) != 0
            if (v & 0x80) != 0 {
                nOn = nDac
                if nLength == 0 { nLength = 64 }
                nTimer = nPeriod
                nLFSR = 0x7FFF
                nVol = nEnvInit
                nEnvTimer = nEnvPeriod == 0 ? 8 : nEnvPeriod
            }
        case 0x14:
            nr50 = v
        case 0x15:
            nr51 = v
        default:
            break
        }
    }

    func sync(_ st: inout StateCoder) {
        st.section("APU ")
        st.sync(&power)
        st.bytes(regs, count: 0x30)
        sq1.sync(&st); sq2.sync(&st)
        st.sync(&swPeriod); st.sync(&swNeg); st.sync(&swShift); st.sync(&swTimer); st.sync(&swShadow); st.sync(&swEnabled)
        st.sync(&wOn); st.sync(&wDac); st.sync(&wLength); st.sync(&wLengthOn); st.sync(&wFreq); st.sync(&wTimer)
        st.sync(&wPos); st.sync(&wShift); st.sync(&wSample)
        st.sync(&nOn); st.sync(&nDac); st.sync(&nLength); st.sync(&nLengthOn)
        st.sync(&nVol); st.sync(&nEnvInit); st.sync(&nEnvUp); st.sync(&nEnvPeriod); st.sync(&nEnvTimer)
        st.sync(&nTimer); st.sync(&nPeriod); st.sync(&nLFSR); st.sync(&nWidth7); st.sync(&nClocked)
        st.sync(&nr50); st.sync(&nr51); st.sync(&fsStep); st.sync(&phase)
    }
}
