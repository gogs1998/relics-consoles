import CoreKit
@testable import DuoEmulator
import Foundation
import Testing

/// The physical-controller path, driven without hardware (the simulator can't pair a pad).
@MainActor
@Suite struct ControllerTests {
    private func bits(_ latch: InputLatch, player: Int = 0) -> InputState {
        InputState(rawValue: player == 0 ? latch.controller.load(ordering: .relaxed) : latch.player2.load(ordering: .relaxed))
    }

    @Test func buttonsReachTheRightPlayer() {
        let hub = GamepadHub(system: .snes)
        let latch = InputLatch()
        let p1 = hub.testPad(latch: latch, player: 0)
        hub.apply(p1, pressed: [.buttonA, .dpadLeft], stick: (0, 0))
        #expect(bits(latch) == [.b, .left])
        let p2 = ObjectIdentifier(hub)
        _ = p2
        #expect(bits(latch, player: 1).isEmpty)
    }

    @Test func stickIsADpadWithDeadZone() {
        let hub = GamepadHub(system: .nes)
        let latch = InputLatch()
        let id = hub.testPad(latch: latch)
        hub.apply(id, pressed: [], stick: (0.2, 0.1))
        #expect(bits(latch).isEmpty)
        hub.apply(id, pressed: [], stick: (0.9, 0.0))
        #expect(bits(latch) == [.right])
        hub.apply(id, pressed: [], stick: (0.7, 0.7))
        #expect(bits(latch) == [.right, .up])
    }

    @Test func modifierDoesNotLeakIntoCombos() {
        let hub = GamepadHub(system: .nes)
        let latch = InputLatch()
        let id = hub.testPad(latch: latch)
        var fired: [Hotkey] = []
        hub.onHotkey = { h, down in if down { fired.append(h) } }
        let t0 = Date()
        hub.apply(id, pressed: [.buttonOptions], stick: (0, 0), now: t0)
        #expect(bits(latch).isEmpty, "Options alone waits before sending Select")
        hub.apply(id, pressed: [.buttonOptions, .rightShoulder], stick: (0, 0), now: t0.addingTimeInterval(0.05))
        #expect(fired == [.saveState])
        #expect(bits(latch).isEmpty, "the combo never reaches the game")
        hub.apply(id, pressed: [], stick: (0, 0), now: t0.addingTimeInterval(0.1))
        #expect(bits(latch).isEmpty, "releasing after a combo sends no Select tap")
    }

    @Test func quickTapStillSendsSelect() {
        let hub = GamepadHub(system: .nes)
        let latch = InputLatch()
        let id = hub.testPad(latch: latch)
        let t0 = Date()
        hub.apply(id, pressed: [.buttonOptions], stick: (0, 0), now: t0)
        hub.apply(id, pressed: [], stick: (0, 0), now: t0.addingTimeInterval(0.05))
        #expect(bits(latch) == [.select])
    }

    @Test func holdingTheModifierAlonePassesThrough() {
        let hub = GamepadHub(system: .nes)
        let latch = InputLatch()
        let id = hub.testPad(latch: latch)
        let t0 = Date()
        hub.apply(id, pressed: [.buttonOptions], stick: (0, 0), now: t0)
        hub.apply(id, pressed: [.buttonOptions], stick: (0, 0), now: t0.addingTimeInterval(0.3))
        #expect(bits(latch) == [.select])
    }

    @Test func remappedButton() {
        let hub = GamepadHub(system: .gba)
        let latch = InputLatch()
        let id = hub.testPad(latch: latch)
        hub.mapping.bind(.buttonY, to: .a)
        hub.apply(id, pressed: [.buttonY], stick: (0, 0))
        #expect(bits(latch) == [.a])
    }

    @Test func settingsAndFilesAreClamped() {
        let s = ControlSettings(diagonalDegrees: 500, deadZone: -1, autoFireHz: 0, hapticLevel: .nan).sanitised
        #expect(s.diagonalDegrees == 60 && s.deadZone == 0.05 && s.autoFireHz == 2 && s.hapticLevel == 1)
        var bad = Control(kind: .face(.a, "A", .ember), frame: CGRect(x: -3, y: 2, width: 0, height: 9))
        bad.opacity = -5
        let l = SavedLayout(system: .nes, area: .table, gameID: nil, preset: .standard, controls: [bad], settings: ControlSettings()).sanitised
        let f = l.controls[0].frame
        #expect(f.minX >= 0 && f.maxX <= 1 && f.minY >= 0 && f.maxY <= 1 && f.width > 0)
        #expect(l.controls[0].opacity == 0.15)
    }

    @Test func secondPadGetsPlayerTwoOnTwoPortSystems() {
        #expect(GamepadHub(system: .snes).players == 2)
        #expect(GamepadHub(system: .gba).players == 1)
    }
}
