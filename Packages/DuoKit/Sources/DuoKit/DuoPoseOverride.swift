import Foundation

/// A manual answer to "is anyone on the other side?", for when the sensors guess wrong
/// or the user simply wants the second surface on (or off).
///
/// Persisted in `UserDefaults.standard` under `storageKey` and honoured by
/// `DuoStageReader`. It only ever chooses between `.table` and `.tent`: a flat phone or
/// a book fold has no far side to force, so the override is ignored there.
///
/// Bind a toggle to it with
/// `@AppStorage(DuoPoseOverride.storageKey) var override: DuoPoseOverride = .automatic`.
public enum DuoPoseOverride: String, Sendable, CaseIterable, Identifiable {
    /// Use the detected pose.
    case automatic
    /// Treat a horizontal fold as tent: two people, far half rotated.
    case forceTent
    /// Treat a horizontal fold as table: one person, nothing rotated.
    case forceTable

    public static let storageKey = "DuoKit.poseOverride"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic:  return "Automatic"
        case .forceTent:  return "Two-sided"
        case .forceTable: return "One-sided"
        }
    }

    /// The stored override, read and written directly. Views should prefer
    /// `@AppStorage(DuoPoseOverride.storageKey)` so they redraw when it changes.
    public static var current: DuoPoseOverride {
        get {
            UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .automatic
        }
        set {
            if newValue == .automatic {
                UserDefaults.standard.removeObject(forKey: storageKey)
            } else {
                UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            }
        }
    }

    /// The pose to report given the detected one. Only `.table` and `.tent` are
    /// overridden.
    public func apply(to pose: DuoPose) -> DuoPose {
        guard pose == .table || pose == .tent else { return pose }
        switch self {
        case .automatic:  return pose
        case .forceTent:  return .tent
        case .forceTable: return .table
        }
    }
}
