import CoreHaptics
import CoreKit
import GameController
import Observation

/// Saved controller and keyboard mappings, one of each per system (UserDefaults, JSON).
@MainActor
enum MappingStore {
    static func controller(for system: SystemID) -> ControllerMapping {
        guard let d = UserDefaults.standard.data(forKey: "mapping.pad.\(system.rawValue)"),
              let m = try? JSONDecoder().decode(ControllerMapping.self, from: d) else { return .defaults(for: system) }
        return m
    }

    static func save(_ m: ControllerMapping, for system: SystemID) {
        if let d = try? JSONEncoder().encode(m) { UserDefaults.standard.set(d, forKey: "mapping.pad.\(system.rawValue)") }
    }

    static func keyboard(for system: SystemID) -> KeyboardMapping {
        guard let d = UserDefaults.standard.data(forKey: "mapping.keys.\(system.rawValue)"),
              let m = try? JSONDecoder().decode(KeyboardMapping.self, from: d) else { return .defaults(for: system) }
        return m
    }

    static func save(_ m: KeyboardMapping, for system: SystemID) {
        if let d = try? JSONEncoder().encode(m) { UserDefaults.standard.set(d, forKey: "mapping.keys.\(system.rawValue)") }
    }

    static func reset(_ system: SystemID) {
        UserDefaults.standard.removeObject(forKey: "mapping.pad.\(system.rawValue)")
        UserDefaults.standard.removeObject(forKey: "mapping.keys.\(system.rawValue)")
    }
}

/// Bluetooth / MFi / USB controllers and hardware keyboards, first-class:
/// hot-plug with a toast, players assigned by connection order (changeable), per-system remappable
/// buttons and hotkey combos (via CoreKit's `InputMapper`), the left stick as a D-pad, and a short
/// rumble on save/load where the controller supports haptics.
@MainActor
@Observable
final class GamepadHub {
    struct Pad: Identifiable, Equatable {
        let id: ObjectIdentifier
        var name: String
        /// 0 = player 1, 1 = player 2, nil = ignored.
        var player: Int?
        var hasHaptics: Bool
    }

    private(set) var pads: [Pad] = []
    private(set) var keyboardConnected = false
    var mapping: ControllerMapping
    var keyboardMapping: KeyboardMapping
    /// Set by the remapping screen: the next physical press (or key) is reported here instead of played.
    var capture: ((Set<PhysicalInput>) -> Void)?
    var captureKey: ((Int) -> Void)?

    var isConnected: Bool { pads.contains { $0.player != nil } }

    @ObservationIgnored var onHotkey: ((Hotkey, Bool) -> Void)?
    @ObservationIgnored var onConnection: ((String, Bool) -> Void)?
    @ObservationIgnored let system: SystemID
    @ObservationIgnored var players = 1
    @ObservationIgnored private weak var latch: InputLatch?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var controllers: [ObjectIdentifier: GCController] = [:]
    @ObservationIgnored private var activeHotkeys: [ObjectIdentifier: Set<Hotkey>] = [:]
    @ObservationIgnored private var keysDown: Set<Int> = []
    @ObservationIgnored private var keyHotkeys: Set<Hotkey> = []
    @ObservationIgnored private var capturePressed: Set<PhysicalInput> = []
    @ObservationIgnored private var hapticEngines: [ObjectIdentifier: CHHapticEngine] = [:]

    init(system: SystemID) {
        self.system = system
        // Known before the core starts, so a second pad already paired is given player 2 at once.
        players = [.nes, .snes, .md, .n64].contains(system) ? 2 : 1
        mapping = MappingStore.controller(for: system)
        keyboardMapping = MappingStore.keyboard(for: system)
    }

    func attach(to latch: InputLatch) {
        self.latch = latch
        let c = NotificationCenter.default
        observers.append(c.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            nonisolated(unsafe) let pad = n.object as? GCController   // delivered on the main queue
            MainActor.assumeIsolated { if let pad { self?.connect(pad, announce: true) } }
        })
        observers.append(c.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] n in
            nonisolated(unsafe) let pad = n.object as? GCController   // delivered on the main queue
            MainActor.assumeIsolated { if let pad { self?.disconnect(pad) } }
        })
        observers.append(c.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.attachKeyboard() }
        })
        observers.append(c.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keyboardGone() }
        })
        for pad in GCController.controllers() { connect(pad, announce: false) }
        attachKeyboard()
        #if DEBUG
        // -fakeController YES: pretend a pad is connected (the simulator can't pair a real one).
        if UserDefaults.standard.bool(forKey: "fakeController") {
            pads.append(Pad(id: ObjectIdentifier(self), name: "Test Controller", player: 0, hasHaptics: false))
        }
        #endif
    }

    func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        for pad in controllers.values { pad.extendedGamepad?.valueChangedHandler = nil }
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
        hapticEngines.values.forEach { $0.stop() }
        latch?.controller.store(0, ordering: .relaxed)
        latch?.player2.store(0, ordering: .relaxed)
        latch?.keyboard.store(0, ordering: .relaxed)
        latch?.padStick.store(0, ordering: .relaxed)
        latch?.player2Stick.store(0, ordering: .relaxed)
    }

    // MARK: connection and players

    private func connect(_ pad: GCController, announce: Bool) {
        guard pad.extendedGamepad != nil else { return }
        let id = ObjectIdentifier(pad)
        guard controllers[id] == nil else { return }
        controllers[id] = pad
        let used = Set(pads.compactMap(\.player))
        let player = (0..<max(1, players)).first { !used.contains($0) }
        let name = pad.vendorName ?? "Controller"
        pads.append(Pad(id: id, name: name, player: player, hasHaptics: pad.haptics != nil))
        pad.playerIndex = player.map { GCControllerPlayerIndex(rawValue: $0) ?? .indexUnset } ?? .indexUnset
        pad.extendedGamepad?.valueChangedHandler = { [weak self] g, _ in
            MainActor.assumeIsolated { self?.read(g, from: id) }
        }
        if announce { onConnection?(name, true) }
    }

    private func disconnect(_ pad: GCController) {
        let id = ObjectIdentifier(pad)
        guard let i = pads.firstIndex(where: { $0.id == id }) else { return }
        let p = pads.remove(at: i)
        controllers[id] = nil
        hapticEngines[id]?.stop()
        hapticEngines[id] = nil
        store(player: p.player, bits: [])
        if let held = activeHotkeys.removeValue(forKey: id) { for h in held { onHotkey?(h, false) } }
        modifierSince[id] = nil; modifierUsed[id] = nil; tapUntil[id] = nil; lastState[id] = nil
        if capture != nil {           // the pad being remapped went away
            capture = nil
            capturePressed = []
        }
        onConnection?(p.name, false)
    }

    /// Reassigns a controller (the other one on that player is moved to the freed slot).
    func assign(_ padID: ObjectIdentifier, to player: Int?) {
        guard let i = pads.firstIndex(where: { $0.id == padID }) else { return }
        let old = pads[i].player
        if let player, let j = pads.firstIndex(where: { $0.player == player && $0.id != padID }) {
            pads[j].player = old
            controllers[pads[j].id]?.playerIndex = old.map { GCControllerPlayerIndex(rawValue: $0) ?? .indexUnset } ?? .indexUnset
        }
        pads[i].player = player
        controllers[padID]?.playerIndex = player.map { GCControllerPlayerIndex(rawValue: $0) ?? .indexUnset } ?? .indexUnset
        latch?.controller.store(0, ordering: .relaxed)
        latch?.player2.store(0, ordering: .relaxed)
    }

    private func store(player: Int?, bits: InputState) {
        switch player {
        case 0?: latch?.controller.store(bits.rawValue, ordering: .relaxed)
        case 1?: latch?.player2.store(bits.rawValue, ordering: .relaxed)
        default: break
        }
    }

    /// The left stick as an analog stick (Nintendo 64): a radial dead zone, rescaled so the
    /// output still starts from zero at its edge and reaches full deflection at the rim.
    nonisolated static func shapedStick(_ stick: (x: Double, y: Double), deadZone: Double) -> AnalogStick {
        guard stick.x.isFinite, stick.y.isFinite else { return .centre }
        let zone = min(max(deadZone, 0), 0.9)
        let m = (stick.x * stick.x + stick.y * stick.y).squareRoot()
        guard m > zone, m > 0 else { return .centre }
        let scaled = min(1, (m - zone) / (1 - zone))
        return AnalogStick(x: stick.x / m * scaled, y: stick.y / m * scaled)
    }

    private func storeStick(player: Int?, _ s: AnalogStick) {
        switch player {
        case 0?: latch?.padStick.store(InputLatch.pack(s), ordering: .relaxed)
        case 1?: latch?.player2Stick.store(InputLatch.pack(s), ordering: .relaxed)
        default: break
        }
    }

    // MARK: reading

    static func pressed(_ g: GCExtendedGamepad) -> Set<PhysicalInput> {
        var s: Set<PhysicalInput> = []
        if g.buttonA.isPressed { s.insert(.buttonA) }
        if g.buttonB.isPressed { s.insert(.buttonB) }
        if g.buttonX.isPressed { s.insert(.buttonX) }
        if g.buttonY.isPressed { s.insert(.buttonY) }
        if g.leftShoulder.isPressed { s.insert(.leftShoulder) }
        if g.rightShoulder.isPressed { s.insert(.rightShoulder) }
        if g.leftTrigger.isPressed { s.insert(.leftTrigger) }
        if g.rightTrigger.isPressed { s.insert(.rightTrigger) }
        if g.dpad.up.isPressed { s.insert(.dpadUp) }
        if g.dpad.down.isPressed { s.insert(.dpadDown) }
        if g.dpad.left.isPressed { s.insert(.dpadLeft) }
        if g.dpad.right.isPressed { s.insert(.dpadRight) }
        if g.leftThumbstickButton?.isPressed == true { s.insert(.leftThumbstickButton) }
        if g.rightThumbstickButton?.isPressed == true { s.insert(.rightThumbstickButton) }
        if g.buttonMenu.isPressed { s.insert(.buttonMenu) }
        if g.buttonOptions?.isPressed == true { s.insert(.buttonOptions) }
        if g.buttonHome?.isPressed == true { s.insert(.buttonHome) }
        s.formUnion(InputMapper.rightStickInputs(x: Double(g.rightThumbstick.xAxis.value),
                                                 y: Double(g.rightThumbstick.yAxis.value)))
        return s
    }

    private func read(_ g: GCExtendedGamepad, from id: ObjectIdentifier) {
        let pressed = Self.pressed(g)
        if let capture {
            // Remapping: report a press (or a held combo) once all buttons are released again.
            if pressed.count > capturePressed.count { capturePressed = pressed }
            if pressed.isEmpty && !capturePressed.isEmpty {
                let c = capturePressed
                capturePressed = []
                self.capture = nil
                capture(c)
            }
            return
        }
        apply(id, pressed: pressed, stick: (x: Double(g.leftThumbstick.xAxis.value), y: Double(g.leftThumbstick.yAxis.value)))
    }

    /// A button that is also a hotkey modifier (Options → Select by default) waits briefly before
    /// reaching the game: if a combo follows, the game never sees it; a quick tap is still sent
    /// on release, and holding it on its own passes through after the wait.
    static let modifierWait: TimeInterval = 0.18
    @ObservationIgnored private var modifierSince: [ObjectIdentifier: [PhysicalInput: Date]] = [:]
    @ObservationIgnored private var modifierUsed: [ObjectIdentifier: Set<PhysicalInput>] = [:]
    @ObservationIgnored private var tapUntil: [ObjectIdentifier: [PhysicalInput: Date]] = [:]
    @ObservationIgnored private var lastState: [ObjectIdentifier: (Set<PhysicalInput>, (x: Double, y: Double))] = [:]

    func apply(_ id: ObjectIdentifier, pressed: Set<PhysicalInput>, stick: (x: Double, y: Double), now: Date = Date()) {
        lastState[id] = (pressed, stick)
        var r = InputMapper.resolve(pressed: pressed, stick: stick, mapping: mapping)
        let modifiers = Set(mapping.hotkeys.compactMap(\.modifier)).filter { mapping.buttons[$0] != nil }
        var since = modifierSince[id] ?? [:]
        var used = modifierUsed[id] ?? []
        var taps = tapUntil[id] ?? [:]
        var recheck: TimeInterval?
        if !r.hotkeys.isEmpty { used.formUnion(modifiers.intersection(pressed)) }
        for m in modifiers {
            if pressed.contains(m) {
                if since[m] == nil { since[m] = now }
                let held = now.timeIntervalSince(since[m]!)
                if used.contains(m) || held < Self.modifierWait {
                    r.buttons.subtract(mapping.buttons[m] ?? [])
                    if !used.contains(m) { recheck = min(recheck ?? .infinity, Self.modifierWait - held + 0.01) }
                }
            } else if let start = since.removeValue(forKey: m) {
                if !used.contains(m) && now.timeIntervalSince(start) < Self.modifierWait {
                    taps[m] = now.addingTimeInterval(0.07)          // a quick tap: send it now, briefly
                }
                used.remove(m)
            }
        }
        for (m, until) in taps {
            if until > now {
                r.buttons.formUnion(mapping.buttons[m] ?? [])
                recheck = min(recheck ?? .infinity, until.timeIntervalSince(now) + 0.01)
            } else {
                taps[m] = nil
            }
        }
        modifierSince[id] = since
        modifierUsed[id] = used
        tapUntil[id] = taps
        let player = pads.first { $0.id == id }?.player
        store(player: player, bits: r.buttons.sanitised)
        if !mapping.stickAsDpad { storeStick(player: player, Self.shapedStick(stick, deadZone: mapping.stickDeadZone)) }
        let before = activeHotkeys[id] ?? []
        for h in r.hotkeys.subtracting(before) { onHotkey?(h, true) }
        for h in before.subtracting(r.hotkeys) { onHotkey?(h, false) }
        activeHotkeys[id] = r.hotkeys
        if let recheck, recheck.isFinite {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(recheck))
                guard let self, let state = self.lastState[id], self.capture == nil else { return }
                self.apply(id, pressed: state.0, stick: state.1)
            }
        }
    }

    private func keyboardGone() {
        keyboardConnected = false
        keysDown.removeAll()
        for h in keyHotkeys { onHotkey?(h, false) }
        keyHotkeys = []
        latch?.keyboard.store(0, ordering: .relaxed)
    }

    var isCapturing: Bool { capture != nil || captureKey != nil }

    #if DEBUG
    /// Unit tests: drive `apply` without real hardware.
    func testPad(latch: InputLatch, player: Int = 0) -> ObjectIdentifier {
        self.latch = latch
        let id = ObjectIdentifier(latch)
        pads.append(Pad(id: id, name: "Test", player: player, hasHaptics: false))
        return id
    }
    #endif

    private func attachKeyboard() {
        guard let kb = GCKeyboard.coalesced?.keyboardInput else { return }
        keyboardConnected = true
        kb.keyChangedHandler = { [weak self] _, _, key, pressed in
            let code = key.rawValue
            MainActor.assumeIsolated { self?.key(code, pressed: pressed) }
        }
    }

    private func key(_ code: Int, pressed: Bool) {
        if pressed, let captureKey {
            self.captureKey = nil
            captureKey(code)
            return
        }
        if pressed { keysDown.insert(code) } else { keysDown.remove(code) }
        let r = InputMapper.resolve(keys: keysDown, mapping: keyboardMapping)
        latch?.keyboard.store(r.buttons.rawValue, ordering: .relaxed)
        for h in r.hotkeys.subtracting(keyHotkeys) { onHotkey?(h, true) }
        for h in keyHotkeys.subtracting(r.hotkeys) { onHotkey?(h, false) }
        keyHotkeys = r.hotkeys
    }

    // MARK: mapping edits

    /// Starts remapping: nothing reaches the game until the capture finishes.
    func beginCapture(_ handler: @escaping (Set<PhysicalInput>) -> Void) {
        latch?.controller.store(0, ordering: .relaxed)
        latch?.player2.store(0, ordering: .relaxed)
        capturePressed = []
        capture = handler
    }

    func saveMappings() {
        MappingStore.save(mapping, for: system)
        MappingStore.save(keyboardMapping, for: system)
    }

    func resetMappings() {
        MappingStore.reset(system)
        mapping = .defaults(for: system)
        keyboardMapping = .defaults(for: system)
    }

    // MARK: haptics

    /// A short, crisp pulse on every connected controller that supports haptics.
    /// Off when Settings turns haptics off.
    var rumbleEnabled = true

    func pulse(intensity: Float = 0.7) {
        guard rumbleEnabled else { return }
        for (id, pad) in controllers {
            guard let haptics = pad.haptics else { continue }
            let engine = hapticEngines[id] ?? haptics.createEngine(withLocality: .default)
            hapticEngines[id] = engine
            guard let engine else { continue }
            do {
                try engine.start()
                let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8),
                ], relativeTime: 0)
                let player = try engine.makePlayer(with: try CHHapticPattern(events: [event], parameters: []))
                try player.start(atTime: CHHapticTimeImmediate)
            } catch {}
        }
    }
}
