import CoreKit
@testable import DuoEmulator
import Foundation
import Testing

/// The DS standard layouts: every control inside its area, no two controls overlapping, and the
/// stylus mapping onto the 256 x 192 touch screen.
@MainActor
@Suite struct DSLayoutTests {
    private func checkNoOverlap(_ controls: [Control], in size: CGSize, _ name: String) {
        let bounds = CGRect(origin: .zero, size: size)
        let solid = controls.filter { if case .combo = $0.kind { return false } else { return true } }
        for c in solid {
            #expect(bounds.insetBy(dx: -0.5, dy: -0.5).contains(c.frame), "\(name): \(c.id) leaves its area")
        }
        for (i, a) in solid.enumerated() {
            for b in solid.dropFirst(i + 1) {
                if case .face = a.kind, case .face = b.kind {
                    // Round buttons: their square frames may touch at the corners, the circles must not.
                    let d = hypot(a.frame.midX - b.frame.midX, a.frame.midY - b.frame.midY)
                    #expect(d >= (a.frame.width + b.frame.width) / 2 - 1, "\(name): \(a.id) overlaps \(b.id)")
                    continue
                }
                #expect(!a.frame.insetBy(dx: 1, dy: 1).intersects(b.frame.insetBy(dx: 1, dy: 1)),
                        "\(name): \(a.id) overlaps \(b.id)")
            }
        }
    }

    @Test func defaultLayoutsAreTidy() {
        for size in [CGSize(width: 90, height: 260), CGSize(width: 140, height: 400)] {
            checkNoOverlap(ControllerLayout.dsTableLeft(size), in: size, "table left")
            checkNoOverlap(ControllerLayout.dsTableRight(size), in: size, "table right")
        }
        let below = CGSize(width: 280, height: 70)
        checkNoOverlap(ControllerLayout.dsTableBelow(below), in: below, "table below")
        for size in [CGSize(width: 300, height: 150), CGSize(width: 380, height: 160), CGSize(width: 420, height: 230)] {
            checkNoOverlap(ControllerLayout.dsBookRight(size), in: size, "book right")
        }
        let deck = CGSize(width: 393, height: 300)
        let controls = ControllerLayout.deck(deck, system: .ds)
        #expect(controls.contains { $0.buttons == .x } && controls.contains { $0.buttons == .y })
        #expect(controls.contains { $0.buttons == .l } && controls.contains { $0.buttons == .r })
        #expect(LayoutPreset.available(for: .ds) == [.standard])
        #expect(ControllerArea.dsTableLeft.isSecondary && !ControllerArea.dsTableRight.isSecondary)
    }

    @Test func stylusMapsOntoTheScreen() {
        let size = CGSize(width: 320, height: 240)
        #expect(DSTouchPad.map(.zero, in: size) == TouchPoint(x: 0, y: 0))
        #expect(DSTouchPad.map(CGPoint(x: 160, y: 120), in: size) == TouchPoint(x: 128, y: 96))
        #expect(DSTouchPad.map(CGPoint(x: 400, y: -9), in: size) == TouchPoint(x: 255, y: 0))
        let packed = InputLatch.stylus(x: 200, y: 150)
        let latch = InputLatch()
        latch.stylus.store(packed, ordering: .relaxed)
        #expect(latch.stylusPoint == TouchPoint(x: 200, y: 150))
        latch.stylus.store(0, ordering: .relaxed)
        #expect(latch.stylusPoint == nil)
    }
}
