import CoreKit
import Foundation
import Testing

@Suite struct InputMappingTests {
    private let still = (x: 0.0, y: 0.0)

    private func press(_ inputs: Set<PhysicalInput>, _ system: SystemID = .snes,
                       stick: (x: Double, y: Double) = (0, 0)) -> (buttons: InputState, hotkeys: Set<Hotkey>) {
        InputMapper.resolve(pressed: inputs, stick: stick, mapping: .defaults(for: system))
    }

    // MARK: defaults

    @Test(arguments: SystemID.allCases)
    func everySystemHasDirectionsStartSelectAndHotkeys(_ system: SystemID) {
        let m = ControllerMapping.defaults(for: system)
        #expect(m.buttons[.dpadUp] == .up)
        #expect(m.buttons[.dpadDown] == .down)
        #expect(m.buttons[.dpadLeft] == .left)
        #expect(m.buttons[.dpadRight] == .right)
        #expect(m.buttons[.buttonMenu] == .start)
        #expect(m.buttons[.buttonOptions] == .select)
        #expect(m.buttons[.buttonHome] == nil)
        #expect(m.stickAsDpad)
        #expect(m.stickDeadZone == 0.35)
        #expect(m.stickDiagonalDegrees == 45)
        #expect(Set(m.hotkeys.map(\.hotkey)) == Set(Hotkey.allCases))
        #expect(m.hotkeys.contains(HotkeyBinding(trigger: .buttonHome, hotkey: .menu)))
        #expect(m.hotkeys.contains(HotkeyBinding(modifier: .buttonOptions, trigger: .leftShoulder, hotkey: .loadState)))
        #expect(m.hotkeys.contains(HotkeyBinding(modifier: .buttonOptions, trigger: .rightShoulder, hotkey: .saveState)))
        #expect(m.hotkeys.contains(HotkeyBinding(modifier: .buttonOptions, trigger: .leftTrigger, hotkey: .rewind)))
        #expect(m.hotkeys.contains(HotkeyBinding(modifier: .buttonOptions, trigger: .rightTrigger, hotkey: .fastForward)))
        // No default uses the triggers for buttons, so they work alone too.
        #expect(m.buttons[.leftTrigger] == nil && m.buttons[.rightTrigger] == nil)
        #expect(m.hotkeys.contains(HotkeyBinding(trigger: .leftTrigger, hotkey: .rewind)))
        #expect(m.hotkeys.contains(HotkeyBinding(trigger: .rightTrigger, hotkey: .fastForward)))
        let k = KeyboardMapping.defaults(for: system)
        #expect(Set(k.hotkeys.values) == Set(Hotkey.allCases))
    }

    @Test(arguments: [SystemID.nes, .gb, .gbc])
    func nintendoTwoButtonDefaults(_ system: SystemID) {
        let m = ControllerMapping.defaults(for: system)
        #expect(m.buttons[.buttonA] == .b)     // south
        #expect(m.buttons[.buttonB] == .a)     // east
        #expect(m.buttons[.buttonX] == nil && m.buttons[.buttonY] == nil)
        #expect(m.buttons[.leftShoulder] == nil && m.buttons[.rightShoulder] == nil)
    }

    @Test func gbaDefaults() {
        let m = ControllerMapping.defaults(for: .gba)
        #expect(m.buttons[.buttonA] == .b)
        #expect(m.buttons[.buttonB] == .a)
        #expect(m.buttons[.leftShoulder] == .l)
        #expect(m.buttons[.rightShoulder] == .r)
    }

    @Test func snesDefaults() {
        let m = ControllerMapping.defaults(for: .snes)
        #expect(m.buttons[.buttonA] == .b)
        #expect(m.buttons[.buttonB] == .a)
        #expect(m.buttons[.buttonX] == .y)
        #expect(m.buttons[.buttonY] == .x)
        #expect(m.buttons[.leftShoulder] == .l)
        #expect(m.buttons[.rightShoulder] == .r)
    }

    @Test func megaDriveDefaults() {
        // West/south/east = A/B/C; LB/north/RB = X/Y/Z (InputState: A=.y B=.b C=.a X=.x Y=.l Z=.r).
        let m = ControllerMapping.defaults(for: .md)
        #expect(m.buttons[.buttonX] == .y)
        #expect(m.buttons[.buttonA] == .b)
        #expect(m.buttons[.buttonB] == .a)
        #expect(m.buttons[.leftShoulder] == .x)
        #expect(m.buttons[.buttonY] == .l)
        #expect(m.buttons[.rightShoulder] == .r)
        // Every 6-button pad button is reachable exactly once.
        let face: [PhysicalInput] = [.buttonX, .buttonA, .buttonB, .leftShoulder, .buttonY, .rightShoulder]
        #expect(face.reduce(InputState()) { $0.union(m.buttons[$1]!) } == [.a, .b, .x, .y, .l, .r])
    }

    // MARK: resolution

    @Test func plainPresses() {
        #expect(press([.buttonA, .dpadLeft]).buttons == [.b, .left])
        #expect(press([.buttonA, .dpadLeft]).hotkeys.isEmpty)
        #expect(press([]).buttons.isEmpty)
        // Options + Menu is the menu combo (Home is often reserved by iOS): the game sees neither.
        #expect(press([.buttonMenu, .buttonOptions]).buttons.isEmpty)
        #expect(press([.buttonMenu, .buttonOptions]).hotkeys == [.menu])
        #expect(press([.buttonMenu]).buttons == [.start])
        #expect(press([.leftThumbstickButton, .rightThumbstickButton]).buttons.isEmpty)   // unmapped
    }

    @Test func homeOpensMenuWithoutPressingAnything() {
        let r = press([.buttonHome, .buttonA])
        #expect(r.hotkeys == [.menu])
        #expect(r.buttons == .b)
    }

    @Test func comboSuppressesItsButtons() {
        // Options + LB: load state, and neither Select nor L reaches the game.
        var r = press([.buttonOptions, .leftShoulder])
        #expect(r.hotkeys == [.loadState])
        #expect(r.buttons.isEmpty)
        r = press([.buttonOptions, .rightShoulder, .buttonA])
        #expect(r.hotkeys == [.saveState])
        #expect(r.buttons == .b)                       // unrelated buttons still work
        // Options alone is Select; LB alone is L.
        #expect(press([.buttonOptions]).buttons == .select)
        #expect(press([.leftShoulder]).buttons == .l)
        #expect(press([.buttonOptions]).hotkeys.isEmpty)
    }

    @Test func comboBeatsTriggerAloneBindingOnSameTrigger() {
        var m = ControllerMapping.defaults(for: .snes)
        m.hotkeys.append(HotkeyBinding(trigger: .rightShoulder, hotkey: .menu))
        let combo = InputMapper.resolve(pressed: [.buttonOptions, .rightShoulder], stick: still, mapping: m)
        #expect(combo.hotkeys == [.saveState])
        #expect(combo.buttons.isEmpty)
        let alone = InputMapper.resolve(pressed: [.rightShoulder], stick: still, mapping: m)
        #expect(alone.hotkeys == [.menu])
        #expect(alone.buttons.isEmpty)                 // R is consumed by its own hotkey
    }

    @Test func triggersAloneAndWithModifier() {
        #expect(press([.leftTrigger]).hotkeys == [.rewind])
        #expect(press([.rightTrigger]).hotkeys == [.fastForward])
        let r = press([.buttonOptions, .rightTrigger])
        #expect(r.hotkeys == [.fastForward])
        #expect(r.buttons.isEmpty)
        #expect(press([.leftTrigger, .rightTrigger]).hotkeys == [.rewind, .fastForward])
    }

    @Test func oppositeDirectionsCancel() {
        #expect(press([.dpadLeft, .dpadRight, .dpadUp]).buttons == .up)
        #expect(press([.dpadUp, .dpadDown]).buttons.isEmpty)
        #expect(press([.dpadUp], stick: (0, -1)).buttons.isEmpty)   // d-pad up + stick down
    }

    // MARK: stick

    @Test func stickDeadZone() {
        #expect(press([], stick: (0.2, 0.2)).buttons.isEmpty)        // |v| ≈ 0.28 < 0.35
        #expect(press([], stick: (0.34, 0)).buttons.isEmpty)
        #expect(press([], stick: (0.36, 0)).buttons == .right)
        #expect(press([], stick: (0, 0)).buttons.isEmpty)
        var m = ControllerMapping.defaults(for: .nes)
        m.stickDeadZone = 0.1
        #expect(InputMapper.resolve(pressed: [], stick: (0.2, 0), mapping: m).buttons == .right)
        m.stickDeadZone = 5                                          // clamped to 0.9
        #expect(InputMapper.resolve(pressed: [], stick: (0.95, 0), mapping: m).buttons == .right)
        #expect(InputMapper.resolve(pressed: [], stick: (0.85, 0), mapping: m).buttons.isEmpty)
        m.stickAsDpad = false
        #expect(InputMapper.resolve(pressed: [], stick: (1, 0), mapping: m).buttons.isEmpty)
    }

    private func at(_ degrees: Double, diagonal: Double = 45) -> InputState {
        let r = degrees * .pi / 180
        return InputMapper.stickDirections(x: cos(r), y: sin(r), deadZone: 0.35, diagonalDegrees: diagonal)
    }

    @Test func stickEightWay() {
        #expect(at(0) == .right)
        #expect(at(90) == .up)
        #expect(at(180) == .left)
        #expect(at(270) == .down)
        #expect(at(45) == [.up, .right])
        #expect(at(135) == [.up, .left])
        #expect(at(225) == [.down, .left])
        #expect(at(315) == [.down, .right])
        // Sector edges at 22.5 degrees from each diagonal.
        #expect(at(22) == .right)
        #expect(at(23) == [.up, .right])
        #expect(at(67) == [.up, .right])
        #expect(at(68) == .up)
        #expect(at(-10) == .right)
        #expect(at(350) == .right)
        #expect(at(205) == [.down, .left])
        #expect(at(200) == .left)
        #expect(at(190) == .left)
    }

    @Test func stickDiagonalWidth() {
        // Narrow diagonals: 20 degree sectors.
        #expect(at(30, diagonal: 20) == .right)
        #expect(at(40, diagonal: 20) == [.up, .right])
        #expect(at(60, diagonal: 20) == .up)
        // Zero: 4-way only.
        #expect(at(45, diagonal: 0) == .up || at(45, diagonal: 0) == .right)
        #expect(at(44, diagonal: 0) == .right)
        #expect(at(46, diagonal: 0) == .up)
        // Wide: 80 degree sectors leave only ±5 degrees around each axis.
        #expect(at(10, diagonal: 80) == [.up, .right])
        #expect(at(3, diagonal: 80) == .right)
        #expect(at(100, diagonal: 80) == [.up, .left])
    }

    @Test func stickYIsUp() {
        #expect(press([], stick: (0, 1)).buttons == .up)
        #expect(press([], stick: (0, -1)).buttons == .down)
        #expect(press([], stick: (-1, 0)).buttons == .left)
        #expect(InputMapper.stickDirections(x: .nan, y: 1, deadZone: 0.35, diagonalDegrees: 45).isEmpty)
    }

    // MARK: remapping

    @Test func remapAButton() {
        var m = ControllerMapping.defaults(for: .nes)
        m.bind(.buttonX, to: .b)                      // second B
        m.bind(.buttonY, to: [.a, .b])                // one button presses both
        m.bind(.buttonA, to: [])                      // unmapped
        #expect(m.buttons[.buttonA] == nil)
        let r = InputMapper.resolve(pressed: [.buttonA], stick: still, mapping: m)
        #expect(r.buttons.isEmpty)
        #expect(InputMapper.resolve(pressed: [.buttonX], stick: still, mapping: m).buttons == .b)
        #expect(InputMapper.resolve(pressed: [.buttonY], stick: still, mapping: m).buttons == [.a, .b])
        #expect(m.inputs(pressing: .b) == [.buttonX, .buttonY])
        #expect(m.inputs(pressing: .a) == [.buttonB, .buttonY])
        #expect(m != ControllerMapping.defaults(for: .nes))
    }

    @Test func remappedHotkey() {
        var m = ControllerMapping.defaults(for: .snes)
        m.hotkeys = [HotkeyBinding(modifier: .leftThumbstickButton, trigger: .buttonA, hotkey: .saveState)]
        var r = InputMapper.resolve(pressed: [.leftThumbstickButton, .buttonA], stick: still, mapping: m)
        #expect(r.hotkeys == [.saveState])
        #expect(r.buttons.isEmpty)
        r = InputMapper.resolve(pressed: [.buttonHome, .leftTrigger], stick: still, mapping: m)
        #expect(r.hotkeys.isEmpty)                     // old bindings gone
    }

    // MARK: Codable

    @Test(arguments: SystemID.allCases)
    func codableRoundTrip(_ system: SystemID) throws {
        var m = ControllerMapping.defaults(for: system)
        m.stickDeadZone = 0.2
        m.stickDiagonalDegrees = 30
        m.bind(.rightThumbstickButton, to: [.a, .start])
        let data = try JSONEncoder().encode(m)
        #expect(try JSONDecoder().decode(ControllerMapping.self, from: data) == m)
        let k = KeyboardMapping.defaults(for: system)
        #expect(try JSONDecoder().decode(KeyboardMapping.self, from: try JSONEncoder().encode(k)) == k)
    }

    @Test func codableFormIsReadableAndTolerant() throws {
        let m = ControllerMapping(buttons: [.buttonA: [.b]], hotkeys: [HotkeyBinding(trigger: .buttonHome, hotkey: .menu)])
        let json = try #require(String(data: try JSONEncoder().encode(m), encoding: .utf8))
        #expect(json.contains("\"buttonA\""))           // keyed by name, not an array of pairs
        // Missing stick fields decode to defaults.
        let old = #"{"buttons":{"dpadUp":1},"hotkeys":[{"trigger":"buttonHome","hotkey":"menu"}]}"#
        let decoded = try JSONDecoder().decode(ControllerMapping.self, from: Data(old.utf8))
        #expect(decoded.buttons == [.dpadUp: .up])
        #expect(decoded.hotkeys == [HotkeyBinding(trigger: .buttonHome, hotkey: .menu)])
        #expect(decoded.stickAsDpad && decoded.stickDeadZone == 0.35 && decoded.stickDiagonalDegrees == 45)
    }

    // MARK: keyboard

    private func keys(_ k: Set<Int>, _ system: SystemID) -> (buttons: InputState, hotkeys: Set<Hotkey>) {
        InputMapper.resolve(keys: k, mapping: .defaults(for: system))
    }

    @Test func keyboardDefaults() {
        #expect(keys([KeyCode.upArrow, KeyCode.rightArrow], .nes).buttons == [.up, .right])
        #expect(keys([KeyCode.leftArrow, KeyCode.rightArrow], .nes).buttons.isEmpty)
        #expect(keys([KeyCode.z], .nes).buttons == .b)
        #expect(keys([KeyCode.x], .gb).buttons == .a)
        #expect(keys([KeyCode.returnKey, KeyCode.rightShift], .gbc).buttons == [.start, .select])
        #expect(keys([KeyCode.a, KeyCode.s], .nes).buttons.isEmpty)
        #expect(keys([KeyCode.q, KeyCode.e], .gba).buttons == [.l, .r])
        #expect(keys([KeyCode.a], .snes).buttons == .y)
        #expect(keys([KeyCode.s], .snes).buttons == .x)
        #expect(keys([KeyCode.q, KeyCode.e], .snes).buttons == [.l, .r])
        // Mega Drive: Z X C = A B C, A S D = X Y Z.
        #expect(keys([KeyCode.z], .md).buttons == .y)
        #expect(keys([KeyCode.x], .md).buttons == .b)
        #expect(keys([KeyCode.c], .md).buttons == .a)
        #expect(keys([KeyCode.a], .md).buttons == .x)
        #expect(keys([KeyCode.s], .md).buttons == .l)
        #expect(keys([KeyCode.d], .md).buttons == .r)
    }

    @Test func keyboardHotkeys() {
        #expect(keys([KeyCode.f1], .snes).hotkeys == [.saveState])
        #expect(keys([KeyCode.f4], .snes).hotkeys == [.loadState])
        #expect(keys([KeyCode.tab], .snes).hotkeys == [.fastForward])
        #expect(keys([KeyCode.backspace], .snes).hotkeys == [.rewind])
        #expect(keys([KeyCode.escape], .snes).hotkeys == [.menu])
        let r = keys([KeyCode.tab, KeyCode.z, 0x7F], .nes)    // unmapped key ignored
        #expect(r.hotkeys == [.fastForward])
        #expect(r.buttons == .b)
    }

    @Test func keyboardRemap() {
        var k = KeyboardMapping.defaults(for: .nes)
        k.bind(key: KeyCode.space, to: .a)
        k.bind(key: KeyCode.tab, to: .b)                     // a button on a hotkey key replaces the hotkey
        #expect(InputMapper.resolve(keys: [KeyCode.space, KeyCode.tab], mapping: k).buttons == [.a, .b])
        #expect(InputMapper.resolve(keys: [KeyCode.tab], mapping: k).hotkeys.isEmpty)
        k.bind(key: KeyCode.f2, to: .saveState)              // moves save state off F1
        #expect(InputMapper.resolve(keys: [KeyCode.f1], mapping: k).hotkeys.isEmpty)
        #expect(InputMapper.resolve(keys: [KeyCode.f2], mapping: k).hotkeys == [.saveState])
        k.bind(key: KeyCode.z, to: .menu)                    // a hotkey on a button key clears the button
        let z = InputMapper.resolve(keys: [KeyCode.z], mapping: k)
        #expect(z.buttons.isEmpty && z.hotkeys == [.menu])
    }
}
