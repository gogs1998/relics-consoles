import AVFoundation
import CoreKit

/// AVAudioEngine pulling mono Float32 at 48 kHz from the session's ring.
@MainActor
final class AudioOutput {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private(set) var isRunning = false

    /// Built outside any actor: a closure written in a @MainActor method inherits main-actor
    /// isolation, and Swift 6 traps when the render thread calls it.
    nonisolated private static func makeNode(ring: AudioRing, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let first = buffers.first, let data = first.mData else { return noErr }
            let out = data.assumingMemoryBound(to: Float.self)
            ring.read(into: out, count: Int(frameCount))
            // Any further channels get a copy (we produce mono).
            for b in buffers.dropFirst() {
                if let d = b.mData { d.copyMemory(from: data, byteCount: Int(frameCount) * 4) }
            }
            return noErr
        }
    }

    func start(ring: AudioRing, mixWithOthers: Bool = true) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: mixWithOthers ? [.mixWithOthers] : [])
        try? session.setPreferredIOBufferDuration(0.01)
        try? session.setActive(true)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1) else { return }
        let node = Self.makeNode(ring: ring, format: format)
        self.node = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        do {
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if let node {
            engine.detach(node)
            self.node = nil
        }
        isRunning = false
    }

    func pause() { engine.pause() }

    func resume() {
        if !engine.isRunning { try? engine.start() }
    }
}
