import CoreKit

private let lengthTable: [UInt8] = [
    10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14,
    12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30,
]
/// Bit `step` of byte `duty` is the waveform.
private let dutyBits: [UInt8] = [0b0000_0010, 0b0000_0110, 0b0001_1110, 0b1111_1001]
private let triangleTable: [UInt8] = [
    15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
]
private let noisePeriods: [UInt16] = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068]
private let dmcRates: [UInt16] = [428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54]

struct Envelope {
    var start = false
    var loop = false
    var constant = false
    var period: UInt8 = 0
    var divider: UInt8 = 0
    var decay: UInt8 = 0

    mutating func clock() {
        if start {
            start = false
            decay = 15
            divider = period
        } else if divider == 0 {
            divider = period
            if decay > 0 { decay -= 1 } else if loop { decay = 15 }
        } else {
            divider -= 1
        }
    }

    var volume: UInt8 { constant ? period : decay }

    mutating func sync(_ s: inout StateCoder) {
        s.sync(&start); s.sync(&loop); s.sync(&constant); s.sync(&period); s.sync(&divider); s.sync(&decay)
    }
}

struct Pulse {
    let isOne: Bool
    var enabled = false
    var duty: UInt8 = 0
    var step: UInt8 = 0
    var timer: UInt16 = 0
    var period: UInt16 = 0
    var length: UInt8 = 0
    var haltLength = false
    var env = Envelope()
    var sweepEnabled = false
    var sweepPeriod: UInt8 = 0
    var sweepNegate = false
    var sweepShift: UInt8 = 0
    var sweepDivider: UInt8 = 0
    var sweepReload = false

    init(isOne: Bool) { self.isOne = isOne }

    mutating func write(_ reg: UInt16, _ v: UInt8) {
        switch reg & 3 {
        case 0:
            duty = v >> 6
            haltLength = (v & 0x20) != 0
            env.loop = haltLength
            env.constant = (v & 0x10) != 0
            env.period = v & 0x0F
        case 1:
            sweepEnabled = (v & 0x80) != 0
            sweepPeriod = (v >> 4) & 7
            sweepNegate = (v & 0x08) != 0
            sweepShift = v & 7
            sweepReload = true
        case 2:
            period = (period & 0x700) | UInt16(v)
        default:
            period = (period & 0x0FF) | (UInt16(v & 7) << 8)
            if enabled { length = lengthTable[Int(v >> 3)] }
            step = 0
            env.start = true
        }
    }

    /// Clocked every APU cycle (every other CPU cycle).
    mutating func clockTimer() {
        if timer == 0 {
            timer = period
            step = (step + 1) & 7
        } else {
            timer -= 1
        }
    }

    var targetPeriod: UInt16 {
        let change = period >> UInt16(sweepShift)
        if sweepNegate {
            return period &- change &- (isOne ? 1 : 0)
        }
        return period &+ change
    }

    var muted: Bool { period < 8 || (!sweepNegate && targetPeriod > 0x7FF) }

    mutating func clockSweep() {
        if sweepDivider == 0 && sweepEnabled && sweepShift > 0 && !muted {
            period = targetPeriod & 0x7FF
        }
        if sweepDivider == 0 || sweepReload {
            sweepDivider = sweepPeriod
            sweepReload = false
        } else {
            sweepDivider -= 1
        }
    }

    mutating func clockLength() {
        if !haltLength && length > 0 { length -= 1 }
    }

    var output: UInt8 {
        if length == 0 || muted || (dutyBits[Int(duty)] >> step) & 1 == 0 { return 0 }
        return env.volume
    }

    mutating func sync(_ s: inout StateCoder) {
        s.sync(&enabled); s.sync(&duty); s.sync(&step); s.sync(&timer); s.sync(&period); s.sync(&length)
        s.sync(&haltLength); env.sync(&s)
        s.sync(&sweepEnabled); s.sync(&sweepPeriod); s.sync(&sweepNegate); s.sync(&sweepShift)
        s.sync(&sweepDivider); s.sync(&sweepReload)
    }
}

struct Triangle {
    var enabled = false
    var timer: UInt16 = 0
    var period: UInt16 = 0
    var step: UInt8 = 0
    var length: UInt8 = 0
    var control = false
    var linearReload: UInt8 = 0
    var linear: UInt8 = 0
    var reloadFlag = false

    mutating func write(_ reg: UInt16, _ v: UInt8) {
        switch reg & 3 {
        case 0:
            control = (v & 0x80) != 0
            linearReload = v & 0x7F
        case 2:
            period = (period & 0x700) | UInt16(v)
        case 3:
            period = (period & 0x0FF) | (UInt16(v & 7) << 8)
            if enabled { length = lengthTable[Int(v >> 3)] }
            reloadFlag = true
        default:
            break
        }
    }

    mutating func clockTimer() {
        if timer == 0 {
            timer = period
            // Ultrasonic periods are silenced on real hardware by the following filters;
            // freezing the sequencer avoids the aliasing pop.
            if length > 0 && linear > 0 && period >= 2 { step = (step + 1) & 31 }
        } else {
            timer -= 1
        }
    }

    mutating func clockLinear() {
        if reloadFlag { linear = linearReload } else if linear > 0 { linear -= 1 }
        if !control { reloadFlag = false }
    }

    mutating func clockLength() {
        if !control && length > 0 { length -= 1 }
    }

    var output: UInt8 { triangleTable[Int(step)] }

    mutating func sync(_ s: inout StateCoder) {
        s.sync(&enabled); s.sync(&timer); s.sync(&period); s.sync(&step); s.sync(&length)
        s.sync(&control); s.sync(&linearReload); s.sync(&linear); s.sync(&reloadFlag)
    }
}

struct Noise {
    var enabled = false
    var timer: UInt16 = 0
    var period: UInt16 = 4
    var shift: UInt16 = 1
    var mode = false
    var length: UInt8 = 0
    var haltLength = false
    var env = Envelope()

    mutating func write(_ reg: UInt16, _ v: UInt8) {
        switch reg & 3 {
        case 0:
            haltLength = (v & 0x20) != 0
            env.loop = haltLength
            env.constant = (v & 0x10) != 0
            env.period = v & 0x0F
        case 2:
            mode = (v & 0x80) != 0
            period = noisePeriods[Int(v & 0x0F)]
        case 3:
            if enabled { length = lengthTable[Int(v >> 3)] }
            env.start = true
        default:
            break
        }
    }

    mutating func clockTimer() {
        if timer == 0 {
            timer = period
            let other: UInt16 = mode ? (shift >> 6) & 1 : (shift >> 1) & 1
            let feedback = (shift & 1) ^ other
            shift = (shift >> 1) | (feedback << 14)
        } else {
            timer -= 1
        }
    }

    mutating func clockLength() {
        if !haltLength && length > 0 { length -= 1 }
    }

    var output: UInt8 {
        if length == 0 || (shift & 1) != 0 { return 0 }
        return env.volume
    }

    mutating func sync(_ s: inout StateCoder) {
        s.sync(&enabled); s.sync(&timer); s.sync(&period); s.sync(&shift); s.sync(&mode); s.sync(&length)
        s.sync(&haltLength); env.sync(&s)
    }
}

struct DMC {
    var irqEnabled = false
    var loop = false
    var rate: UInt16 = 428
    var timer: UInt16 = 0
    var output: UInt8 = 0
    var sampleAddress: UInt16 = 0xC000
    var sampleLength: UInt16 = 1
    var currentAddress: UInt16 = 0xC000
    var bytesRemaining: UInt16 = 0
    var buffer: UInt8 = 0
    var bufferEmpty = true
    var shiftReg: UInt8 = 0
    var bitsRemaining: UInt8 = 8
    var silence = true
    var irq = false

    mutating func sync(_ s: inout StateCoder) {
        s.sync(&irqEnabled); s.sync(&loop); s.sync(&rate); s.sync(&timer); s.sync(&output)
        s.sync(&sampleAddress); s.sync(&sampleLength); s.sync(&currentAddress); s.sync(&bytesRemaining)
        s.sync(&buffer); s.sync(&bufferEmpty); s.sync(&shiftReg); s.sync(&bitsRemaining); s.sync(&silence)
        s.sync(&irq)
    }
}

/// The 2A03's sound: two pulses, triangle, noise, DMC, the frame sequencer and the mixer.
final class APU {
    var pulse1 = Pulse(isOne: true)
    var pulse2 = Pulse(isOne: false)
    var triangle = Triangle()
    var noise = Noise()
    var dmc = DMC()

    var frameMode5 = false
    var frameIRQInhibit = false   // power-on behaves as if $4017 = $00
    var last4017: UInt8 = 0
    var frameIRQ = false
    var frameCycle = 0
    var evenCycle = false
    /// Countdown to applying a $4017 write (it lands 3-4 cycles later).
    var pendingFrameReset = -1

    /// Reads memory for DMC samples (set by the console); returns the byte and stalls the CPU.
    /// The DMC wants a sample byte: the CPU performs the DMA at its next read cycle.
    var dmcFetchPending = false
    var dmcAddress: UInt16 { dmc.currentAddress }

    var decimator: Decimator
    private let pulseMix: [Float]
    private let tndMix: [Float]

    init() {
        decimator = Decimator(inputRate: 1_789_773, outputRate: 48_000, highPass: (90, 440), lowPass: 14_000)
        pulseMix = (0..<31).map { n in n == 0 ? 0 : Float(95.52 / (8128.0 / Double(n) + 100)) }
        tndMix = (0..<203).map { n in n == 0 ? 0 : Float(163.67 / (24329.0 / Double(n) + 100)) }
    }

    deinit { decimator.deallocate() }

    var irqLine: Bool { frameIRQ || dmc.irq }

    func reset() {
        writeRegister(0x4015, 0)
        frameCycle = 0
        frameIRQ = false
        dmc.irq = false
        writeRegister(0x4017, last4017)   // reset re-writes the last value (power-on: $00)
        // ...and the write lands during the reset sequence, about 10 cycles before the first
        // instruction runs.
        pendingFrameReset = -1
        frameCycle = 6
    }

    func readStatus() -> UInt8 {
        var r: UInt8 = 0
        if pulse1.length > 0 { r |= 0x01 }
        if pulse2.length > 0 { r |= 0x02 }
        if triangle.length > 0 { r |= 0x04 }
        if noise.length > 0 { r |= 0x08 }
        if dmc.bytesRemaining > 0 { r |= 0x10 }
        if frameIRQ { r |= 0x40 }
        if dmc.irq { r |= 0x80 }
        frameIRQ = false
        return r
    }

    func writeRegister(_ addr: UInt16, _ v: UInt8) {
        switch addr {
        case 0x4000...0x4003: pulse1.write(addr, v)
        case 0x4004...0x4007: pulse2.write(addr, v)
        case 0x4008...0x400B: triangle.write(addr, v)
        case 0x400C...0x400F: noise.write(addr, v)
        case 0x4010:
            dmc.irqEnabled = (v & 0x80) != 0
            dmc.loop = (v & 0x40) != 0
            dmc.rate = dmcRates[Int(v & 0x0F)]
            if !dmc.irqEnabled { dmc.irq = false }
        case 0x4011:
            dmc.output = v & 0x7F
        case 0x4012:
            dmc.sampleAddress = 0xC000 | (UInt16(v) << 6)
        case 0x4013:
            dmc.sampleLength = (UInt16(v) << 4) | 1
        case 0x4015:
            pulse1.enabled = (v & 0x01) != 0; if !pulse1.enabled { pulse1.length = 0 }
            pulse2.enabled = (v & 0x02) != 0; if !pulse2.enabled { pulse2.length = 0 }
            triangle.enabled = (v & 0x04) != 0; if !triangle.enabled { triangle.length = 0 }
            noise.enabled = (v & 0x08) != 0; if !noise.enabled { noise.length = 0 }
            dmc.irq = false
            if (v & 0x10) != 0 {
                if dmc.bytesRemaining == 0 {
                    dmc.currentAddress = dmc.sampleAddress
                    dmc.bytesRemaining = dmc.sampleLength
                }
            } else {
                dmc.bytesRemaining = 0
            }
        case 0x4017:
            last4017 = v
            frameMode5 = (v & 0x80) != 0
            frameIRQInhibit = (v & 0x40) != 0
            if frameIRQInhibit { frameIRQ = false }
            pendingFrameReset = evenCycle ? 3 : 4
        default:
            break
        }
    }

    private func quarterFrame() {
        pulse1.env.clock()
        pulse2.env.clock()
        noise.env.clock()
        triangle.clockLinear()
    }

    private func halfFrame() {
        pulse1.clockLength(); pulse1.clockSweep()
        pulse2.clockLength(); pulse2.clockSweep()
        triangle.clockLength()
        noise.clockLength()
    }

    /// One CPU cycle.
    @inline(__always)
    func step() {
        if pendingFrameReset >= 0 {
            if pendingFrameReset == 0 {
                frameCycle = 0
                if frameMode5 { quarterFrame(); halfFrame() }
            }
            pendingFrameReset -= 1
        }
        frameCycle += 1
        switch frameCycle {
        case 7457: quarterFrame()
        case 14913: quarterFrame(); halfFrame()
        case 22371: quarterFrame()
        case 29828:
            if !frameMode5 && !frameIRQInhibit { frameIRQ = true }
        case 29829:
            if !frameMode5 {
                quarterFrame(); halfFrame()
                if !frameIRQInhibit { frameIRQ = true }
            }
        case 29830:
            if !frameMode5 {
                if !frameIRQInhibit { frameIRQ = true }
                frameCycle = 0
            }
        case 37281:
            if frameMode5 { quarterFrame(); halfFrame() }
        case 37282:
            frameCycle = 0
        default:
            break
        }

        triangle.clockTimer()
        if evenCycle {
            pulse1.clockTimer()
            pulse2.clockTimer()
            noise.clockTimer()
        }
        evenCycle.toggle()
        clockDMC()

        let p = Int(pulse1.output) + Int(pulse2.output)
        let tnd = 3 * Int(triangle.output) + 2 * Int(noise.output) + Int(dmc.output)
        decimator.push(pulseMix[p] + tndMix[tnd])
    }

    @inline(__always)
    private func clockDMC() {
        if dmc.bufferEmpty && dmc.bytesRemaining > 0 && !dmcFetchPending {
            dmcFetchPending = true
        }
        clockDMCOutput()
    }

    /// Completes a DMC DMA with the byte the CPU's bus fetched.
    func deliverDMC(_ value: UInt8) {
        guard dmc.bufferEmpty && dmc.bytesRemaining > 0 else { return }
        do {
            dmc.buffer = value
            dmc.bufferEmpty = false
            dmc.currentAddress = dmc.currentAddress == 0xFFFF ? 0x8000 : dmc.currentAddress + 1
            dmc.bytesRemaining -= 1
            if dmc.bytesRemaining == 0 {
                if dmc.loop {
                    dmc.currentAddress = dmc.sampleAddress
                    dmc.bytesRemaining = dmc.sampleLength
                } else if dmc.irqEnabled {
                    dmc.irq = true
                }
            }
        }
    }

    @inline(__always)
    private func clockDMCOutput() {
        if dmc.timer > 0 {
            dmc.timer -= 1
            return
        }
        dmc.timer = dmc.rate - 1
        if !dmc.silence {
            if (dmc.shiftReg & 1) != 0 {
                if dmc.output <= 125 { dmc.output += 2 }
            } else if dmc.output >= 2 {
                dmc.output -= 2
            }
        }
        dmc.shiftReg >>= 1
        dmc.bitsRemaining -= 1
        if dmc.bitsRemaining == 0 {
            dmc.bitsRemaining = 8
            if dmc.bufferEmpty {
                dmc.silence = true
            } else {
                dmc.silence = false
                dmc.shiftReg = dmc.buffer
                dmc.bufferEmpty = true
            }
        }
    }

    func sync(_ s: inout StateCoder) {
        s.section("APU ")
        pulse1.sync(&s); pulse2.sync(&s); triangle.sync(&s); noise.sync(&s); dmc.sync(&s)
        s.sync(&frameMode5); s.sync(&frameIRQInhibit); s.sync(&frameIRQ); s.sync(&frameCycle)
        s.sync(&evenCycle); s.sync(&pendingFrameReset); s.sync(&dmcFetchPending); s.sync(&last4017)
    }
}
