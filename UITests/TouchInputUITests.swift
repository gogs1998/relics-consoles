import XCTest

/// Drives the real touch controller (UIKit multi-touch surface) and checks the game responded.
/// Screenshots go to /private/tmp/duo-emulator-uitest/ (the simulator shares the Mac's filesystem).
final class TouchInputUITests: XCTestCase {
    private let outDir = "/private/tmp/duo-emulator-uitest"

    @MainActor
    func testTouchControllerDrivesTheGame() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-pose", "table", "-autoplay", "demo.nes", "-freshStart", "YES"]
        app.launch()
        let pad = app.descendants(matching: .any)["Direction pad"]
        XCTAssertTrue(pad.waitForExistence(timeout: 10))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func point(_ f: CGRect, dx: CGFloat = 0, dy: CGFloat = 0) -> XCUICoordinate {
            origin.withOffset(CGVector(dx: f.midX + dx, dy: f.midY + dy))
        }
        sleep(2)
        // Hold right on the D-pad for 1.2 s, then tap B (palette swap) and A (jump).
        point(pad.frame, dx: pad.frame.width * 0.36).press(forDuration: 1.2)
        let b = app.descendants(matching: .any)["B button"]
        let a = app.descendants(matching: .any)["A button"]
        point(b.frame).tap()
        point(a.frame).tap()
        usleep(150_000)
        save(XCUIScreen.main.screenshot(), "touch-table")

        let readout = app.descendants(matching: .any)["debug.touchInput"]
        XCTAssertTrue(readout.exists)
        let bits = UInt32((readout.value as? String) ?? "") ?? 0
        // InputState: right = 1<<3, a = 1<<4, b = 1<<5
        XCTAssertNotEqual(bits & (1 << 3), 0, "D-pad right never registered (bits \(bits))")
        XCTAssertNotEqual(bits & (1 << 4), 0, "A never registered (bits \(bits))")
        XCTAssertNotEqual(bits & (1 << 5), 0, "B never registered (bits \(bits))")
        XCTAssertEqual(bits & (1 << 10 | 1 << 11), 0, "Start/Select pressed by accident")
    }

    @MainActor
    private func save(_ shot: XCUIScreenshot, _ name: String) {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }
}
