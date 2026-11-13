import CoreKit
@testable import DuoEmulator
import Foundation
import Testing

@MainActor
@Suite struct SettingsTests {
    @Test func defaultsPersistenceAndClamping() throws {
        let name = "settings-test-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        let a = AppSettings(defaults: d)
        #expect(a.haptics && a.autoSave && a.fastForwardSpeed == 3 && a.screenMode == .auto && a.volume == 0.9)
        d.set("lcd", forKey: "screenMode.gb")
        a.haptics = false; a.autoSave = false; a.fastForwardSpeed = 4; a.volume = 0.25; a.screenMode = .scanlines
        #expect(d.string(forKey: "screenMode.gb") == nil)   // a new default resets per-system picks
        let b = AppSettings(defaults: d)
        #expect(!b.haptics && !b.autoSave && b.fastForwardSpeed == 4 && b.volume == 0.25 && b.screenMode == .scanlines)
        d.set(7, forKey: AppSettings.Keys.fastForward)
        d.set(3.0, forKey: AppSettings.Keys.volume)
        let c = AppSettings(defaults: d)
        #expect(c.fastForwardSpeed == 3 && c.volume == 1)
    }
}
