import CoreMotion
import SwiftUI

/// Distinguishes the poses the fold API cannot.
///
/// A horizontal division region means the display is split into a top and a bottom
/// half — but that is true both when the device lies open like a laptop and when it
/// stands on its edges like a tent, and those are completely different products. The
/// reserved-region API reports axis and active/inactive only.
///
/// With a hinge angle (iOS 27.1 on hardware) the detector compares the IMU half's tilt
/// against what a tent and a table would each produce at that angle, refuses tent
/// above ~150°, and needs three agreeing samples before switching. Without one it
/// falls back to gravity alone. See `PoseClassifier` for the geometry.
@MainActor
@Observable
public final class PoseDetector {

    /// The detected pose. Raw sensor output: `DuoStageReader` additionally applies the
    /// user's `DuoPoseOverride`.
    public private(set) var pose: DuoPose = .flat
    /// Live hinge angle in degrees (180 = flat) when the SDK provides one.
    public private(set) var hingeDegrees: Double?
    /// True while the hinge reports `.closed`.
    public private(set) var isClosed = false

    private let motion = CMMotionManager()
    private var fold: Fold = .flat
    private var hinge: HingeReading?
    private var filter = PoseHysteresis()

    public init() {
        #if DEBUG
        observeSimulator()
        #endif
    }

    public func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 0.2
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let gravity = data?.gravity else { return }
            self.recompute(gravity: gravity)
        }
    }

    public func stop() {
        motion.stopDeviceMotionUpdates()
    }

    public func update(fold: Fold) {
        self.fold = fold
        recompute(gravity: motion.deviceMotion?.gravity)
    }

    public func update(hinge: HingeReading?) {
        self.hinge = hinge
        let degrees = hinge?.degrees
        if hingeDegrees != degrees { hingeDegrees = degrees }
        let closed = hinge?.isClosed ?? false
        if isClosed != closed { isClosed = closed }
        recompute(gravity: motion.deviceMotion?.gravity)
    }

    private func recompute(gravity: CMAcceleration?) {
        #if DEBUG
        // A simulated fold carries its simulated pose. Gravity in the Simulator is
        // meaningless, so it must not be consulted for a hinge that does not exist.
        if fold.isSimulated {
            set(FoldSimulator.shared.pose)
            filter.reset(to: pose)
            return
        }
        #endif
        let raw = PoseClassifier.classify(fold: fold, hinge: hinge, gravityY: gravity?.y)
        set(filter.feed(raw))
    }

    /// Assigns only on change, so observers are not woken five times a second for a
    /// pose that has not moved.
    private func set(_ new: DuoPose) {
        if pose != new { pose = new }
    }

    #if DEBUG
    /// Re-resolves when the debug pose picker changes. Table and tent produce the same
    /// simulated fold, so `update(fold:)` alone never hears about that switch.
    private func observeSimulator() {
        withObservationTracking {
            _ = FoldSimulator.shared.pose
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recompute(gravity: self.motion.deviceMotion?.gravity)
                self.observeSimulator()
            }
        }
    }
    #endif
}
