@testable import RoostDesign
import SwiftUI
import XCTest

/// The 4-pt scale is documented in the README and in RoostSpacing.swift. If a number changes,
/// both have to change with it, so it is pinned here.
final class RoostSpacingTests: XCTestCase {
    func testScaleIsTheDocumentedNumbers() {
        XCTAssertEqual(RoostSpacing.xxs, 2)
        XCTAssertEqual(RoostSpacing.xs, 4)
        XCTAssertEqual(RoostSpacing.sm, 8)
        XCTAssertEqual(RoostSpacing.md, 12)
        XCTAssertEqual(RoostSpacing.lg, 16)
        XCTAssertEqual(RoostSpacing.xl, 24)
        XCTAssertEqual(RoostSpacing.xxl, 32)
        XCTAssertEqual(RoostSpacing.xxxl, 48)
    }

    func testSemanticValuesAreTheDocumentedNumbers() {
        XCTAssertEqual(RoostSpacing.screenMargin, 16)
        XCTAssertEqual(RoostSpacing.cardPadding, 16)
        XCTAssertEqual(RoostSpacing.rowPadding, 12)
        XCTAssertEqual(RoostSpacing.sectionGap, 24)
        XCTAssertEqual(RoostSpacing.minTapTarget, 44)
    }

    func testScaleAscendsAndStaysOnTheGrid() {
        let values = RoostSpacing.scale.map(\.value)
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(Set(values).count, values.count)
        // Everything but the 2-pt hairline is a multiple of four.
        for (name, value) in RoostSpacing.scale where name != "xxs" {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0, "\(name) is off the 4-pt grid")
        }
    }

    func testSemanticValuesComeFromTheScale() {
        let scale = Set(RoostSpacing.scale.map(\.value))
        for (name, value) in RoostSpacing.semantic {
            XCTAssertTrue(scale.contains(value), "\(name) is not a value on the scale")
        }
    }
}

final class RoostRadiusTests: XCTestCase {
    func testScaleIsTheDocumentedNumbers() {
        XCTAssertEqual(RoostRadius.sm, 6)
        XCTAssertEqual(RoostRadius.md, 10)
        XCTAssertEqual(RoostRadius.lg, 14)
        XCTAssertEqual(RoostRadius.xl, 18)
        XCTAssertEqual(RoostRadius.card, 22)
        XCTAssertEqual(RoostRadius.pill, 999)
        let values = RoostRadius.scale.map(\.value)
        XCTAssertEqual(values, values.sorted())
    }

    func testConcentricInnerSubtractsTheInset() {
        XCTAssertEqual(RoostRadius.concentricInner(outer: RoostRadius.card, inset: RoostSpacing.sm), RoostRadius.lg)
        XCTAssertEqual(RoostRadius.concentricInner(outer: RoostRadius.xl, inset: RoostSpacing.xs), RoostRadius.lg)
    }

    func testConcentricInnerClampsRatherThanGoingSquare() {
        XCTAssertEqual(RoostRadius.concentricInner(outer: RoostRadius.md, inset: RoostSpacing.xl), 4)
        XCTAssertEqual(RoostRadius.concentricInner(outer: 8, inset: 40, minimum: 2), 2)
        XCTAssertEqual(RoostRadius.concentricInner(outer: 8, inset: 0), 8)
    }
}

final class RoostElevationTests: XCTestCase {
    func testStepsAscend() {
        let radii = RoostElevation.all.map(\.radius)
        XCTAssertEqual(radii, radii.sorted())
        let offsets = RoostElevation.all.map(\.yOffset)
        XCTAssertEqual(offsets, offsets.sorted())
    }

    func testDarkModeIsQuieterGeometryAndNeverFullyOpaque() {
        for level in RoostElevation.all {
            XCTAssertLessThan(level.blurRadius(.dark), level.blurRadius(.light), "\(level.name) blur")
            XCTAssertLessThan(level.offsetY(.dark), level.offsetY(.light), "\(level.name) offset")
            XCTAssertGreaterThan(level.darkHairline, 0, "\(level.name) needs a dark hairline")
            XCTAssertLessThan(level.lightOpacity, 1)
            XCTAssertLessThan(level.darkOpacity, 1)
        }
    }

    func testShadowIsInkTintedInLightAndBlackInDark() {
        let light = RoostElevation.card.shadowColor(.light).resolve(in: EnvironmentValues())
        // The mockup's --shadow is rgba(31,42,34,…): a green-black, not pure black.
        XCTAssertGreaterThan(Double(light.green), Double(light.red))
        let dark = RoostElevation.card.shadowColor(.dark).resolve(in: EnvironmentValues())
        XCTAssertEqual(Double(dark.red) + Double(dark.green) + Double(dark.blue), 0, accuracy: 0.01)
    }
}

final class RoostTypeTests: XCTestCase {
    /// The point of the ramp: it grows with the reader's text size.
    func testRampScalesMonotonicallyAcrossSizeCategories() {
        let sizes = DynamicTypeSize.allCases
        for style in RoostType.Style.allCases {
            let scaled = sizes.map { RoostType.scaledSize(style, at: $0) }
            for (smaller, larger) in zip(scaled, scaled.dropFirst()) {
                XCTAssertLessThan(
                    smaller, larger,
                    "\(style.rawValue) does not grow between adjacent size categories"
                )
            }
            XCTAssertEqual(
                RoostType.scaledSize(style, at: .large), style.spec.size, accuracy: 0.0001,
                "\(style.rawValue) should render at its base size at the default text size"
            )
            XCTAssertGreaterThan(
                RoostType.scaledSize(style, at: .accessibility5),
                RoostType.scaledSize(style, at: .large) * 2,
                "\(style.rawValue) should more than double at the largest accessibility size"
            )
        }
    }

    func testReferenceBodySizesAreTheSystemRamp() {
        XCTAssertEqual(RoostType.referenceBodySize(for: .xSmall), 14)
        XCTAssertEqual(RoostType.referenceBodySize(for: .large), 17)
        XCTAssertEqual(RoostType.referenceBodySize(for: .accessibility5), 53)
        XCTAssertEqual(RoostType.multiplier(for: .large), 1)
    }

    /// Every rung's base size is the system size for the text style it tracks, so the fallback
    /// font lands on the same size as the custom one.
    func testEachRungMatchesItsTextStyleSize() {
        let systemSizes: [Font.TextStyle: CGFloat] = [
            .largeTitle: 34, .title: 28, .title2: 22, .title3: 20, .headline: 17,
            .body: 17, .callout: 16, .subheadline: 15, .footnote: 13, .caption: 12, .caption2: 11,
        ]
        for spec in RoostType.all {
            XCTAssertEqual(systemSizes[spec.textStyle], spec.size, "\(spec.name) is off its text style's size")
        }
    }

    func testRampIsOrderedLargestToSmallestWithinEachFace() {
        for face in RoostType.Face.allCases {
            let sizes = RoostType.all.filter { $0.face == face }.map(\.size)
            XCTAssertFalse(sizes.isEmpty, "\(face.rawValue) has no rungs")
            XCTAssertEqual(sizes, sizes.sorted(by: >), "\(face.rawValue) rungs are out of order")
        }
    }

    func testOnlyMonoLabelsCarryTracking() {
        for spec in RoostType.all {
            if spec.name == "monoLabel" {
                XCTAssertGreaterThan(spec.tracking, 0)
            } else {
                XCTAssertEqual(spec.tracking, 0, "\(spec.name) should let the face set its own spacing")
            }
        }
    }

    func testEveryRungIsNamedAfterItsCaseAndDocumented() {
        for style in RoostType.Style.allCases {
            XCTAssertEqual(style.spec.name, style.rawValue)
            XCTAssertFalse(style.spec.usage.isEmpty, "\(style.rawValue) has no usage note")
        }
        XCTAssertEqual(RoostType.all.count, RoostType.Style.allCases.count)
    }

    func testBodyCopyIsNeverSetInTheDisplayOrMonoFace() {
        XCTAssertEqual(RoostType.Style.body.spec.face, .body)
        XCTAssertEqual(RoostType.Style.callout.spec.face, .body)
        XCTAssertEqual(RoostType.Style.subheadline.spec.face, .body)
        XCTAssertGreaterThan(RoostType.Style.body.spec.lineSpacing, 0, "running text needs its reading rhythm")
    }
}

final class RoostColorRoleTests: XCTestCase {
    func testEveryRoleResolvesToADefinedRawToken() {
        let defined = Set(RoostColor.all.map(\.name))
        XCTAssertFalse(defined.isEmpty)
        for role in RoostColor.Role.allCases {
            XCTAssertTrue(
                defined.contains(role.token.name),
                "\(role.rawValue) maps to \(role.token.name), which is not a token in RoostColor.all"
            )
            XCTAssertTrue(
                RoostColor.all.contains(role.token),
                "\(role.rawValue) does not point at the same token instance RoostColor publishes"
            )
        }
    }

    func testRolesResolveTheSameColourAsTheirToken() {
        for role in RoostColor.Role.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let expected = role.token.rgba(scheme)
                let resolved = role.color(scheme).resolve(in: EnvironmentValues())
                XCTAssertEqual(Double(resolved.red), expected.r, accuracy: 0.01, "\(role.rawValue) red \(scheme)")
                XCTAssertEqual(Double(resolved.green), expected.g, accuracy: 0.01, "\(role.rawValue) green \(scheme)")
                XCTAssertEqual(Double(resolved.blue), expected.b, accuracy: 0.01, "\(role.rawValue) blue \(scheme)")
                XCTAssertEqual(Double(resolved.opacity), expected.a, accuracy: 0.01, "\(role.rawValue) alpha \(scheme)")
            }
        }
    }

    /// The mockup's mapping: Anne is the green (.avatar-a / .tally-fill-a), Wes is the blue
    /// (.avatar-p / .tally-fill-p), cat care is the green badge, chores are the gold one.
    /// Anne/Wes/nudge each own a token now (same hex as what they used to borrow).
    func testPeopleAndCategoriesKeepTheMockupsTints() {
        XCTAssertEqual(RoostPerson.anne.role.token.name, "anne")
        XCTAssertEqual(RoostPerson.anne.softRole.token.name, "anneSoft")
        XCTAssertEqual(RoostPerson.wes.role.token.name, "wes")
        XCTAssertEqual(RoostPerson.wes.softRole.token.name, "wesSoft")
        XCTAssertEqual(RoostPerson.anne.role.token.hex(.light), RoostColor.accentToken.hex(.light))
        XCTAssertEqual(RoostPerson.wes.role.token.hex(.light), RoostColor.infoToken.hex(.light))
        XCTAssertEqual(RoostCategory.catCare.role.token.name, "accent")
        XCTAssertEqual(RoostCategory.home.role.token.name, "gold")
        XCTAssertEqual(RoostCategory.meals.role.token.name, "meal")
        XCTAssertEqual(RoostCategory.bonus.role.token.name, "gold")
        XCTAssertNotEqual(
            RoostPerson.anne.role.token,
            RoostPerson.wes.role.token,
            "the two of them need to be told apart"
        )
        XCTAssertNotEqual(
            RoostPerson.anne.role.token,
            RoostColor.Role.accent.token,
            "Anne no longer borrows the accent token"
        )
        XCTAssertNotEqual(
            RoostPerson.wes.role.token,
            RoostColor.Role.notice.token,
            "Wes no longer borrows the notice/info token"
        )
    }

    func testNudgeStageHasItsOwnToken() {
        XCTAssertEqual(RoostColor.Role.nudge.token.name, "nudge")
        XCTAssertEqual(RoostColor.Role.nudgeSoft.token.name, "nudgeSoft")
        XCTAssertEqual(RoostColor.Role.nudge.token.hex(.light), RoostColor.infoToken.hex(.light))
        XCTAssertNotEqual(
            RoostColor.Role.nudge.token,
            RoostColor.Role.notice.token,
            "nudge no longer borrows notice"
        )
    }

    func testStatusLadderUsesThreeDistinctColours() {
        let ladder = [RoostColor.Role.success, .nudge, .warning, .danger].map(\.token.name)
        XCTAssertEqual(Set(ladder).count, 4, "on time, nudge, pointed, and alert must look different")
    }

    func testSoftPartnersPointAtASoftToken() {
        for role in RoostColor.Role.allCases {
            guard let soft = role.soft else { continue }
            XCTAssertTrue(soft.token.name.hasSuffix("Soft"), "\(role.rawValue).soft is \(soft.token.name)")
            XCTAssertNotEqual(soft.token, role.token)
        }
    }

    func testRoleNamesAreUnique() {
        let names = RoostColor.Role.allCases.map(\.rawValue)
        XCTAssertEqual(Set(names).count, names.count)
    }
}

final class RoostMotionTests: XCTestCase {
    func testReduceMotionReturnsANonSpringAnimation() {
        for named in RoostMotion.Named.allCases {
            XCTAssertEqual(RoostMotion.kind(named, reduceMotion: false), .spring, "\(named.rawValue)")
            XCTAssertNotEqual(RoostMotion.kind(named, reduceMotion: true), .spring, "\(named.rawValue)")

            let reduced = String(describing: RoostMotion.reduceMotionAware(named, reduceMotion: true))
            XCTAssertFalse(
                reduced.lowercased().contains("spring"),
                "\(named.rawValue) still animates with a spring under Reduce Motion: \(reduced)"
            )
            let normal = String(describing: RoostMotion.reduceMotionAware(named, reduceMotion: false))
            XCTAssertNotEqual(normal, reduced, "\(named.rawValue) should differ under Reduce Motion")
        }
    }

    func testQuickBecomesInstantAndTheRestCrossFade() {
        XCTAssertEqual(RoostMotion.Named.quick.reducedKind, .instant)
        for named in RoostMotion.Named.allCases where named != .quick {
            XCTAssertEqual(named.reducedKind, .crossFade, "\(named.rawValue)")
        }
    }

    func testDocumentedDurationsAndBounce() {
        XCTAssertEqual(RoostMotion.Named.quick.duration, 0.18)
        XCTAssertEqual(RoostMotion.Named.standard.duration, 0.32)
        XCTAssertEqual(RoostMotion.Named.gentle.duration, 0.45)
        XCTAssertEqual(RoostMotion.Named.bouncyCelebration.duration, 0.60)
        XCTAssertEqual(RoostMotion.Named.quick.bounce, 0)
        XCTAssertEqual(RoostMotion.Named.gentle.bounce, 0)
        XCTAssertGreaterThan(RoostMotion.Named.bouncyCelebration.bounce, RoostMotion.Named.standard.bounce)
        // Reduce Motion substitutes are shorter than the spring they replace.
        for named in RoostMotion.Named.allCases {
            XCTAssertLessThan(named.reducedDuration, named.duration, "\(named.rawValue)")
            XCTAssertFalse(named.usage.isEmpty, "\(named.rawValue) has no guidance")
        }
    }

    func testDurationsAscendWithWeight() {
        let order: [RoostMotion.Named] = [.quick, .standard, .gentle, .bouncyCelebration]
        let durations = order.map(\.duration)
        XCTAssertEqual(durations, durations.sorted())
    }

    func testStaggerCapsAndDisappearsUnderReduceMotion() {
        XCTAssertEqual(RoostMotion.staggerDelay(index: 0), 0)
        XCTAssertEqual(RoostMotion.staggerDelay(index: 3), 0.12, accuracy: 0.0001)
        XCTAssertEqual(RoostMotion.staggerDelay(index: 100), 0.32, accuracy: 0.0001)
        XCTAssertEqual(RoostMotion.staggerDelay(index: 5, reduceMotion: true), 0)
    }

    func testTransitionsFlattenToAFadeUnderReduceMotion() {
        for role in RoostTransition.allCases {
            let reduced = String(describing: role.transition(reduceMotion: true))
            let normal = String(describing: role.transition(reduceMotion: false))
            XCTAssertNotEqual(normal, reduced, "\(role.rawValue) should change under Reduce Motion")
            XCTAssertFalse(
                reduced.lowercased().contains("move") || reduced.lowercased().contains("scale"),
                "\(role.rawValue) still moves under Reduce Motion: \(reduced)"
            )
        }
    }
}

final class RoostHapticTests: XCTestCase {
    func testEveryMomentIsDistinctAndDocumented() {
        let names = RoostHaptic.allCases.map(\.rawValue)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(RoostHaptic.allCases.count, 6)
        for haptic in RoostHaptic.allCases {
            XCTAssertFalse(haptic.usage.isEmpty, "\(haptic.rawValue) has no guidance")
        }
    }

    func testPressIsALightImpactAndNotTheSelectionTick() {
        XCTAssertEqual(
            String(describing: RoostHaptic.press.feedback),
            String(describing: SensoryFeedback.impact(weight: .light))
        )
        XCTAssertNotEqual(
            String(describing: RoostHaptic.press.feedback),
            String(describing: RoostHaptic.selection.feedback)
        )
    }

    func testCheckOffAndUndoDoNotFeelTheSame() {
        XCTAssertNotEqual(
            String(describing: RoostHaptic.checkOff.feedback),
            String(describing: RoostHaptic.undo.feedback)
        )
        XCTAssertEqual(String(describing: RoostHaptic.checkOff.feedback), String(describing: SensoryFeedback.success))
        XCTAssertEqual(String(describing: RoostHaptic.error.feedback), String(describing: SensoryFeedback.error))
    }
}

final class RoostGlassTests: XCTestCase {
    /// Rule 2: exactly one style carries a tint, so a screen cannot tint everything.
    func testOnlyThePrimaryStyleIsTinted() {
        XCTAssertNotNil(RoostGlassStyle.primary.tint)
        XCTAssertNil(RoostGlassStyle.clear.tint)
        XCTAssertNil(RoostGlassStyle.quiet.tint)
        XCTAssertEqual(RoostGlassStyle.all.filter { $0.tint != nil }.count, 1)
    }

    func testOnlyTappableGlassIsInteractive() {
        XCTAssertTrue(RoostGlassStyle.clear.isInteractive)
        XCTAssertTrue(RoostGlassStyle.primary.isInteractive)
        XCTAssertFalse(RoostGlassStyle.quiet.isInteractive)
    }

    func testPrimaryGlassIsTintedWithTheAccent() {
        let tint = RoostGlassStyle.primary.tint?.resolve(in: EnvironmentValues())
        let accent = RoostColor.Role.accent.color(.light).resolve(in: EnvironmentValues())
        XCTAssertEqual(Double(tint?.red ?? -1), Double(accent.red), accuracy: 0.01)
        XCTAssertEqual(Double(tint?.green ?? -1), Double(accent.green), accuracy: 0.01)
    }
}
