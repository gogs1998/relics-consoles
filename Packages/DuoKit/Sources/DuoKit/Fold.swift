import CoreGraphics
import SwiftUI

/// What an app needs to know about the hinge, expressed without depending on the Duo
/// SDK existing. `DuoSDK` fills this in from the real reserved-region API when built
/// against Xcode 27.1+; consumers only ever talk to this.
public struct Fold: Equatable, Sendable {

    /// True only while the device is actually folded. A flat phone — Duo or otherwise
    /// — reports `false` and an empty rect.
    public var isActive: Bool

    /// The division region's frame in the stage's coordinate space (points). Can be
    /// non-empty while inactive, when the SDK can say where the hinge *would* be, so
    /// layout and renderers can pre-warm and transitions don't pop.
    ///
    /// Per UIKit's `UIViewReservedRegion.h`, this frame **includes** `margins`.
    public var frame: CGRect

    /// The inset within `frame` that interactive content should stay clear of. Zero
    /// for a simulated fold, and before the SDK reports one.
    public var margins: EdgeInsets

    /// True when this fold came from the debug simulator rather than the OS. The pose
    /// detector needs to know: a simulated hinge has a frame, so "is the frame empty?"
    /// cannot tell real from pretend — and asking that is exactly what broke tent pose
    /// in 0.1.0, falling through to gravity the Simulator does not have.
    public var isSimulated: Bool

    public init(isActive: Bool = false, frame: CGRect = .zero, isSimulated: Bool = false,
                margins: EdgeInsets = EdgeInsets()) {
        self.isActive = isActive
        self.frame = frame
        self.isSimulated = isSimulated
        self.margins = margins
    }

    /// The physical crease: `frame` with `margins` removed. Equal to `frame` when the
    /// margins are zero, and empty when `frame` is.
    public var creaseFrame: CGRect {
        guard !frame.isEmpty else { return frame }
        return CGRect(x: frame.minX + margins.leading,
                      y: frame.minY + margins.top,
                      width: max(0, frame.width - margins.leading - margins.trailing),
                      height: max(0, frame.height - margins.top - margins.bottom))
    }

    public static let flat = Fold()

    /// Which way the hinge band runs, derived from the region's own shape rather than
    /// from interface orientation — which Apple explicitly tells us not to trust on the
    /// inner display.
    public enum Axis: Sendable { case horizontal, vertical }

    /// `.horizontal` is a wide, short band dividing the display into top and bottom.
    public var axis: Axis {
        frame.width >= frame.height ? .horizontal : .vertical
    }

    public var midpoint: CGFloat {
        axis == .horizontal ? frame.midY : frame.midX
    }

    /// The half a person can comfortably reach while the device stands on its edges.
    ///
    /// Apple's rule: in a partial fold the system displaces its own alerts, sheets and
    /// menus to the bottom half for stability. Custom layouts are expected to do the
    /// same, and this is how.
    public func nearHalf(in bounds: CGRect) -> CGRect {
        guard isActive, !frame.isEmpty else { return bounds }
        switch axis {
        case .horizontal:
            let top = frame.maxY
            return CGRect(x: bounds.minX, y: top, width: bounds.width, height: bounds.maxY - top)
        case .vertical:
            let lead = frame.maxX
            return CGRect(x: lead, y: bounds.minY, width: bounds.maxX - lead, height: bounds.height)
        }
    }

    /// The opposite half — the one facing away from whoever is holding the device.
    /// This is the surface that makes two-sided apps possible.
    public func farHalf(in bounds: CGRect) -> CGRect {
        guard isActive, !frame.isEmpty else { return .zero }
        switch axis {
        case .horizontal:
            return CGRect(x: bounds.minX, y: bounds.minY,
                          width: bounds.width, height: frame.minY - bounds.minY)
        case .vertical:
            return CGRect(x: bounds.minX, y: bounds.minY,
                          width: frame.minX - bounds.minX, height: bounds.height)
        }
    }
}

/// The poses an app can meaningfully behave differently in.
///
/// This is a *behavioural* summary — what the app should DO (which way is up, who can
/// see what) — never a layout instruction. Apple's rule stands: lay out from size
/// classes and reserved regions, not from a pose enum.
public enum DuoPose: String, Sendable, CaseIterable, Identifiable {
    /// Open flat, or an ordinary non-folding iPhone.
    case flat
    /// Vertical fold, both halves facing the person holding it — an open book.
    /// Apple displaces alerts to the trailing half here, which only makes sense
    /// because the user can see both halves.
    case book
    /// Horizontal fold, lower half lying on the surface, upper half tilted up like a
    /// laptop lid. Both halves face the same person. Apple's guidance: top half for
    /// distant viewing, bottom half for touch controls.
    case table
    /// Horizontal fold, standing on its edges in a lambda. The two halves face
    /// **opposite directions** — one screen each for two different people.
    /// This is the pose no slab phone can imitate, and the one two-sided apps need.
    case tent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .flat:  return "Flat"
        case .book:  return "Book"
        case .table: return "Table"
        case .tent:  return "Tent"
        }
    }

    /// Whether the two halves face different people. Only true in tent pose — this is
    /// the flag every two-sided app should gate its second surface on.
    public var isTwoSided: Bool { self == .tent }

    /// In tent pose the far half faces the other way, so its viewer sees a
    /// 180-degree rotation of whatever is drawn there. Content intended for that
    /// person has to be counter-rotated or they read it upside down.
    public var farHalfIsRotated: Bool { self == .tent }

    /// What the fold alone can tell you.
    ///
    /// Deliberately conservative: the division region reports an axis and nothing else,
    /// and a horizontal fold is `.table` *or* `.tent` depending on how the device is
    /// physically standing. The reserved-region API cannot distinguish them — only
    /// gravity can. Assume the safer of the two and let `PoseDetector` upgrade it.
    public init(fold: Fold) {
        guard fold.isActive else { self = .flat; return }
        self = fold.axis == .horizontal ? .table : .book
    }
}
