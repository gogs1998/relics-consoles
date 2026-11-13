import CoreKit
@testable import DuoEmulator
import Foundation
import Testing

/// The Nintendo 64 standard layouts (every area, nothing overlapping or leaving its area, nothing
/// over the game in landscape), the touch stick's maths, and its settings surviving old files.
@MainActor
@Suite struct N64LayoutTests {
    private func checkTidy(_ controls: [Control], in size: CGSize, _ name: String) {
        let bounds = CGRect(origin: .zero, size: size)
        for c in controls {
            #expect(bounds.insetBy(dx: -0.5, dy: -0.5).contains(c.frame), "\(name): \(c.id) leaves its area \(c.frame)")
        }
        for (i, a) in controls.enumerated() {
            for b in controls.dropFirst(i + 1) {
                let round: (Control) -> Bool = { c in
                    switch c.kind { case .face, .stick, .cStick: true; default: false }
                }
                if round(a) && round(b) {
                    let d = hypot(a.frame.midX - b.frame.midX, a.frame.midY - b.frame.midY)
                    #expect(d >= (a.frame.width + b.frame.width) / 2 - 1, "\(name): \(a.id) overlaps \(b.id)")
                    continue
                }
                #expect(!a.frame.insetBy(dx: 1, dy: 1).intersects(b.frame.insetBy(dx: 1, dy: 1)),
                        "\(name): \(a.id) overlaps \(b.id)")
            }
        }
    }

    private func hasEverything(_ controls: [Control], _ name: String) {
        let pressable = controls.reduce(InputState()) { $0.union($1.buttons) }
        #expect(pressable.isSuperset(of: [.a, .b, .z, .l, .r, .start, .cUp, .cDown, .cLeft, .cRight]), "\(name)")
        #expect(controls.contains { $0.kind == .stick }, "\(name): no stick")
        #expect(controls.contains { $0.kind == .dpad }, "\(name): no D-pad")
    }

    @Test func deckLayoutsForPhonesAndTheDuoTable() {
        // portrait iPhones (small to large) and the Duo's bottom half
        for size in [CGSize(width: 367, height: 330), CGSize(width: 382, height: 440), CGSize(width: 422, height: 470),
                     CGSize(width: 384, height: 270), CGSize(width: 330, height: 250)] {
            for cStick in [false, true] {
                let c = N64Layout.camera(ControllerLayout.deck(size, system: .n64), cStick: cStick)
                checkTidy(c, in: size, "deck \(size) cStick \(cStick)")
                hasEverything(c, "deck \(size) cStick \(cStick)")
            }
        }
    }

    @Test func bookPages() {
        for size in [CGSize(width: 230, height: 100), CGSize(width: 260, height: 120), CGSize(width: 400, height: 150),
                     CGSize(width: 460, height: 200)] {
            let left = ControllerLayout.bookLeft(size, system: .n64)
            checkTidy(left, in: size, "book left \(size)")
            for cStick in [false, true] {
                let right = N64Layout.camera(ControllerLayout.bookRight(size, system: .n64), cStick: cStick)
                checkTidy(right, in: size, "book right \(size) cStick \(cStick)")
                hasEverything(left + right, "book \(size) cStick \(cStick)")
            }
        }
    }

    @Test func landscapeKeepsOffTheGame() {
        for (size, game) in [(CGSize(width: 852, height: 393), CGRect(x: 175, y: 8, width: 502, height: 377)),
                             (CGSize(width: 932, height: 430), CGRect(x: 189, y: 8, width: 553, height: 414)),
                             (CGSize(width: 667, height: 375), CGRect(x: 103, y: 8, width: 461, height: 359))] {
            for cStick in [false, true] {
                let c = N64Layout.camera(ControllerLayout.overlay(size, gameRect: game, system: .n64), cStick: cStick)
                checkTidy(c, in: size, "landscape \(size)")
                hasEverything(c, "landscape \(size)")
                for ctl in c { #expect(!ctl.frame.intersects(game), "landscape \(size): \(ctl.id) covers the game") }
            }
        }
    }

    /// The C buttons reach Apple's 44 pt minimum wherever the area has room for it (phones in
    /// portrait, the Duo table, ordinary landscape phones and roomy book pages), and are never
    /// smaller than they used to be.
    @Test func cButtonsAreBigEnough() {
        func cSize(_ list: [Control]) -> CGFloat { list.first(where: N64Layout.isCButton)?.frame.width ?? 0 }
        for size in [CGSize(width: 367, height: 330), CGSize(width: 382, height: 370), CGSize(width: 382, height: 440),
                     CGSize(width: 384, height: 270)] {
            #expect(cSize(ControllerLayout.deck(size, system: .n64)) >= 44, "deck \(size)")
        }
        // the big deck: about 60 pt on a portrait phone; the smallest Duo table guess still gets 40+
        #expect(cSize(ControllerLayout.deck(CGSize(width: 382, height: 370), system: .n64)) >= 58)
        #expect(cSize(ControllerLayout.deck(CGSize(width: 330, height: 250), system: .n64)) >= 40)
        // the C stick takes the diamond's place, as big as the D-pad
        let deck = ControllerLayout.deck(CGSize(width: 382, height: 370), system: .n64)
        if let pad = deck.first(where: { $0.kind == .dpad }), let cs = deck.first(where: { $0.kind == .cStick }) {
            #expect(abs(cs.frame.width - pad.frame.width) < 1)
        } else {
            Issue.record("no D-pad or C stick")
        }
        for size in [CGSize(width: 400, height: 150), CGSize(width: 422, height: 140), CGSize(width: 460, height: 200)] {
            #expect(cSize(ControllerLayout.bookRight(size, system: .n64)) >= 44, "book \(size)")
        }
        #expect(cSize(ControllerLayout.bookRight(CGSize(width: 230, height: 100), system: .n64)) >= 21)
        #expect(cSize(ControllerLayout.overlay(CGSize(width: 852, height: 393), gameRect: CGRect(x: 175, y: 8, width: 502, height: 377),
                                               system: .n64)) >= 44)
        #expect(cSize(ControllerLayout.overlay(CGSize(width: 667, height: 375), gameRect: CGRect(x: 103, y: 8, width: 461, height: 359),
                                               system: .n64)) >= 21)
    }

    /// The camera choice swaps the four C buttons for one C stick in the same place; layouts saved
    /// before the C stick existed get one made over their C buttons.
    @Test func cameraChoiceSwapsTheCButtonsForTheCStick() {
        let deck = ControllerLayout.deck(CGSize(width: 382, height: 370), system: .n64)
        let buttons = N64Layout.camera(deck, cStick: false)
        #expect(buttons.filter(N64Layout.isCButton).count == 4 && !buttons.contains { $0.kind == .cStick })
        let stick = N64Layout.camera(deck, cStick: true)
        #expect(!stick.contains(where: N64Layout.isCButton) && stick.filter { $0.kind == .cStick }.count == 1)
        #expect(stick.first { $0.kind == .cStick }?.buttons == [.cUp, .cDown, .cLeft, .cRight])
        let old = deck.filter { $0.kind != .cStick }   // a layout saved by build 5
        let made = N64Layout.camera(old, cStick: true).first { $0.kind == .cStick }
        let box = old.filter(N64Layout.isCButton).map(\.frame).reduce(CGRect.null) { $0.union($1) }
        #expect(made != nil)
        if let made {
            #expect(abs(made.frame.midX - box.midX) < 0.5 && abs(made.frame.midY - box.midY) < 0.5)
            #expect(made.frame.width > box.width * 0.6 && made.frame.width <= box.width)
        }
        #expect(N64Layout.withCStick(deck).count == deck.count)   // never a second one
    }

    @Test func cStickDirections() {
        let o = CGPoint(x: 100, y: 100), r: CGFloat = 50
        func at(_ degrees: Double, _ fraction: Double) -> CGPoint {
            let a = degrees * .pi / 180
            return CGPoint(x: 100 + cos(a) * fraction * 50, y: 100 - sin(a) * fraction * 50)   // up is +90
        }
        // threshold: nothing until 40 % of the radius
        #expect(CStickMath.buttons(thumb: at(0, 0.35), origin: o, radius: r, held: []) == [])
        #expect(CStickMath.buttons(thumb: at(0, 0.45), origin: o, radius: r, held: []) == .cRight)
        #expect(CStickMath.buttons(thumb: at(90, 0.9), origin: o, radius: r, held: []) == .cUp)
        #expect(CStickMath.buttons(thumb: at(180, 0.9), origin: o, radius: r, held: []) == .cLeft)
        #expect(CStickMath.buttons(thumb: at(270, 2), origin: o, radius: r, held: []) == .cDown)   // beyond the rim still counts
        // hysteresis: once held, it lets go only inside 30 %
        #expect(CStickMath.buttons(thumb: at(0, 0.35), origin: o, radius: r, held: .cRight) == .cRight)
        #expect(CStickMath.buttons(thumb: at(0, 0.25), origin: o, radius: r, held: .cRight) == [])
        // diagonals press two at once
        #expect(CStickMath.buttons(thumb: at(45, 0.8), origin: o, radius: r, held: []) == [.cUp, .cRight])
        #expect(CStickMath.buttons(thumb: at(135, 0.8), origin: o, radius: r, held: []) == [.cUp, .cLeft])
        #expect(CStickMath.buttons(thumb: at(225, 0.8), origin: o, radius: r, held: []) == [.cDown, .cLeft])
        #expect(CStickMath.buttons(thumb: at(315, 0.8), origin: o, radius: r, held: []) == [.cDown, .cRight])
        // eight equal sectors: 15 degrees is right only, 30 is the up-right diagonal
        #expect(CStickMath.buttons(thumb: at(15, 0.8), origin: o, radius: r, held: []) == .cRight)
        #expect(CStickMath.buttons(thumb: at(30, 0.8), origin: o, radius: r, held: []) == [.cUp, .cRight])
        // angle hysteresis: a held diagonal survives a small drift past the sector edge
        #expect(CStickMath.buttons(thumb: at(18, 0.8), origin: o, radius: r, held: [.cUp, .cRight]) == [.cUp, .cRight])
        #expect(CStickMath.buttons(thumb: at(10, 0.8), origin: o, radius: r, held: [.cUp, .cRight]) == .cRight)
        // release: back at the centre, nothing (the touch layer also clears it when the thumb lifts)
        #expect(CStickMath.buttons(thumb: o, origin: o, radius: r, held: [.cUp, .cRight]) == [])
        #expect(CStickMath.buttons(thumb: at(0, 0.9), origin: o, radius: 0, held: []) == [])
    }

    /// The camera choice: this game's, else all games', else C buttons.
    @Test func cameraOptionResolvesGameThenSystem() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("opts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LayoutStore(directory: dir)
        #expect(store.options(.n64, game: "g1").cStick == nil)
        store.saveOptions(LayoutOptions(cStick: true), .n64, game: nil)
        #expect(store.options(.n64, game: "g1").cStick == true)
        store.saveOptions(LayoutOptions(cStick: false), .n64, game: "g1")
        #expect(store.options(.n64, game: "g1").cStick == false)
        #expect(store.options(.n64, game: "g2").cStick == true)
        #expect(store.hasGameLayout(.n64, game: "g1"))
        store.removeOptions(.n64, game: "g1")
        #expect(store.options(.n64, game: "g1").cStick == true)
        // survives a fresh store (on disk)
        #expect(LayoutStore(directory: dir).options(.n64, game: nil).cStick == true)
    }

    @Test func stickIsTrueAnalog() {
        let o = CGPoint(x: 100, y: 100)
        // no snapping: a point at 30 degrees comes out at 30 degrees
        let p = CGPoint(x: 100 + 40 * cos(.pi / 6), y: 100 - 40 * sin(.pi / 6))
        let v = StickMath.value(thumb: p, origin: o, radius: 50, range: 1, deadZone: 0)
        #expect(abs(atan2(v.y, v.x) - .pi / 6) < 1e-9)
        #expect(abs((v.x * v.x + v.y * v.y).squareRoot() - 0.8) < 1e-9)
        // sensitivity: full tilt at range x radius, clamped beyond it
        let full = StickMath.value(thumb: CGPoint(x: 140, y: 100), origin: o, radius: 50, range: 0.8, deadZone: 0)
        #expect(abs(full.x - 1) < 1e-9 && full.y == 0)
        let beyond = StickMath.value(thumb: CGPoint(x: 100, y: 10), origin: o, radius: 50, range: 0.8, deadZone: 0)
        #expect(abs(beyond.y - 1) < 1e-9)   // up is positive; the outer ring is full tilt
        // dead zone: nothing inside, then rising smoothly from zero
        #expect(StickMath.value(thumb: CGPoint(x: 104, y: 100), origin: o, radius: 50, range: 1, deadZone: 0.1) == .centre)
        let edge = StickMath.value(thumb: CGPoint(x: 106, y: 100), origin: o, radius: 50, range: 1, deadZone: 0.1)
        #expect(edge.x > 0 && edge.x < 0.03)
        // the knob follows the thumb, held inside the base
        #expect(StickMath.knob(thumb: CGPoint(x: 110, y: 95), origin: o, radius: 50) == CGVector(dx: 10, dy: -5))
        let k = StickMath.knob(thumb: CGPoint(x: 300, y: 100), origin: o, radius: 50)
        #expect(abs(k.dx - 31) < 1e-9 && k.dy == 0)
    }

    @Test func stickSettingsLoadFromOldFilesAndAreClamped() throws {
        let old = Data(#"{"diagonalDegrees":24,"deadZone":0.2,"autoFireHz":15,"hapticLevel":0.5}"#.utf8)
        let s = try JSONDecoder().decode(ControlSettings.self, from: old)
        #expect(s.diagonalDegrees == 24 && s.stickRange == 0.8 && s.stickDeadZone == 0.06)
        #expect(!s.stickOuterRing && !s.stickRecentre)
        var wild = ControlSettings()
        wild.stickRange = 9
        wild.stickDeadZone = -1
        #expect(wild.sanitised.stickRange == 1 && wild.sanitised.stickDeadZone == 0)
        var round = ControlSettings()
        round.stickOuterRing = true
        round.stickRecentre = true
        round.stickRange = 0.6
        let back = try JSONDecoder().decode(ControlSettings.self, from: JSONEncoder().encode(round))
        #expect(back == round)
    }

    @Test func latchCarriesTheStick() {
        let latch = InputLatch()
        #expect(latch.stick == .centre)
        latch.padStick.store(InputLatch.pack(AnalogStick(x: 0.25, y: -0.5)), ordering: .relaxed)
        #expect(latch.stick == AnalogStick(x: 0.25, y: -0.5))
        latch.touchStick.store(InputLatch.pack(AnalogStick(x: -1, y: 1)), ordering: .relaxed)
        #expect(latch.stick == AnalogStick(x: -1, y: 1))   // the touch stick wins while held
        let shaped = GamepadHub.shapedStick((x: 0.05, y: 0), deadZone: 0.12)
        #expect(shaped == .centre)
        let rim = GamepadHub.shapedStick((x: 0, y: 1), deadZone: 0.12)
        #expect(abs(rim.y - 1) < 1e-9)
        let mapping = ControllerMapping.defaults(for: .n64)
        #expect(!mapping.stickAsDpad)
        #expect(mapping.buttons[.rightStickUp] == .cUp && mapping.buttons[.rightStickRight] == .cRight)
        let r = InputMapper.resolve(pressed: InputMapper.rightStickInputs(x: 0.9, y: -0.8), stick: (0, 0), mapping: mapping)
        #expect(r.buttons == [.cRight, .cDown])
    }
}
