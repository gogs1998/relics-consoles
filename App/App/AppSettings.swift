import CoreKit
import Foundation
import Observation

/// App-wide preferences (Settings screen), kept in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    /// Touch-controller haptics (and controller rumble on save/load).
    var haptics: Bool { didSet { defaults.set(haptics, forKey: Keys.haptics) } }
    /// Game volume, 0...1, applied to the emulator's own audio only.
    var volume: Double { didSet { defaults.set(volume, forKey: Keys.volume) } }
    /// The screen filter a system uses until the pause menu picks one for it.
    var screenMode: ScreenMode {
        didSet {
            defaults.set(screenMode.rawValue, forKey: Keys.screenMode)
            // A new default applies everywhere: forget the per-system choices.
            for s in SystemID.allCases { defaults.removeObject(forKey: "screenMode.\(s.rawValue)") }
        }
    }
    /// Fast-forward multiplier.
    var fastForwardSpeed: Int { didSet { defaults.set(fastForwardSpeed, forKey: Keys.fastForward) } }
    /// Write an auto-save when the game sleeps or closes, and resume from it next time.
    var autoSave: Bool { didSet { defaults.set(autoSave, forKey: Keys.autoSave) } }

    static let fastForwardChoices = [2, 3, 4, 8]

    enum Keys {
        static let haptics = "settings.haptics", volume = "settings.volume", screenMode = "settings.screenMode"
        static let fastForward = "settings.fastForward", autoSave = "settings.autoSave"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        haptics = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        volume = min(1, max(0, defaults.object(forKey: Keys.volume) as? Double ?? 0.9))
        screenMode = defaults.string(forKey: Keys.screenMode).flatMap(ScreenMode.init(rawValue:)) ?? .auto
        let ff = defaults.integer(forKey: Keys.fastForward)
        fastForwardSpeed = Self.fastForwardChoices.contains(ff) ? ff : 3
        autoSave = defaults.object(forKey: Keys.autoSave) as? Bool ?? true
    }
}
