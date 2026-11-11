import XCTest

/// The layout editor, the 6-Button Arcade preset, the controllers screen and the layouts used
/// while a physical controller plays (faked with -fakeController: the simulator can't pair a pad).
final class ControlsUITests: XCTestCase {
    private let outDir = "/private/tmp/duo-emulator-uitest"

    override func tearDown() async throws {
        await MainActor.run {
            XCUIApplication().terminate()            // no game audio left playing
            XCUIDevice.shared.orientation = .portrait
        }
        try await super.tearDown()
    }

    @MainActor private func save(_ name: String) {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    }

    @MainActor private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    @MainActor private func openEditor(_ app: XCUIApplication) {
        let edit = app.buttons["menu.editControls"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        XCTAssertTrue(app.buttons["edit.done"].waitForExistence(timeout: 5))
    }

    /// Drag the A button in edit mode, save, relaunch: it stays where it was put.
    @MainActor func testEditorMovesAndKeepsAButton() throws {
        var app = launch(["-pose", "table", "-autoplay", "demo.nes", "-freshStart", "YES", "-resetLayouts", "YES", "-openMenu", "YES", "-keepTouchControls", "YES"])
        let aButton = app.descendants(matching: .any)["A button"]
        XCTAssertTrue(aButton.waitForExistence(timeout: 10))
        let before = aButton.frame
        openEditor(app)
        let handle = app.descendants(matching: .any)["edit.face16"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: -48, dy: -24)))
        save("editor-table")
        app.buttons["edit.done"].tap()
        sleep(1)
        let after = app.descendants(matching: .any)["A button"].frame
        XCTAssertLessThan(after.midX, before.midX - 20, "A button didn't move left")
        app.terminate()
        app = launch(["-pose", "table", "-autoplay", "demo.nes", "-freshStart", "YES", "-keepTouchControls", "YES"])
        let again = app.descendants(matching: .any)["A button"]
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        XCTAssertEqual(again.frame.midX, after.midX, accuracy: 2, "layout wasn't saved")
    }

    @MainActor private func chooseArcade(_ app: XCUIApplication) {
        app.buttons["edit.preset"].tap()
        let item = app.buttons["6-Button Arcade"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }

    @MainActor func testArcadePresetSNES() throws {
        let app = launch(["-pose", "table", "-autoplay", "ares_snes_demo.sfc", "-freshStart", "YES", "-resetLayouts", "YES", "-openMenu", "YES", "-keepTouchControls", "YES"])
        openEditor(app)
        chooseArcade(app)
        save("editor-arcade-snes")
        app.buttons["edit.done"].tap()
        sleep(1)
        XCTAssertTrue(app.descendants(matching: .any)["L button"].exists, "arcade panel puts L on the face")
        save("table-arcade-snes")
    }

    @MainActor func testArcadePresetMegaDrive() throws {
        let app = launch(["-pose", "table", "-autoplay", "ares_md_demo.md", "-freshStart", "YES", "-resetLayouts", "YES", "-openMenu", "YES", "-keepTouchControls", "YES"])
        openEditor(app)
        chooseArcade(app)
        app.buttons["edit.done"].tap()
        sleep(1)
        XCTAssertTrue(app.descendants(matching: .any)["Z button"].exists)
        save("table-arcade-md")
    }

    @MainActor func testControllersScreen() throws {
        let app = launch(["-pose", "flat", "-duoAspect", "NO", "-autoplay", "ares_snes_demo.sfc", "-freshStart", "YES",
                          "-fakeController", "YES", "-openMenu", "YES"])
        let button = app.buttons["menu.controllers"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        sleep(2)
        save("controllers-sheet")
    }

    @MainActor func testControllerCompanionTable() throws {
        let app = launch(["-pose", "table", "-autoplay", "gba_demo.gba", "-freshStart", "YES", "-fakeController", "YES"])
        sleep(4)
        XCTAssertFalse(app.descendants(matching: .any)["Direction pad"].exists, "touch controls should hide")
        save("table-controller")
    }

    @MainActor func testControllerLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        _ = launch(["-pose", "flat", "-duoAspect", "NO", "-autoplay", "demo.nes", "-freshStart", "YES", "-fakeController", "YES"])
        sleep(4)
        save("landscape-controller")
    }

    @MainActor func testControllerBook() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        _ = launch(["-pose", "book", "-autoplay", "ares_snes_demo.sfc", "-freshStart", "YES", "-fakeController", "YES"])
        sleep(4)
        save("book-controller")
    }
}
