@testable import RoostDesign
import SwiftUI
import XCTest

final class RoostColorTests: XCTestCase {
    /// Spot checks straight from roost-app-mockup.html.
    func testHexValuesMatchMockup() {
        XCTAssertEqual(RoostColor.bgToken.hex(.light), "#F3F6F2")
        XCTAssertEqual(RoostColor.bgToken.hex(.dark), "#121A15")
        // .app-shell overrides (the app palette) for light; :root dark block for dark
        XCTAssertEqual(RoostColor.accentToken.hex(.light), "#2F8F72")
        XCTAssertEqual(RoostColor.accentToken.hex(.dark), "#6FC2A6")
        XCTAssertEqual(RoostColor.accentSoftToken.hex(.light), "#CFEEE1")
        XCTAssertEqual(RoostColor.goldToken.hex(.light), "#E08F2E")
        XCTAssertEqual(RoostColor.goldSoftToken.hex(.light), "#FBE3C2")
        XCTAssertEqual(RoostColor.infoToken.hex(.light), "#4C7FE0")
        XCTAssertEqual(RoostColor.infoSoftToken.hex(.light), "#DEE6FC")
        XCTAssertEqual(RoostColor.teaseToken.hex(.light), "#D6487A")
        XCTAssertEqual(RoostColor.teaseSoftToken.hex(.light), "#FBDCE8")
        XCTAssertEqual(RoostColor.alertToken.hex(.light), "#E2233F")
        XCTAssertEqual(RoostColor.alertToken.hex(.dark), "#FF6478")
        XCTAssertEqual(RoostColor.alertSoftToken.hex(.light), "#FCD9DF")
        // tokens .app-shell does not override keep the :root light value
        XCTAssertEqual(RoostColor.mealToken.hex(.light), "#C2571F")
        XCTAssertEqual(RoostColor.assignSoftToken.hex(.light), "#E6DFF5")
        XCTAssertEqual(RoostColor.assignSoftToken.hex(.dark), "#332750")
        XCTAssertEqual(RoostColor.inkToken.hex(.light), "#1F2A22")
        XCTAssertEqual(RoostColor.inkToken.hex(.dark), "#EAF2EC")
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
        let appTokens = [
            RoostColor.accentToken, RoostColor.accentSoftToken, RoostColor.goldToken, RoostColor.goldSoftToken,
            RoostColor.infoToken, RoostColor.infoSoftToken, RoostColor.teaseToken, RoostColor.teaseSoftToken,
            RoostColor.alertToken, RoostColor.alertSoftToken,
        ]
        for (page, app) in zip(RoostColor.Page.all, appTokens) {
            XCTAssertEqual(page.dark, app.dark, "\(page.name) dark matches app dark")
            XCTAssertNotEqual(page.light, app.light, "\(page.name) light differs from app light")
        }
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
