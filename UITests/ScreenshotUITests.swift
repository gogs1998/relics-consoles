import XCTest

/// Launches each pose and saves screenshots to /private/tmp/duo-emulator-uitest/.
/// Book pose is taken in landscape: the Duo's hinge runs along its short edge, so a vertical fold
/// only happens with the device turned sideways.
final class ScreenshotUITests: XCTestCase {
    private let outDir = "/private/tmp/duo-emulator-uitest"

    override func tearDown() async throws {
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }
        try await super.tearDown()
    }

    @MainActor
    private func shoot(_ name: String, args: [String], landscape: Bool = false, wait: UInt32 = 4,
                       before: ((XCUIApplication) -> Void)? = nil) {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        sleep(wait)
        before?(app)
        let shot = XCUIScreen.main.screenshot()
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    }

    @MainActor func testTablePose() {
        shoot("table-nes", args: ["-pose", "table", "-autoplay", "demo.nes", "-freshStart", "YES", "-holdInput", "right"])
    }

    @MainActor func testBookPose() {
        shoot("book-nes", args: ["-pose", "book", "-autoplay", "demo.nes", "-freshStart", "YES"], landscape: true)
    }

    @MainActor func testFlatPhone() {
        shoot("iphone-nes", args: ["-pose", "flat", "-duoAspect", "NO", "-autoplay", "demo.nes", "-freshStart", "YES"])
    }

    @MainActor func testLandscapePhone() {
        shoot("iphone-landscape-gbc", args: ["-pose", "flat", "-duoAspect", "NO", "-autoplay", "gb_demo.gbc", "-freshStart", "YES"],
              landscape: true)
    }

    @MainActor func testTableGameBoy() {
        shoot("table-gbc", args: ["-pose", "table", "-autoplay", "gb_demo.gbc", "-freshStart", "YES"])
    }

    @MainActor func testZTableMenu() {
        shoot("table-menu", args: ["-pose", "table", "-autoplay", "demo.nes", "-freshStart", "YES", "-openMenu", "YES"])
    }

    @MainActor func testLibraryTable() {
        shoot("table-library", args: ["-pose", "table"], wait: 3)
    }

    @MainActor func testLibraryPhone() {
        shoot("iphone-library", args: ["-pose", "flat", "-duoAspect", "NO"], wait: 3)
    }

    /// The audio engine is pulling samples and they are not silent.
    @MainActor func testAudioFlows() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-pose", "table", "-autoplay", "demo.nes", "-freshStart", "YES"]
        app.launch()
        sleep(5)
        let readout = app.descendants(matching: .any)["debug.audio"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        let parts = ((readout.value as? String) ?? "").split(separator: " ")
        let pulled = Int(parts.first ?? "") ?? 0
        let peak = Float(parts.last ?? "") ?? 0
        print("AUDIO pulled=\(pulled) peak=\(peak)")
        XCTAssertGreaterThan(pulled, 48_000, "the audio engine isn't pulling samples")
        XCTAssertGreaterThan(peak, 0.02, "audio is silent")
    }
}
