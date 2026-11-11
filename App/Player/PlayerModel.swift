import AVFoundation
import CoreKit
import Observation
import SwiftUI
import UIKit

/// One play session, owned by the main actor: the emulation session plus audio, input and saves.
@MainActor
@Observable
final class PlayerModel {
    let game: GameRecord
    let session: EmulatorSession
    let controller = ControllerModel()
    let gamepads: GamepadHub
    let layouts = LayoutStore.shared
    /// Edit mode for the touch controller (nil when not editing). The game stays paused meanwhile.
    var editor: LayoutEditor?
    /// The controller-remapping sheet.
    var showingControllers = false
    /// Keep the on-screen controller visible even with a physical controller connected.
    var keepTouchControls = UserDefaults.standard.bool(forKey: "keepTouchControls") {
        didSet { UserDefaults.standard.set(keepTouchControls, forKey: "keepTouchControls") }
    }
    private(set) var players = 1
    /// True when a physical controller drives the game and the touch controller steps aside.
    var physicalMode: Bool { gamepads.isConnected && !keepTouchControls && editor == nil }

    private(set) var videoSize = CGSize(width: 256, height: 240)
    private(set) var errorMessage: String?
    private(set) var started = false
    var menuOpen = false {
        didSet {
            if menuOpen { pause() } else if editor == nil && !showingControllers { resume() }
        }
    }
    private(set) var fastForward = false
    private(set) var rewinding = false
    private(set) var toast: String?
    private(set) var savingPulse = 0
    private(set) var slotThumbs: [Int: UIImage] = [:]
    private(set) var slotDates: [Int: Date] = [:]
    /// DEBUG: "samplesPulled peak" for the UI test.
    private(set) var audioStats = "0 0"
    #if DEBUG
    /// DEBUG: "touches x y" (stylus presses sent to the core, and the last point) for the UI test.
    var stylusDebug = "0"
    #endif
    /// Mega Drive: show the six-button pad (X Y Z, Mode) instead of the three-button one.
    var sixButtonPad = UserDefaults.standard.bool(forKey: "md.sixButton") {
        didSet { UserDefaults.standard.set(sixButtonPad, forKey: "md.sixButton") }
    }
    var screenMode: ScreenMode {
        didSet { UserDefaults.standard.set(screenMode.rawValue, forKey: "screenMode.\(game.system.rawValue)") }
    }

    @ObservationIgnored private let store: GameStore
    @ObservationIgnored private let audio = AudioOutput()
    @ObservationIgnored private var romCRC: UInt32 = 0
    @ObservationIgnored private var stateVersion: UInt32 = 1
    @ObservationIgnored private var startTime = Date()
    @ObservationIgnored private var batteryTimer: Timer?
    @ObservationIgnored private var debugTimer: Timer?
    @ObservationIgnored private var lastBattery: Data?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(game: GameRecord, store: GameStore) throws {
        self.game = game
        self.store = store
        // Mapped, not read: a DS cartridge can be hundreds of MB and the core keeps its own copy.
        let rom = try Data(contentsOf: store.romURL(for: game), options: .mappedIfSafe)
        if rom.isEmpty { throw ImportError.unreadable(game.fileName) }
        gamepads = GamepadHub(system: game.system)
        let battery = try? Data(contentsOf: store.batteryURL(for: game))
        lastBattery = battery
        session = EmulatorSession(system: game.system, rom: rom, battery: battery)
        let saved = UserDefaults.standard.string(forKey: "screenMode.\(game.system.rawValue)")
        screenMode = saved.flatMap(ScreenMode.init(rawValue:)) ?? .auto
    }


    func start(resume autoResume: Bool) {
        controller.latch = session.input
        controller.onMenu = { [weak self] in self?.menuOpen = true }
        controller.onFastForward = { [weak self] on in self?.setFastForward(on) }
        controller.onRewind = { [weak self] on in self?.setRewind(on) }
        gamepads.attach(to: session.input)
        gamepads.onHotkey = { [weak self] key, down in self?.hotkey(key, down: down) }
        gamepads.onConnection = { [weak self] name, connected in
            guard let self else { return }
            self.controller.releaseAll()
            self.show(connected ? "\(name) connected" : "\(name) disconnected")
        }

        session.onError = { [weak self] message in
            Task { @MainActor in self?.errorMessage = message }
        }
        session.onStarted = { [weak self] w, h, crc, version, players in
            Task { @MainActor in
                self?.videoSize = CGSize(width: w, height: h)
                self?.romCRC = crc
                self?.stateVersion = version
                self?.players = players
                self?.gamepads.players = players
                self?.started = true
                if autoResume { self?.resumeAutoState() }
            }
        }
        session.onVideoSize = { [weak self] w, h in
            Task { @MainActor in
                // SNES hi-res frames are twice as wide but show the same picture shape.
                self?.videoSize = CGSize(width: w >= 512 ? w / 2 : w, height: h >= 448 ? h / 2 : h)
            }
        }
        session.start()
        audio.start(ring: session.audio)
        refreshSlots()

        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushBattery() }
        }
        #if DEBUG
        debugTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let ring = self?.session.audio else { return }
                self?.audioStats = "\(ring.samplesPulled) \(ring.peakOut)"
                AudioOutput.log.info("ring fill \(ring.fill) pulled \(ring.samplesPulled) peak \(ring.peakOut)")
            }
        }
        #endif
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controller.releaseAll()
                self?.pause()
                self?.writeAutoState()
                self?.flushBattery()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.menuOpen == false { self?.resume() } }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
            MainActor.assumeIsolated {
                guard let self else { return }
                if began {
                    self.menuOpen = true           // a call: pause behind the menu
                } else {
                    self.audio.restart()           // re-activate the session; the player resumes from the menu
                }
            }
        })
    }

    /// Leaving the game: auto-state, battery, stop the thread.
    func stop() {
        writeAutoState()
        flushBattery()
        batteryTimer?.invalidate()
        debugTimer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        controller.releaseAll()
        gamepads.detach()
        session.send(.stop)
        audio.stop()
        store.markPlayed(game.id, seconds: Date().timeIntervalSince(startTime))
    }

    func pause() {
        session.send(.pause)
        audio.pause()
    }

    func resume() {
        session.send(.resume)
        audio.resume()
    }

    func reset() {
        session.send(.reset)
        menuOpen = false
        show("Reset")
    }

    func setFastForward(_ on: Bool) {
        fastForward = on
        session.send(.speed(on ? 3 : 1))
    }

    func setRewind(_ on: Bool) {
        rewinding = on
        session.send(.rewind(on))
    }

    // MARK: saves

    private func flushBattery() {
        let url = store.batteryURL(for: game)
        let previous = lastBattery
        session.send(.battery { [weak self] data in
            guard let data, data != previous else { return }
            try? data.write(to: url, options: .atomic)
            Task { @MainActor in
                self?.lastBattery = data
                self?.savingPulse += 1
            }
        })
    }

    func saveState(slot: Int) {
        let url = store.stateURL(for: game, slot: slot)
        let thumbURL = store.thumbnailURL(for: game, slot: slot)
        let thumb = currentThumbnail()
        let system = game.system, crc = romCRC, version = stateVersion
        session.send(.saveState { [weak self] payload in
            guard let payload else { return }
            let data = StateContainer(system: system, coreStateVersion: version, romCRC: crc, payload: payload).encoded()
            try? data.write(to: url, options: .atomic)
            if let png = thumb { try? png.write(to: thumbURL, options: .atomic) }
            Task { @MainActor in
                self?.refreshSlots()
                self?.savingPulse += 1
                if slot != 0 { self?.show("Saved to slot \(slot)") }
            }
        })
    }

    func loadState(slot: Int) {
        guard let data = try? Data(contentsOf: store.stateURL(for: game, slot: slot)) else {
            show("Slot \(slot) is empty")
            return
        }
        do {
            let c = try StateContainer.decode(data)
            guard c.system == game.system, c.romCRC == romCRC || romCRC == 0 else {
                show("That state belongs to a different game")
                return
            }
            guard c.coreStateVersion == stateVersion else {
                show("That state was made by an older version of the app")
                return
            }
            session.send(.loadState(c.payload) { [weak self] error in
                Task { @MainActor in
                    self?.show(error ?? (slot == 0 ? "Resumed where you left off" : "Loaded slot \(slot)"))
                }
            })
            menuOpen = false
        } catch {
            show((error as? LocalizedError)?.errorDescription ?? "That state couldn't be loaded")
        }
    }

    private func writeAutoState() {
        guard started, errorMessage == nil else { return }
        saveState(slot: 0)
    }

    private func resumeAutoState() {
        guard FileManager.default.fileExists(atPath: store.stateURL(for: game, slot: 0).path) else { return }
        loadState(slot: 0)
    }

    // MARK: controllers and layouts

    private func hotkey(_ key: Hotkey, down: Bool) {
        switch key {
        case .menu: if down { menuOpen.toggle() }
        case .fastForward: setFastForward(down)
        case .rewind: setRewind(down)
        case .saveState:
            if down { saveState(slot: 1); gamepads.pulse() }
        case .loadState:
            if down { loadState(slot: 1); gamepads.pulse(intensity: 0.45) }
        }
    }

    func beginEditingControls() {
        controller.releaseAll()
        editor = LayoutEditor(system: game.system, gameID: game.id, store: layouts)
        menuOpen = false          // stays paused while editing
    }

    func endEditingControls() {
        editor = nil
        resume()
    }

    func closeControllers() {
        gamepads.saveMappings()
        showingControllers = false
        resume()
    }

    func startOver() {
        try? FileManager.default.removeItem(at: store.stateURL(for: game, slot: 0))
        reset()
    }

    func refreshSlots() {
        var thumbs: [Int: UIImage] = [:]
        var dates: [Int: Date] = [:]
        for slot in 0...4 {
            let url = store.stateURL(for: game, slot: slot)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let date = attrs[.modificationDate] as? Date {
                dates[slot] = date
                thumbs[slot] = UIImage(contentsOfFile: store.thumbnailURL(for: game, slot: slot).path)
            }
        }
        slotThumbs = thumbs
        slotDates = dates
    }

    private func currentThumbnail() -> Data? {
        guard let snap = session.frames.snapshot() else { return nil }
        var px = snap.pixels
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let image: CGImage? = px.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: snap.width, height: snap.height, bitsPerComponent: 8,
                      bytesPerRow: snap.width * 4, space: cs, bitmapInfo: info)?.makeImage()
        }
        guard let image else { return nil }
        return UIImage(cgImage: image).pngData()
    }

    func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled { self?.toast = nil }
        }
    }
}
