import SwiftUI

/// Everything an app needs to know about the surface it is drawing on, resolved once
/// per layout pass.
public struct DuoStage: Equatable, Sendable {
    /// The full view bounds.
    public var bounds: CGRect
    /// The area to actually draw in. Identical to `bounds` on real hardware; in debug
    /// builds without the Duo SDK it is letterboxed to the inner display's 1.42 ratio.
    public var canvas: CGRect
    public var fold: Fold
    /// The pose to behave in: detected, then the user's `DuoPoseOverride` applied.
    public var pose: DuoPose
    /// The half within reach of whoever is holding the device.
    public var nearHalf: CGRect
    /// The half facing away. Empty unless folded. In tent pose this belongs to a
    /// second person.
    public var farHalf: CGRect
    public var safeArea: EdgeInsets
    /// True while the hinge reports `.closed`. Always false where there is no hinge.
    public var isClosed: Bool = false
    /// The manual override in force when this stage was resolved.
    public var poseOverride: DuoPoseOverride = .automatic

    public var isTwoSided: Bool { pose.isTwoSided }
}

/// The container every DuoKit app builds on.
///
/// Resolves the fold (real SDK, or simulated in debug), the pose (fold axis plus
/// gravity and hinge angle), and the two halves, then hands them to your content.
/// Start a `PoseDetector` and pass it in to get `.tent` distinguished from `.table`;
/// without one, a horizontal fold is reported conservatively as `.table`. Either way
/// the stored `DuoPoseOverride` is applied last.
public struct DuoStageReader<Content: View>: View {
    private let detector: PoseDetector?
    private let content: (DuoStage) -> Content

    @State private var isClosed = false
    @AppStorage(DuoPoseOverride.storageKey) private var poseOverride: DuoPoseOverride = .automatic

    #if DEBUG
    @State private var sim = FoldSimulator.shared
    #endif

    public init(detector: PoseDetector? = nil,
                @ViewBuilder content: @escaping (DuoStage) -> Content) {
        self.detector = detector
        self.content = content
    }

    public var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let canvas = resolvedCanvas(bounds, proxy: proxy)
            let fold = resolvedFold(proxy: proxy, canvas: canvas)
            let stage = DuoStage(
                bounds: bounds,
                canvas: canvas,
                fold: fold,
                pose: poseOverride.apply(to: detectedPose(fold: fold)),
                nearHalf: fold.nearHalf(in: canvas),
                farHalf: fold.farHalf(in: canvas),
                safeArea: proxy.safeAreaInsets,
                isClosed: isClosed,
                poseOverride: poseOverride
            )

            content(stage)
                .onChange(of: fold, initial: true) { _, new in detector?.update(fold: new) }
        }
        .duoOnHingeChange { reading in
            isClosed = reading?.isClosed ?? false
            detector?.update(hinge: reading)
        }
    }

    /// The pose before the override.
    ///
    /// A simulated fold reads the simulator directly: table and tent share one
    /// simulated `Fold`, so anything keyed on the fold changing — the detector's
    /// `update(fold:)` included — would never see that switch.
    private func detectedPose(fold: Fold) -> DuoPose {
        #if DEBUG
        if fold.isSimulated { return sim.pose }
        #endif
        return detector?.pose ?? DuoPose(fold: fold)
    }

    /// True when the OS is new enough *and* this display actually has a hinge. An
    /// iPhone 18 on iOS 27.1 satisfies the first and not the second, so asking the OS
    /// version alone would switch the development harness off on every ordinary phone.
    private func hasRealFold(proxy: GeometryProxy) -> Bool {
        !DuoSDK.fold(from: proxy).frame.isEmpty
    }

    private func resolvedCanvas(_ bounds: CGRect, proxy: GeometryProxy) -> CGRect {
        #if DEBUG
        if !hasRealFold(proxy: proxy) { return sim.canvas(in: bounds) }
        #endif
        return bounds
    }

    private func resolvedFold(proxy: GeometryProxy, canvas: CGRect) -> Fold {
        if hasRealFold(proxy: proxy) { return DuoSDK.fold(from: proxy) }
        #if DEBUG
        return sim.fold(in: canvas)
        #else
        return .flat
        #endif
    }
}

extension View {
    /// Counter-transforms content drawn on the far half so the person on the other
    /// side sees it the right way up.
    ///
    /// Only tent pose needs this. In book and table pose both halves face the same
    /// person, and rotating either one would be actively wrong.
    @ViewBuilder
    public func duoFarHalfOrientation(_ pose: DuoPose) -> some View {
        if pose.farHalfIsRotated {
            self.rotationEffect(.degrees(180))
        } else {
            self
        }
    }
}
