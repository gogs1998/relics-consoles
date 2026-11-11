import XCTest

/// The DS test cart (our own ROM, Tools/build_ds_roms.py) in each arrangement, and the stylus path:
/// a tap on the touch screen reaches the session. Screenshots go to /private/tmp/duo-emulator-uitest/.
final class DSUITests: XCTestCase {
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
        app.launchArguments = args + ["-autoplay", "ds_demo.nds", "-freshStart", "YES", "-keepTouchControls", "YES",
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

    /// Duo table pose: tapping the touch screen sends the stylus; the controls sit around it.
    @MainActor func testTableTouchScreen() throws {
        let app = launch(["-pose", "table"])
        let pad = app.descendants(matching: .any)["ds.touchScreen"]
        XCTAssertTrue(pad.waitForExistence(timeout: 8))
        sleep(2)
        let frame = pad.frame
        XCTAssertGreaterThan(frame.width, 100)
        XCTAssertEqual(frame.width / frame.height, 4.0 / 3.0, accuracy: 0.02)
        // The touch screen is in the bottom half, and no button overlaps it.
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.minY, window.midY - 40)
        var seen = 0
        for label in ["A button", "B button", "X button", "Y button", "L shoulder button", "R shoulder button",
                      "Start", "Select", "Direction pad"] {
            let button = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            guard button.exists else { continue }
            seen += 1
            XCTAssertFalse(button.frame.intersects(frame), "\(label) covers the touch screen")
        }
        XCTAssertGreaterThanOrEqual(seen, 7, "the DS controls are missing")
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.5)
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.9)).tap()
        let readout = app.descendants(matching: .any)["debug.stylus"]
        XCTAssertTrue(readout.waitForExistence(timeout: 3))
        let parts = ((readout.value as? String) ?? "").split(separator: " ").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 3, "readout \(String(describing: readout.value))")
        XCTAssertGreaterThanOrEqual(parts.first ?? 0, 2, "stylus presses not seen")
        // The last tap was near the bottom-left corner of the 256 x 192 screen.
        if parts.count == 3 {
            XCTAssertLessThan(parts[1], 64)
            XCTAssertGreaterThan(parts[2], 150)
        }
        save("table-ds")
    }

    /// Touch held through the launch argument: the game paints the touch screen green.
    @MainActor func testTableStylusHeld() {
        _ = launch(["-pose", "table", "-holdStylus", "128,96", "-holdInput", "a"])
        sleep(5)
        save("table-ds-stylus")
    }

    /// The layout editor works on the DS's three table-pose areas: drag A, save, it moved.
    @MainActor func testEditorMovesDSButton() throws {
        let app = launch(["-pose", "table", "-openMenu", "YES"])
        let aButton = app.descendants(matching: .any)["A button"]
        XCTAssertTrue(aButton.waitForExistence(timeout: 10))
        let before = aButton.frame
        let edit = app.buttons["menu.editControls"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        XCTAssertTrue(app.buttons["edit.done"].waitForExistence(timeout: 5))
        let handle = app.descendants(matching: .any)["edit.face16"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 40)))
        save("editor-table-ds")
        app.buttons["edit.done"].tap()
        sleep(1)
        let after = app.descendants(matching: .any)["A button"].frame
        XCTAssertGreaterThan(after.midY, before.midY + 16, "A button didn't move down")
        let pad = app.descendants(matching: .any)["ds.touchScreen"]
        XCTAssertFalse(after.intersects(pad.frame), "the moved button covers the touch screen")
    }

    @MainActor func testPhonePortrait() {
        _ = launch(["-pose", "flat", "-duoAspect", "NO"])
        sleep(5)
        save("iphone-ds")
    }

    @MainActor func testBookPose() {
        _ = launch(["-pose", "book"], landscape: true)
        sleep(5)
        save("book-ds")
    }

    @MainActor func testPhoneLandscape() {
        _ = launch(["-pose", "flat", "-duoAspect", "NO"], landscape: true)
        sleep(5)
        save("iphone-landscape-ds")
    }
}
