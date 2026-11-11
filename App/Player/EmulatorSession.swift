import AresCore
import CoreKit
import Foundation
import GBACore
import GBCore
import NESCore
import Synchronization

/// The newest finished frame, handed from the emulation thread to the renderer.
final class FrameExchange: @unchecked Sendable {
    private let lock = NSLock()
    private var pixels: UnsafeMutablePointer<UInt32>
    private var capacity: Int
    private(set) var width = 0
    private(set) var height = 0
    private var sequence: UInt64 = 0

    init() {
        capacity = 256 * 240
        pixels = .allocate(capacity: capacity)
        pixels.initialize(repeating: 0xFF000000, count: capacity)
    }

    deinit { pixels.deallocate() }

    func publish(_ src: UnsafeBufferPointer<UInt32>, width w: Int, height h: Int) {
        lock.lock()
        if w * h > capacity {
            pixels.deallocate()
            capacity = w * h
            pixels = .allocate(capacity: capacity)
        }
        if let base = src.baseAddress { pixels.update(from: base, count: w * h) }
        width = w
        height = h
        sequence &+= 1
        lock.unlock()
    }

    /// Calls `body` with the frame if it is newer than `since`. Returns the frame's sequence.
    @discardableResult
    func withFrame(newerThan since: UInt64, _ body: (UnsafePointer<UInt32>, Int, Int) -> Void) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        guard sequence != since, width > 0 else { return sequence }
        body(pixels, width, height)
        return sequence
    }

    /// A copy for thumbnails.
    func snapshot() -> (pixels: [UInt32], width: Int, height: Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard width > 0 else { return nil }
        return (Array(UnsafeBufferPointer(start: pixels, count: width * height)), width, height)
    }
}

/// Buttons from every source, merged by OR at the start of each frame.
final class InputLatch: Sendable {
    let touch = Atomic<UInt32>(0)
    let controller = Atomic<UInt32>(0)
    let keyboard = Atomic<UInt32>(0)
    /// Player 2 (a second controller), for systems with two ports.
    let player2 = Atomic<UInt32>(0)
    /// Buttons that auto-fire while held, and the half-period in frames.
    let autoFire = Atomic<UInt32>(0)
    let autoFireHalfPeriod = Atomic<Int>(3)

    var current: InputState {
        InputState(rawValue: touch.load(ordering: .relaxed) | controller.load(ordering: .relaxed)
                   | keyboard.load(ordering: .relaxed))
    }
}

/// Things the UI asks the emulation thread to do. Applied at frame boundaries.
enum SessionCommand: Sendable {
    case pause
    case resume
    case reset
    case speed(Int)
    case rewind(Bool)
    case saveState(@Sendable (Data?) -> Void)
    case loadState(Data, @Sendable (String?) -> Void)
    case battery(@Sendable (Data?) -> Void)
    case stop
}

/// Owns one core on a dedicated thread: pacing, audio rate control, rewind, fast-forward.
///
/// The core is built *on* that thread from Sendable inputs and never leaves it.
final class EmulatorSession: @unchecked Sendable {
    let system: SystemID
    let frames = FrameExchange()
    let audio = AudioRing(capacityPowerOfTwo: 1 << 14)
    let input = InputLatch()

    private let rom: Data
    private let battery: Data?
    private let commands = Mutex<[SessionCommand]>([])
    private var thread: Thread?

    /// Reported back to the main actor.
    var onError: (@Sendable (String) -> Void)?
    var onStarted: (@Sendable (_ videoWidth: Int, _ videoHeight: Int, _ romCRC: UInt32, _ stateVersion: UInt32, _ players: Int) -> Void)?
    /// The core changed resolution (Mega Drive 256/320 wide, SNES hi-res).
    var onVideoSize: (@Sendable (_ videoWidth: Int, _ videoHeight: Int) -> Void)?

    // Emulation-thread state (touched only on that thread).
    private var paused = false
    private var speed = 1
    private var rewinding = false
    private var rewindStates: [Data] = []
    private var rewindBytes = 0
    private let rewindCap = 24 * 1024 * 1024
    private var frameCount = 0

    init(system: SystemID, rom: Data, battery: Data?) {
        self.system = system
        self.rom = rom
        self.battery = battery
    }

    func start() {
        let t = Thread { [self] in self.run() }
        t.name = "Emulation"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    func send(_ command: SessionCommand) {
        commands.withLock { $0.append(command) }
    }

    // MARK: the emulation thread

    private static func makeCore(system: SystemID, rom: Data, battery: Data?) throws -> any EmulatorCore {
        switch system {
        case .nes: return try NESSystem(rom: rom, battery: battery)
        case .gb, .gbc: return try GBSystem(rom: rom, battery: battery)
        case .gba: return try GBASystem(rom: rom, battery: battery)
        case .snes: return try SNESSystem(rom: rom, battery: battery)
        case .md: return try MDSystem(rom: rom, battery: battery)
        }
    }

    private static func romCRC(_ core: any EmulatorCore, rom: Data) -> UInt32 {
        if let nes = core as? NESSystem { return nes.romCRC }
        if let gb = core as? GBSystem { return gb.romCRC }
        return CRC32.checksum(rom)
    }

    /// One live core per process: a quick quit-and-reopen waits for the old thread to let go
    /// (ares keeps its console in process-wide state).
    private static let coreGate = NSLock()

    private func run() {
        Self.coreGate.lock()
        defer { Self.coreGate.unlock() }
        runCore()
    }

    private func runCore() {
        let core: any EmulatorCore
        do {
            core = try Self.makeCore(system: system, rom: rom, battery: battery)
        } catch {
            onError?((error as? LocalizedError)?.errorDescription ?? "This game couldn't be started.")
            return
        }
        onStarted?(core.videoSize.width, core.videoSize.height, Self.romCRC(core, rom: rom), core.stateVersion, core.maxPlayers)

        var lastSize = core.videoSize
        let basePeriod = 1.0 / core.frameRate
        let targetFill = Double(core.audioSampleRate) * basePeriod * 3   // ~3 frames of audio queued
        var next = ProcessInfo.processInfo.systemUptime
        var running = true

        while running {
            let pending = commands.withLock { list -> [SessionCommand] in
                let l = list
                list.removeAll()
                return l
            }
            for c in pending {
                switch c {
                case .pause: paused = true
                case .resume:
                    paused = false
                    audio.clear()
                    next = ProcessInfo.processInfo.systemUptime
                case .reset: core.reset(); rewindStates.removeAll(); rewindBytes = 0
                case .speed(let s):
                    if s == 1 && speed != 1 { audio.clear() }
                    speed = max(1, s)
                case .rewind(let on):
                    rewinding = on
                    if !on { audio.clear() }
                case .saveState(let reply): reply(core.saveState())
                case .loadState(let data, let reply):
                    do {
                        try core.loadState(data)
                        core.runFrame(input: [])
                        discardAudio(core)
                        frames.publish(core.framebuffer, width: core.videoSize.width, height: core.videoSize.height)
                        reply(nil)
                    } catch {
                        reply((error as? LocalizedError)?.errorDescription ?? "That save state couldn't be loaded.")
                    }
                case .battery(let reply): reply(core.batteryRAM)
                case .stop: running = false
                }
            }
            if !running { break }
            if paused {
                Thread.sleep(forTimeInterval: 0.01)
                next = ProcessInfo.processInfo.systemUptime
                continue
            }

            if rewinding {
                if let state = rewindStates.popLast() {
                    rewindBytes -= state.count
                    try? core.loadState(state)
                    core.runFrame(input: [])
                    discardAudio(core)
                }
            } else {
                var held = input.current
                let fire = InputState(rawValue: input.autoFire.load(ordering: .relaxed))
                if !fire.isEmpty {
                    let half = max(1, input.autoFireHalfPeriod.load(ordering: .relaxed))
                    if (frameCount / half) % 2 == 1 { held.subtract(fire) }
                }
                let p2 = InputState(rawValue: input.player2.load(ordering: .relaxed)).sanitised
                for i in 0..<speed {
                    if core.maxPlayers > 1 { core.runFrame(inputs: [held, p2]) } else { core.runFrame(input: held) }
                    frameCount += 1
                    if frameCount % rewindInterval == 0 { pushRewind(core.saveState()) }
                    if i < speed - 1 { discardAudio(core) }
                }
                if speed == 1 { core.drainAudio(into: audio) } else { discardAudio(core) }
            }
            let size = core.videoSize
            frames.publish(core.framebuffer, width: size.width, height: size.height)
            if size != lastSize {
                lastSize = size
                onVideoSize?(size.width, size.height)
            }

            // Dynamic rate control: lengthen or shorten the frame by up to 0.5 % to hold the
            // audio queue near its target.
            var period = basePeriod
            if speed == 1 && !rewinding {
                let err = (Double(audio.fill) - targetFill) / targetFill
                period *= 1 + max(-0.005, min(0.005, err * 0.005))
            }
            next += period
            let now = ProcessInfo.processInfo.systemUptime
            if next < now - 0.1 { next = now }   // fell behind (debugger, backgrounding): resync
            if next > now { Thread.sleep(forTimeInterval: next - now) }
        }
    }

    private func discardAudio(_ core: any EmulatorCore) { core.discardAudio() }

    /// Big states (GBA ~400 KB) are snapshotted less often so rewind still reaches ~15 s back.
    private var rewindInterval = 4

    private func pushRewind(_ state: Data) {
        if state.count > 100_000 { rewindInterval = 15 }
        rewindStates.append(state)
        rewindBytes += state.count
        while rewindBytes > rewindCap, !rewindStates.isEmpty {
            rewindBytes -= rewindStates.removeFirst().count
        }
    }
}
