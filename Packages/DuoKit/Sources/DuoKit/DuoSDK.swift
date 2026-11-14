import SwiftUI

/// The entire Duo-only API surface, in one file.
///
/// Verified against the iOS 27.1 SDK on 23 September 2026 by reading
/// `SwiftUICore.swiftinterface` directly, not from the Tech Talks. Three things the
/// talks left me believing that turned out to be wrong are corrected here.
///
/// Everything is gated at **runtime**, not behind a compile flag. The slate's rule is
/// Duo-native, not Duo-only: one binary runs on every iPhone and simply finds no fold
/// on the ones that do not bend.
public enum DuoSDK {

    /// True when this device's OS knows what a fold is.
    public static var isAvailable: Bool {
        if #available(iOS 27.1, *) { return true }
        return false
    }

    /// The hinge, if this display has one.
    ///
    /// **Correction:** a region carries its own `isActive`. The earlier shim asserted
    /// that foldedness had to be inferred from whether an active-only query returned
    /// anything — it does not, and that would have meant two queries where one does.
    /// Asking with `.includeInactive` and reading the flag gives the frame *and* the
    /// state together, which is also how the geometry stays stable across a fold
    /// instead of popping when the region appears.
    public static func fold(from proxy: GeometryProxy) -> Fold {
        guard #available(iOS 27.1, *) else { return .flat }
        let regions = proxy.reservedRegions(kind: .division, options: .includeInactive)
        guard let region = regions.first else { return .flat }
        // The frame already includes `margins`; they are the inset that interactive
        // content should keep clear of. Both are carried so `Fold.creaseFrame` can
        // recover the physical crease.
        return Fold(isActive: region.isActive, frame: region.frame, margins: region.margins)
    }

    /// The inner camera is an occlusion region, active only while the camera is. Tent
    /// and Round do not use the camera; this is here for whichever app eventually does.
    public static func occlusions(from proxy: GeometryProxy) -> [CGRect] {
        guard #available(iOS 27.1, *) else { return [] }
        return proxy.reservedRegions(kind: .occlusion).map(\.frame)
    }
}

/// A hinge reading. `nil` where the device has no hinge.
public struct HingeReading: Equatable, Sendable {
    /// Degrees open. Verified real: `DeviceHinge.angle` exists and is an `Angle`.
    public var degrees: Double
    public var isPartiallyOpen: Bool
    public var isClosed: Bool

    /// Neither partially open nor closed: the SDK's `.fullyOpen`. The device is flat.
    public var isFullyOpen: Bool { !isPartiallyOpen && !isClosed }

    public init(degrees: Double, isPartiallyOpen: Bool, isClosed: Bool = false) {
        self.degrees = degrees
        self.isPartiallyOpen = isPartiallyOpen
        self.isClosed = isClosed
    }
}

extension View {
    /// Live hinge angle — a continuous analogue input no slab phone has.
    ///
    /// **Correction:** the handler takes *two* contexts, old and new, not one. And the
    /// modifier carries an `isEnabled:`, so it can be left in place and switched off
    /// rather than conditionally applied.
    @ViewBuilder
    public func duoOnHingeChange(isEnabled: Bool = true,
                                 _ handler: @escaping (HingeReading?) -> Void) -> some View {
        if #available(iOS 27.1, *) {
            self.onHingeChange(isEnabled: isEnabled) { _, context in
                guard let hinge = context.hinge else {
                    handler(nil)
                    return
                }
                handler(HingeReading(degrees: hinge.angle.degrees,
                                     isPartiallyOpen: hinge.status == .partiallyOpen,
                                     isClosed: hinge.status == .closed))
            }
        } else {
            self
        }
    }

    /// For single-page, bottom-heavy apps with no toolbar. Apple's guidance is that
    /// these opt out of the vertical bar rather than leave an empty rail down the side
    /// of the inner display.
    ///
    /// **Correction:** the type is `ToolbarVerticalBehavior` with `.automatic` and
    /// `.disabled`. Not `.hidden`, which was never a case.
    @ViewBuilder
    public func duoDisablesVerticalBar() -> some View {
        if #available(iOS 27.1, *) {
            self.toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
    }
}
