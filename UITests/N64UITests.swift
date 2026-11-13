import XCTest

/// The Nintendo 64 test cart (our own ROM, Tools/build_n64_roms.py): the touch stick and buttons
/// reach the session, no control covers the game, the layout editor shows the stick settings, and
/// screenshots of each arrangement go to /private/tmp/duo-emulator-uitest/.
final class N64UITests: XCTestCase {
    private let outDir = "/private/tmp/duo-emulator-uitest"

    override func tearDown() async throws {
        await MainActor.run {
            XCUIApplication().terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        try await super.tearDown()
    }

    @MainActor
    private func launch(_ args: [String], landscape: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = args + ["-autoplay", "n64_demo.z64", "-freshStart", "YES", "-keepTouchControls", "YES",
                                      "-resetLayouts", "YES"]
        app.launch()
        return app
    }

    @MainActor
    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    }

    @MainActor
    private func element(_ app: XCUIApplication, label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func checkNothingCoversTheGame(_ app: XCUIApplication, _ name: String) {
        let game = app.descendants(matching: .any)["game.screen"]
        XCTAssertTrue(game.waitForExistence(timeout: 8), "\(name): no game screen")
        var seen = 0
        for label in ["Analog stick", "Direction pad", "A button", "B button", "C up button", "C down button",
                      "C left button", "C right button", "Z shoulder button", "L shoulder button", "R shoulder button",
                      "Start"] {
            let e = element(app, label: label)
            guard e.exists else { continue }
            seen += 1
            XCTAssertFalse(e.frame.intersects(game.frame.insetBy(dx: 1, dy: 1)), "\(name): \(label) covers the game")
        }
        XCTAssertEqual(seen, 12, "\(name): some N64 controls are missing")
    }

    /// iPhone portrait: the stick moves the analog value, A reaches the game, nothing covers it.
    @MainActor func testPortraitStickAndButtons() throws {
        let app = launch(["-pose", "flat", "-duoAspect", "NO"])
        let stick = element(app, label: "Analog stick")
        XCTAssertTrue(stick.waitForExistence(timeout: 10))
        sleep(2)
        checkNothingCoversTheGame(app, "portrait")
        let centre = stick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        centre.press(forDuration: 0.1, thenDragTo: centre.withOffset(CGVector(dx: stick.frame.width * 0.6, dy: 0)),
                     withVelocity: .slow, thenHoldForDuration: 0.6)
        let readout = app.descendants(matching: .any)["debug.stick"]
        XCTAssertTrue(readout.waitForExistence(timeout: 3))
        let parts = ((readout.value as? String) ?? "").split(separator: " ").compactMap { Double($0) }
        XCTAssertEqual(parts.count, 2, "readout \(String(describing: readout.value))")
        XCTAssertGreaterThan(parts.first ?? 0, 0.9, "the stick didn't reach full right")
        XCTAssertLessThan(abs(parts.last ?? 1), 0.2)
        element(app, label: "A button").press(forDuration: 0.3)
        let touch = app.descendants(matching: .any)["debug.touchInput"]
        let bits = UInt32((touch.value as? String) ?? "") ?? 0
        XCTAssertNotEqual(bits & (1 << 4), 0, "A didn't reach the latch")
        // hold A for the screenshot (the square turns red)
        let a = element(app, label: "A button").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        a.press(forDuration: 0.05)
        save("iphone-n64")
    }

    @MainActor func testLandscape() {
        let app = launch(["-pose", "flat", "-duoAspect", "NO"], landscape: true)
        XCTAssertTrue(element(app, label: "Analog stick").waitForExistence(timeout: 10))
        sleep(3)
        checkNothingCoversTheGame(app, "landscape")
        save("iphone-landscape-n64")
    }

    @MainActor func testDuoTable() {
        let app = launch(["-pose", "table"])
        XCTAssertTrue(element(app, label: "Analog stick").waitForExistence(timeout: 10))
        sleep(3)
        checkNothingCoversTheGame(app, "table")
        save("table-n64")
    }

    @MainActor func testBookPose() {
        let app = launch(["-pose", "book"], landscape: true)
        XCTAssertTrue(element(app, label: "Analog stick").waitForExistence(timeout: 10))
        sleep(3)
        save("book-n64")
    }

    /// The editor's panel has the stick settings; turning on the outer ring is saved with Done.
    @MainActor func testEditorStickSettings() throws {
        let app = launch(["-pose", "flat", "-duoAspect", "NO", "-openMenu", "YES"])
        let edit = app.buttons["menu.editControls"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        XCTAssertTrue(app.buttons["edit.done"].waitForExistence(timeout: 5))
        let ring = app.switches["edit.stickRing"]
        if !ring.exists { app.swipeUp() }
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "no outer-ring setting")
        XCTAssertTrue(app.switches["edit.stickRecentre"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["edit.stickSensitivity"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["edit.stickDeadZone"].exists)
        ring.tap()
        save("editor-n64")
        app.buttons["edit.done"].tap()
        sleep(1)
        XCTAssertTrue(element(app, label: "Analog stick").exists)
    }
}
