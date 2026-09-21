@testable import RoostDesign
import SwiftUI
import XCTest

final class RoostColorTests: XCTestCase {
    func testHouseholdPaletteIdentity() {
        XCTAssertEqual(RoostColor.bgToken.hex(.dark), "#071323")
        XCTAssertEqual(RoostColor.accentToken.hex(.dark), "#00DDD3")
        XCTAssertEqual(RoostColor.anneToken.hex(.dark), "#A0ECD5")
        XCTAssertEqual(RoostColor.wesToken.hex(.dark), "#F3A0C1")
    }

    func testTextAndActionsHaveReadableContrastInBothAppearances() {
        func luminance(_ token: RoostColorToken, _ scheme: ColorScheme) -> Double {
            let c = token.rgba(scheme)
            func linear(_ v: Double) -> Double {
                v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
        }
        for scheme in [ColorScheme.light, .dark] {
            for background in [RoostColor.bgToken, RoostColor.surfaceToken, RoostColor.surface2Token] {
                for foreground in [RoostColor.inkToken, RoostColor.inkSoftToken,
                                   RoostColor.accentToken, RoostColor.anneToken, RoostColor.wesToken,
                                   RoostColor.nudgeToken, RoostColor.teaseToken, RoostColor.alertToken]
                {
                    let a = luminance(foreground, scheme), b = luminance(background, scheme)
                    XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5,
                                                "\(foreground.name) on \(background.name), \(scheme)")
                }
            }
        }
    }

    func testShadowAlpha() {
        let l = RoostColor.shadowToken.rgba(.light)
        XCTAssertEqual(l.a, 0.14, accuracy: 0.0001)
        XCTAssertEqual(Int(round(l.r * 255)), 31)
        XCTAssertEqual(Int(round(l.g * 255)), 42)
        XCTAssertEqual(Int(round(l.b * 255)), 34)
        let d = RoostColor.shadowToken.rgba(.dark)
        XCTAssertEqual(d.a, 0.45, accuracy: 0.0001)
        XCTAssertEqual(d.r + d.g + d.b, 0)
    }

    /// The marketing-page palette stays reachable under RoostColor.Page with the :root light values.
    func testPagePaletteKeepsRootLightValues() {
        XCTAssertEqual(RoostColor.Page.accentToken.hex(.light), "#2F6F5E")
        XCTAssertEqual(RoostColor.Page.goldToken.hex(.light), "#B9812E")
        XCTAssertEqual(RoostColor.Page.infoToken.hex(.light), "#3E6B8A")
        XCTAssertEqual(RoostColor.Page.teaseToken.hex(.light), "#AE4568")
        XCTAssertEqual(RoostColor.Page.alertToken.hex(.light), "#C81E3A")
        XCTAssertEqual(RoostColor.Page.alertSoftToken.hex(.light), "#FBDCE1")
        XCTAssertEqual(RoostColor.Page.all.count, 10)
    }

    func testTokenCountAndUniqueNames() {
        XCTAssertEqual(RoostColor.all.count, 27)
        XCTAssertEqual(Set(RoostColor.all.map(\.name)).count, 27)
        XCTAssertEqual(RoostColor.pairs.count, 10)
    }

    /// Resolves each dynamic color through the platform and checks it round-trips to the token hex.
    func testDynamicColorsResolvePerScheme() {
        for token in RoostColor.all + RoostColor.Page.all {
            for scheme in [ColorScheme.light, .dark] {
                let expected = token.rgba(scheme)
                let resolved = token.color.resolve(in: environment(scheme))
                XCTAssertEqual(Double(resolved.red), expected.r, accuracy: 0.01, "\(token.name) red \(scheme)")
                XCTAssertEqual(Double(resolved.green), expected.g, accuracy: 0.01, "\(token.name) green \(scheme)")
                XCTAssertEqual(Double(resolved.blue), expected.b, accuracy: 0.01, "\(token.name) blue \(scheme)")
                XCTAssertEqual(Double(resolved.opacity), expected.a, accuracy: 0.01, "\(token.name) alpha \(scheme)")
            }
        }
    }

    private func environment(_ scheme: ColorScheme) -> EnvironmentValues {
        var env = EnvironmentValues()
        env.colorScheme = scheme
        return env
    }
}

final class RoostFontTests: XCTestCase {
    func testBundledFilesRegisterAndFamiliesBecomeAvailable() throws {
        try RoostFonts.register()
        XCTAssertTrue(RoostFont.isAvailable(RoostFont.Family.display), "Fraunces")
        XCTAssertTrue(RoostFont.isAvailable(RoostFont.Family.body), "Nunito Sans")
        XCTAssertTrue(RoostFont.isAvailable(RoostFont.Family.mono), "IBM Plex Mono")
        // second call is a no-op, not an error
        XCTAssertEqual(try RoostFonts.register(), [])
    }

    func testLicensesShipNextToFonts() {
        for lic in ["OFL-Fraunces.txt", "OFL-NunitoSans.txt", "OFL-IBMPlexMono.txt"] {
            XCTAssertNotNil(Bundle.module.url(forResource: lic, withExtension: nil, subdirectory: "Fonts"), lic)
        }
    }
}
