// D-10: the appearance choice.
//
// Three small contracts, and each of them is a way the screen could go wrong rather than a restatement of
// the enum. The **raw values** are what sits in `UserDefaults` on a phone that has already been used, so
// renaming one silently resets everybody's choice. The **mapping** is the whole feature: `nil` is what
// "follow the phone" means to SwiftUI, and a `.light` that came back `nil` would look like the setting had
// no effect at all. And the **fallback** is the downgrade path — a value written by a newer build, or junk
// — which has to read as `.system` rather than leave the picker with no selection.
@testable import Roost
import SwiftUI
import XCTest

final class AppearanceTests: XCTestCase {
    // MARK: - what is on disk

    /// The strings a shipped phone already has stored. Changing one is changing everybody's setting back.
    func testTheRawValuesAreTheOnesWrittenToDisk() {
        XCTAssertEqual(Appearance.system.rawValue, "system")
        XCTAssertEqual(Appearance.light.rawValue, "light")
        XCTAssertEqual(Appearance.dark.rawValue, "dark")
        XCTAssertEqual(Appearance.storageKey, "appearance")
    }

    /// Left to right in the segmented control, and the order the menu lists.
    func testTheChoicesComeOutSystemLightDark() {
        XCTAssertEqual(Appearance.allCases, [.system, .light, .dark])
        XCTAssertEqual(Appearance.allCases.map(\.id), ["system", "light", "dark"])
    }

    func testEveryChoiceHasItsOwnTitle() {
        XCTAssertEqual(Appearance.system.title, Strings.Settings.appearanceSystem)
        XCTAssertEqual(Appearance.light.title, Strings.Settings.appearanceLight)
        XCTAssertEqual(Appearance.dark.title, Strings.Settings.appearanceDark)
        XCTAssertEqual(Set(Appearance.allCases.map(\.title)).count, Appearance.allCases.count)
    }

    // MARK: - what the window is told

    /// `nil` is not "no answer" — it is the answer. It is what hands the decision back to iOS, and it is
    /// the only value that lets the phone's own setting still move the app.
    func testSystemOverridesNothing() {
        XCTAssertNil(Appearance.system.colorScheme)
    }

    func testLightAndDarkOverrideThePhone() {
        XCTAssertEqual(Appearance.light.colorScheme, .light)
        XCTAssertEqual(Appearance.dark.colorScheme, .dark)
    }

    // MARK: - reading it back

    /// A phone that has never been to Settings.
    func testNothingStoredIsSystem() {
        XCTAssertEqual(Appearance.stored(nil), .system)
    }

    func testAStoredChoiceComesBack() {
        XCTAssertEqual(Appearance.stored("system"), .system)
        XCTAssertEqual(Appearance.stored("light"), .light)
        XCTAssertEqual(Appearance.stored("dark"), .dark)
    }

    /// A value from a newer build, a leftover, an empty string, a case that does not match. All of them are
    /// the system appearance, which is the one state that is never wrong.
    func testAnythingElseIsSystem() {
        for raw in ["", "sepia", "Dark", "true", "  light  ", "0"] {
            XCTAssertEqual(Appearance.stored(raw), .system, "'\(raw)' should fall back rather than stick")
        }
    }

    /// The same read the app makes, through a real `UserDefaults` rather than a literal: `@AppStorage`
    /// hands over whatever string is under the key, and `stored` is the only thing between that and the
    /// window's colour scheme.
    func testAJunkValueUnderTheKeyReadsAsSystem() throws {
        let suite = "roost-appearance-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(Appearance.stored(defaults.string(forKey: Appearance.storageKey)), .system)

        defaults.set("dark", forKey: Appearance.storageKey)
        XCTAssertEqual(Appearance.stored(defaults.string(forKey: Appearance.storageKey)), .dark)

        defaults.set("moonlight", forKey: Appearance.storageKey)
        XCTAssertEqual(Appearance.stored(defaults.string(forKey: Appearance.storageKey)), .system)
    }

    /// Round trip: what the picker writes is what the app reads.
    func testWhatThePickerWritesIsWhatTheAppReads() {
        for choice in Appearance.allCases {
            XCTAssertEqual(Appearance.stored(choice.rawValue), choice)
        }
    }
}
