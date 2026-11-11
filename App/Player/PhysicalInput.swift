import CoreKit
import GameController
import Observation

/// MFi / Xbox / PlayStation controllers and hardware keyboards, written into the session's latch.
///
/// Mapping (data, so a remapping UI can edit it later): D-pad or left stick; south = B, east = A
/// (positional, like the original pads); shoulders L/R; Menu = Start; Options = Select.
/// Keyboard: arrows or WASD, Z = B, X = A, Return = Start, Right Shift = Select, Tab = fast-forward,
/// Backspace = rewind.
@MainActor
@Observable
final class PhysicalInput {
    private(set) var controllerName: String?
    var onFastForward: ((Bool) -> Void)?
    var onRewind: ((Bool) -> Void)?
    var onMenu: (() -> Void)?

    @ObservationIgnored private weak var latch: InputLatch?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var keysDown: Set<GCKeyCode> = []

    func attach(to latch: InputLatch) {
        self.latch = latch
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshKeyboard() }
        })
        refresh()
        refreshKeyboard()
    }

    func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        latch?.controller.store(0, ordering: .relaxed)
        latch?.keyboard.store(0, ordering: .relaxed)
        for c in GCController.controllers() { c.extendedGamepad?.valueChangedHandler = nil }
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
    }

    private func refresh() {
        let pad = GCController.controllers().first { $0.extendedGamepad != nil }
        controllerName = pad?.vendorName ?? (pad == nil ? nil : "Controller")
        guard let gamepad = pad?.extendedGamepad else {
            latch?.controller.store(0, ordering: .relaxed)
            return
        }
        gamepad.valueChangedHandler = { [weak self] g, _ in
            MainActor.assumeIsolated { self?.read(g) }
        }
    }

    private var lastFF = false
    private var lastRewind = false

    private func read(_ g: GCExtendedGamepad) {
        var s: InputState = []
        let dx = g.dpad.xAxis.value + g.leftThumbstick.xAxis.value
        let dy = g.dpad.yAxis.value + g.leftThumbstick.yAxis.value
        if dx < -0.4 { s.insert(.left) }
        if dx > 0.4 { s.insert(.right) }
        if dy > 0.4 { s.insert(.up) }
        if dy < -0.4 { s.insert(.down) }
        if g.buttonA.isPressed { s.insert(.b) }
        if g.buttonB.isPressed { s.insert(.a) }
        if g.buttonX.isPressed { s.insert(.y) }
        if g.buttonY.isPressed { s.insert(.x) }
        if g.leftShoulder.isPressed { s.insert(.l) }
        if g.rightShoulder.isPressed { s.insert(.r) }
        if g.buttonMenu.isPressed { s.insert(.start) }
        if g.buttonOptions?.isPressed == true { s.insert(.select) }
        latch?.controller.store(s.rawValue, ordering: .relaxed)
        let ff = g.rightTrigger.isPressed
        if ff != lastFF { lastFF = ff; onFastForward?(ff) }
        let rw = g.leftTrigger.isPressed
        if rw != lastRewind { lastRewind = rw; onRewind?(rw) }
        if g.buttonHome?.isPressed == true { onMenu?() }
    }

    private func refreshKeyboard() {
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = { [weak self] _, _, key, pressed in
            MainActor.assumeIsolated { self?.key(key, pressed: pressed) }
        }
    }

    private func key(_ key: GCKeyCode, pressed: Bool) {
        if pressed { keysDown.insert(key) } else { keysDown.remove(key) }
        if key == .tab { onFastForward?(pressed) }
        if key == .deleteOrBackspace { onRewind?(pressed) }
        if key == .escape && pressed { onMenu?() }
        var s: InputState = []
        let map: [(GCKeyCode, InputState)] = [
            (.upArrow, .up), (.downArrow, .down), (.leftArrow, .left), (.rightArrow, .right),
            (.keyW, .up), (.keyS, .down), (.keyA, .left), (.keyD, .right),
            (.keyZ, .b), (.keyX, .a), (.keyC, .y), (.keyV, .x), (.keyQ, .l), (.keyE, .r),
            (.returnOrEnter, .start), (.rightShift, .select),
        ]
        for (k, b) in map where keysDown.contains(k) { s.insert(b) }
        latch?.keyboard.store(s.rawValue, ordering: .relaxed)
    }
}
