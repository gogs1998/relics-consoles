/// Turns a core's per-clock audio level into output-rate samples.
///
/// A box filter (average of every input since the last output) followed by the
/// console-style output stage: two DC-blocking high-passes and a gentle low-pass.
/// Owned by a core and used only on the emulation thread.
public struct Decimator {
    public let outputRate: Double
    @usableFromInline var step: Double
    @usableFromInline var phase: Double = 0
    @usableFromInline var acc: Float = 0
    @usableFromInline var count: Float = 0

    // filter state
    @usableFromInline var hp1Prev: Float = 0, hp1Out: Float = 0
    @usableFromInline var hp2Prev: Float = 0, hp2Out: Float = 0
    @usableFromInline var lpOut: Float = 0
    @usableFromInline let hp1A: Float, hp2A: Float, lpA: Float

    @usableFromInline var out: UnsafeMutablePointer<Float>
    @usableFromInline let outCapacity: Int
    public private(set) var outCount = 0

    /// - Parameters:
    ///   - inputRate: clocks per second at which `push` is called.
    ///   - highPass: corner frequencies of the two DC blockers (Hz); 0 disables one.
    public init(inputRate: Double, outputRate: Double = 48_000, highPass: (Double, Double) = (90, 440),
                lowPass: Double = 14_000) {
        self.outputRate = outputRate
        step = outputRate / inputRate
        func hpCoeff(_ f: Double) -> Float {
            guard f > 0 else { return 1 }
            let rc = 1 / (2 * Double.pi * f), dt = 1 / outputRate
            return Float(rc / (rc + dt))
        }
        hp1A = hpCoeff(highPass.0)
        hp2A = hpCoeff(highPass.1)
        let rc = 1 / (2 * Double.pi * lowPass), dt = 1 / outputRate
        lpA = Float(dt / (rc + dt))
        outCapacity = 8192
        out = .allocate(capacity: outCapacity)
    }

    /// Call when the struct's owner goes away (structs can't have deinit with a pointer we share).
    public func deallocate() { out.deallocate() }

    /// Retunes the input clock (e.g. GB double speed). Keeps filter state.
    public mutating func setInputRate(_ rate: Double) { step = outputRate / rate }

    @inlinable @inline(__always)
    public mutating func push(_ level: Float) {
        acc += level
        count += 1
        phase += step
        if phase >= 1 {
            phase -= 1
            emit(acc / count)
            acc = 0
            count = 0
        }
    }

    /// Pushes the same level for `n` clocks (for cores that step in multi-clock chunks).
    @inlinable
    public mutating func push(_ level: Float, clocks n: Int) {
        for _ in 0..<n { push(level) }
    }

    @usableFromInline
    mutating func emit(_ x: Float) {
        hp1Out = hp1A * (hp1Out + x - hp1Prev)
        hp1Prev = x
        hp2Out = hp2A * (hp2Out + hp1Out - hp2Prev)
        hp2Prev = hp1Out
        lpOut += lpA * (hp2Out - lpOut)
        if outCount < outCapacity {
            out[outCount] = lpOut
            outCount += 1
        }
    }

    /// Hands the pending samples to `ring` and empties the buffer.
    public mutating func drain(into ring: AudioRing) {
        ring.write(UnsafeBufferPointer(start: out, count: outCount))
        outCount = 0
    }

    /// Discards pending samples (fast-forward, rewind).
    public mutating func discard() { outCount = 0 }

    /// Read-only view of the pending samples (tests).
    public var pending: UnsafeBufferPointer<Float> { UnsafeBufferPointer(start: out, count: outCount) }
}
