import Foundation

/// The pure core of `PoseDetector`: no CoreMotion, no SwiftUI state, no clock. Every
/// decision the detector makes about table versus tent is made here, so it can be
/// unit-tested with plain numbers.
enum PoseClassifier {

    /// Above this hinge angle (180 = flat) the device is too open to be standing as a
    /// tent. It is a slightly bent phone in a hand, or a laptop with its lid well back.
    static let tentMaxHingeDegrees = 150.0

    /// Fallback when there is no hinge angle (pre-27.1, the Simulator): above this much
    /// gravity along the screen's y axis the reference half counts as standing up.
    /// 0.5g is 30 degrees off horizontal.
    static let legacyUprightThreshold = 0.5

    /// One sample's verdict, before hysteresis.
    ///
    /// - Parameters:
    ///   - fold: the division region, real or simulated.
    ///   - hinge: the latest hinge reading, if the SDK provides one.
    ///   - gravityY: CoreMotion gravity along the device's y axis, in g. `nil` when
    ///     motion is unavailable or not started.
    static func classify(fold: Fold, hinge: HingeReading?, gravityY: Double?) -> DuoPose {
        if let hinge {
            // The hinge itself says the device is open flat; trust it over a region
            // that may lag the hardware by a frame.
            if hinge.isFullyOpen { return .flat }
            // Closed: the inner display is off. Never claim a second viewer.
            if hinge.isClosed { return DuoPose(fold: fold) }
        }
        guard fold.isActive else { return .flat }
        guard fold.axis == .horizontal else { return .book }

        // No motion data: assume the safer pose. Claiming `.tent` while flat on a desk
        // would draw one half upside down for the only person looking at it.
        guard let gravityY, gravityY.isFinite else { return .table }

        guard let degrees = hinge?.degrees, degrees.isFinite else {
            return abs(gravityY) > legacyUprightThreshold ? .tent : .table
        }
        return horizontalPose(hingeDegrees: degrees, gravityY: gravityY)
    }

    /// Table or tent, from hinge angle α and the IMU half's tilt θ = asin(|gravity.y|).
    ///
    /// - Tent (a symmetric lambda on its two edges): each half is tilted
    ///   (180 − α) / 2 off horizontal.
    /// - Table (an L, one half on the surface): the base half reads θ ≈ 0, the lid
    ///   half reads θ ≈ 180 − α. Which half holds the IMU is not known, so both are
    ///   candidates. Past vertical (α < 90) the lid leans back over the base, and
    ///   |gravity.y| folds back: asin(sin(180 − α)) = α.
    ///
    /// The nearest prediction wins; a tie goes to `.table`, the safer answer.
    static func horizontalPose(hingeDegrees: Double, gravityY: Double) -> DuoPose {
        guard hingeDegrees < tentMaxHingeDegrees else { return .table }
        let alpha = min(max(hingeDegrees, 0), 180)
        let theta = asin(min(abs(gravityY), 1)) * 180 / .pi

        let tent = (180 - alpha) / 2
        let lidRaw = 180 - alpha
        let lid = lidRaw > 90 ? 180 - lidRaw : lidRaw

        let toTent = abs(theta - tent)
        let toTable = min(abs(theta), abs(theta - lid))
        return toTent < toTable ? .tent : .table
    }
}

/// Debounces table ↔ tent so a pose sitting on a decision boundary does not flicker.
///
/// Only the gravity-derived decision is debounced. Transitions into or out of `.flat`
/// or `.book` come from the OS's own fold state and are applied immediately.
struct PoseHysteresis: Equatable {

    /// Consecutive agreeing samples needed before switching between table and tent.
    let required: Int

    private(set) var current: DuoPose?
    private var pending: DuoPose?
    private var count = 0

    init(required: Int = 3) {
        self.required = max(1, required)
    }

    /// Feeds one raw sample and returns the pose to report.
    mutating func feed(_ candidate: DuoPose) -> DuoPose {
        guard let current, Self.isDebounced(current), Self.isDebounced(candidate) else {
            reset(to: candidate)
            return candidate
        }
        if candidate == current {
            pending = nil
            count = 0
            return current
        }
        if candidate == pending {
            count += 1
        } else {
            pending = candidate
            count = 1
        }
        if count >= required {
            reset(to: candidate)
            return candidate
        }
        return current
    }

    mutating func reset(to pose: DuoPose?) {
        current = pose
        pending = nil
        count = 0
    }

    private static func isDebounced(_ pose: DuoPose) -> Bool {
        pose == .table || pose == .tent
    }
}
