import Synchronization

/// Lock-free single-producer / single-consumer ring of mono Float32 samples.
///
/// The emulation thread writes, the audio render thread reads. Neither side allocates or locks.
public final class AudioRing: @unchecked Sendable {
    public let capacity: Int
    private let mask: Int
    private let buffer: UnsafeMutablePointer<Float>
    private let head = Atomic<Int>(0)   // next write index (producer)
    private let tail = Atomic<Int>(0)   // next read index (consumer)
    /// Last sample handed to the device: an underrun decays from here instead of clicking.
    private var lastOut: Float = 0

    public init(capacityPowerOfTwo: Int = 1 << 14) {
        precondition(capacityPowerOfTwo > 0 && capacityPowerOfTwo & (capacityPowerOfTwo - 1) == 0)
        capacity = capacityPowerOfTwo
        mask = capacityPowerOfTwo - 1
        buffer = .allocate(capacity: capacityPowerOfTwo)
        buffer.initialize(repeating: 0, count: capacityPowerOfTwo)
    }

    deinit { buffer.deallocate() }

    /// Samples waiting to be played.
    public var fill: Int {
        head.load(ordering: .acquiring) &- tail.load(ordering: .acquiring)
    }

    /// Producer side. Drops what doesn't fit (the pacing loop keeps us from getting here).
    public func write(_ samples: UnsafeBufferPointer<Float>) {
        let h = head.load(ordering: .relaxed)
        let t = tail.load(ordering: .acquiring)
        let space = capacity - (h &- t)
        let n = min(space, samples.count)
        guard n > 0, let base = samples.baseAddress else { return }
        for i in 0..<n { buffer[(h &+ i) & mask] = base[i] }
        head.store(h &+ n, ordering: .releasing)
    }

    /// Consumer side (audio thread). Always fills `out` completely.
    public func read(into out: UnsafeMutablePointer<Float>, count: Int) {
        let t = tail.load(ordering: .relaxed)
        let h = head.load(ordering: .acquiring)
        let n = min(h &- t, count)
        for i in 0..<n { out[i] = buffer[(t &+ i) & mask] }
        if n > 0 { lastOut = out[n - 1] }
        if n < count {
            var v = lastOut
            for i in n..<count { v *= 0.995; out[i] = v }
            lastOut = v
        }
        tail.store(t &+ n, ordering: .releasing)
    }

    /// Consumer-side flush (call only while the consumer is idle, e.g. after fast-forward
    /// stops, from the producer thread with the engine still running is also safe:
    /// it just advances the read index to the write index).
    public func clear() {
        tail.store(head.load(ordering: .acquiring), ordering: .releasing)
    }
}
