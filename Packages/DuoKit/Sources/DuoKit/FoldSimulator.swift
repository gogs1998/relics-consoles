import SwiftUI

#if DEBUG

/// Development harness. There is no shipping Duo and no folding simulator yet, so the
/// fold is synthesised and the render is letterboxed into a Duo-shaped canvas on
/// whatever device is to hand.
///
/// Debug builds only — it compiles out of release entirely.
@MainActor
@Observable
public final class FoldSimulator {

    public static let shared = FoldSimulator()

    /// Also settable at launch with `-pose tent|book|flat`, so poses can be
    /// screenshotted from the command line without a folding simulator.
    public var pose: DuoPose = DuoPose(rawValue: UserDefaults.standard.string(forKey: "pose") ?? "") ?? .flat

    /// Letterbox to the inner display's 669 x 951 pt aspect, so layout decided on an
    /// iPhone 17 Pro survives contact with the real 1.42 ratio.
    public var constrainToDuoAspect = true

    /// Width of the simulated division band, margins included. On hardware the real
    /// width comes from the SDK's region frame.
    public var hingeWidth: CGFloat = 40

    /// Inner display, in points: 1878 x 2670 px at ~2.8x.
    public static let innerDisplayPoints = CGSize(width: 669, height: 951)

    public init() {}

    public func fold(in bounds: CGRect) -> Fold {
        switch pose {
        case .flat:
            return Fold(isSimulated: true)
        case .tent, .table:
            // Same division region either way — a horizontal fold. What separates a
            // laptop on a desk from a tent standing on its edges is gravity, not
            // geometry, which is exactly why `PoseDetector` exists.
            let y = bounds.midY - hingeWidth / 2
            return Fold(isActive: true,
                        frame: CGRect(x: bounds.minX, y: y, width: bounds.width, height: hingeWidth),
                        isSimulated: true)
        case .book:
            let x = bounds.midX - hingeWidth / 2
            return Fold(isActive: true,
                        frame: CGRect(x: x, y: bounds.minY, width: hingeWidth, height: bounds.height),
                        isSimulated: true)
        }
    }

    public func canvas(in bounds: CGRect) -> CGRect {
        guard constrainToDuoAspect else { return bounds }
        // Match the device's own orientation. Letterboxing a landscape screen into a
        // portrait-shaped canvas hides every landscape layout behind a bug.
        let portrait = Self.innerDisplayPoints.width / Self.innerDisplayPoints.height
        let target = bounds.width > bounds.height ? 1 / portrait : portrait
        let current = bounds.width / bounds.height
        if current > target {
            let w = bounds.height * target
            return CGRect(x: bounds.midX - w / 2, y: bounds.minY, width: w, height: bounds.height)
        } else {
            let h = bounds.width / target
            return CGRect(x: bounds.minX, y: bounds.midY - h / 2, width: bounds.width, height: h)
        }
    }
}

#endif
