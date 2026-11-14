import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import DuoKit

private let horizontal = Fold(isActive: true, frame: CGRect(x: 0, y: 455, width: 669, height: 40))
private let vertical = Fold(isActive: true, frame: CGRect(x: 314, y: 0, width: 40, height: 951))

/// |gravity.y| for a half tilted `degrees` off horizontal.
private func g(_ degrees: Double) -> Double { -sin(degrees * .pi / 180) }

private func partial(_ degrees: Double) -> HingeReading {
    HingeReading(degrees: degrees, isPartiallyOpen: true)
}

@Suite("PoseClassifier")
struct PoseClassifierTests {

    // MARK: Fold geometry decides before gravity does

    @Test func inactiveFoldIsFlat() {
        #expect(PoseClassifier.classify(fold: .flat, hinge: nil, gravityY: g(90)) == .flat)
    }

    @Test func verticalFoldIsBook() {
        #expect(PoseClassifier.classify(fold: vertical, hinge: partial(90), gravityY: g(45)) == .book)
    }

    @Test func fullyOpenHingeIsFlatEvenIfRegionLags() {
        let open = HingeReading(degrees: 180, isPartiallyOpen: false)
        #expect(open.isFullyOpen)
        #expect(PoseClassifier.classify(fold: horizontal, hinge: open, gravityY: g(45)) == .flat)
    }

    @Test func closedHingeNeverClaimsTent() {
        let closed = HingeReading(degrees: 0, isPartiallyOpen: false, isClosed: true)
        #expect(!closed.isFullyOpen)
        #expect(PoseClassifier.classify(fold: horizontal, hinge: closed, gravityY: g(90)) == .table)
    }

    @Test func noGravityIsTable() {
        #expect(PoseClassifier.classify(fold: horizontal, hinge: partial(90), gravityY: nil) == .table)
        #expect(PoseClassifier.classify(fold: horizontal, hinge: nil, gravityY: nil) == .table)
    }

    // MARK: No hinge angle: the 0.1.1 behaviour, unchanged

    @Test(arguments: [(-0.9, DuoPose.tent), (0.9, .tent), (-0.51, .tent),
                      (-0.5, .table), (-0.1, .table), (0, .table)])
    func legacyGravityOnly(gravityY: Double, expected: DuoPose) {
        #expect(PoseClassifier.classify(fold: horizontal, hinge: nil, gravityY: gravityY) == expected)
    }

    // MARK: With a hinge angle

    @Test(arguments: [75.0, 90, 105, 120, 135, 145])
    func symmetricTentIsTent(alpha: Double) {
        let tilt = (180 - alpha) / 2
        #expect(PoseClassifier.classify(fold: horizontal, hinge: partial(alpha), gravityY: g(tilt)) == .tent)
    }

    @Test(arguments: [70.0, 90, 110, 130, 145])
    func laptopWithImuInBaseIsTable(alpha: Double) {
        #expect(PoseClassifier.classify(fold: horizontal, hinge: partial(alpha), gravityY: g(1)) == .table)
    }

    /// The 0.1.1 bug: an L with the IMU in the lid read as tent, because the lid is
    /// upright and |gravity.y| is large.
    @Test(arguments: [70.0, 90, 110, 130, 145])
    func laptopWithImuInLidIsTable(alpha: Double) {
        let lid = 180 - alpha
        #expect(PoseClassifier.classify(fold: horizontal, hinge: partial(alpha), gravityY: g(lid)) == .table)
    }

    /// The other 0.1.1 bug: a slightly bent phone held upright in the hand.
    @Test(arguments: [150.0, 160, 170, 178])
    func slightlyBentInHandIsTable(alpha: Double) {
        for tilt in stride(from: 0.0, through: 90, by: 10) {
            #expect(PoseClassifier.classify(fold: horizontal, hinge: partial(alpha), gravityY: g(tilt)) == .table)
        }
    }

    @Test func tentIsOnlyAllowedBelowGate() {
        #expect(PoseClassifier.horizontalPose(hingeDegrees: 149, gravityY: g(15.5)) == .tent)
        #expect(PoseClassifier.horizontalPose(hingeDegrees: 150, gravityY: g(15)) == .table)
    }

    @Test func heldUprightWithModerateFoldIsTable() {
        // α = 140: tent predicts 20°, table predicts 0° or 40°. Upright in a hand is ~80°.
        #expect(PoseClassifier.horizontalPose(hingeDegrees: 140, gravityY: g(80)) == .table)
    }

    /// Below 90° the lid leans back past vertical and |gravity.y| folds back: at α = 60
    /// the lid and a tent half both read 60°. Ambiguous, so the safer answer wins.
    @Test func ambiguityGoesToTable() {
        #expect(PoseClassifier.horizontalPose(hingeDegrees: 60, gravityY: g(60)) == .table)
    }

    @Test func boundariesAtNinetyDegrees() {
        // α = 90: tent 45°, table 0° / 90°. Midpoints at 22.5° and 67.5°.
        #expect(PoseClassifier.horizontalPose(hingeDegrees: 90, gravityY: g(22)) == .table)
        #expect(PoseClassifier.horizontalPose(hingeDegrees: 90, gravityY: g(23)) == .tent)
        #expect(PoseClassifier.horizontalPose(hingeDegrees: 90, gravityY: g(67)) == .tent)
        #expect(PoseClassifier.horizontalPose(hingeDegrees: 90, gravityY: g(68)) == .table)
    }

    @Test func outOfRangeInputsDoNotTrap() {
        #expect(PoseClassifier.horizontalPose(hingeDegrees: -10, gravityY: 1.3) == .tent)
        #expect(PoseClassifier.classify(fold: horizontal, hinge: partial(.nan), gravityY: -0.9) == .tent)
        #expect(PoseClassifier.classify(fold: horizontal, hinge: partial(90), gravityY: .nan) == .table)
    }
}

@Suite("PoseHysteresis")
struct PoseHysteresisTests {

    @Test func firstSampleIsImmediate() {
        var h = PoseHysteresis()
        #expect(h.feed(.tent) == .tent)
    }

    @Test func needsThreeAgreeingSamplesToSwitch() {
        var h = PoseHysteresis(required: 3)
        _ = h.feed(.table)
        #expect(h.feed(.tent) == .table)
        #expect(h.feed(.tent) == .table)
        #expect(h.feed(.tent) == .tent)
        #expect(h.feed(.table) == .tent)
    }

    @Test func interruptedRunStartsAgain() {
        var h = PoseHysteresis(required: 3)
        _ = h.feed(.tent)
        #expect(h.feed(.table) == .tent)
        #expect(h.feed(.table) == .tent)
        #expect(h.feed(.tent) == .tent)      // run broken
        #expect(h.feed(.table) == .tent)
        #expect(h.feed(.table) == .tent)
        #expect(h.feed(.table) == .table)
    }

    @Test func foldStateChangesAreImmediate() {
        var h = PoseHysteresis(required: 3)
        _ = h.feed(.tent)
        #expect(h.feed(.flat) == .flat)
        #expect(h.feed(.table) == .table)
        #expect(h.feed(.book) == .book)
        #expect(h.feed(.tent) == .tent)
    }

    @Test func requiredOfOneSwitchesAtOnce() {
        var h = PoseHysteresis(required: 1)
        _ = h.feed(.table)
        #expect(h.feed(.tent) == .tent)
    }
}

@Suite("DuoPoseOverride")
struct DuoPoseOverrideTests {

    @Test func automaticPassesThrough() {
        for pose in DuoPose.allCases {
            #expect(DuoPoseOverride.automatic.apply(to: pose) == pose)
        }
    }

    @Test func forcesOnlyBetweenTableAndTent() {
        #expect(DuoPoseOverride.forceTent.apply(to: .table) == .tent)
        #expect(DuoPoseOverride.forceTent.apply(to: .tent) == .tent)
        #expect(DuoPoseOverride.forceTable.apply(to: .tent) == .table)
        #expect(DuoPoseOverride.forceTable.apply(to: .table) == .table)
        for force in [DuoPoseOverride.forceTent, .forceTable] {
            #expect(force.apply(to: .flat) == .flat)
            #expect(force.apply(to: .book) == .book)
        }
    }

    @Test func persistsInUserDefaults() {
        let saved = UserDefaults.standard.string(forKey: DuoPoseOverride.storageKey)
        defer { UserDefaults.standard.set(saved, forKey: DuoPoseOverride.storageKey) }

        DuoPoseOverride.current = .forceTent
        #expect(UserDefaults.standard.string(forKey: DuoPoseOverride.storageKey) == "forceTent")
        #expect(DuoPoseOverride.current == .forceTent)
        DuoPoseOverride.current = .automatic
        #expect(UserDefaults.standard.string(forKey: DuoPoseOverride.storageKey) == nil)
        #expect(DuoPoseOverride.current == .automatic)
    }
}

@Suite("Fold margins")
struct FoldMarginTests {

    @Test func defaultMarginsLeaveCreaseEqualToFrame() {
        #expect(horizontal.margins == EdgeInsets())
        #expect(horizontal.creaseFrame == horizontal.frame)
        #expect(Fold.flat.creaseFrame.isEmpty)
    }

    @Test func creaseIsFrameInsetByMargins() {
        let fold = Fold(isActive: true, frame: CGRect(x: 0, y: 450, width: 669, height: 40),
                        margins: EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
        #expect(fold.creaseFrame == CGRect(x: 0, y: 462, width: 669, height: 16))
        #expect(fold.axis == .horizontal)
    }

    @Test func marginsTakePartInEquality() {
        var a = horizontal
        a.margins = EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0)
        #expect(a != horizontal)
    }
}
