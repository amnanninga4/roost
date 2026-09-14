@testable import RoostDesign
import SwiftUI
import XCTest

final class RoostPressStyleTests: XCTestCase {
    /// The numbers the spec sets for a touch-down: 0.97 scale, 0.85 opacity.
    func testThePressVocabularyIsTheDocumentedNumbers() {
        XCTAssertEqual(RoostButtonStyle.pressedScale, 0.97)
        XCTAssertEqual(RoostButtonStyle.pressedOpacity, 0.85)
    }

    func testTheQuietVariantOnlySkipsTheHaptic() {
        XCTAssertTrue(RoostButtonStyle().firesHaptic)
        XCTAssertFalse(RoostButtonStyle(haptic: false).firesHaptic)
    }
}

final class RoostAvatarTests: XCTestCase {
    /// The ceiling the app's `listGlyphCeiling` pinned before the component absorbed it: past this a
    /// badge stops reading as decoration.
    func testTheGlyphCeilingIsTheDocumentedValue() {
        XCTAssertEqual(RoostAvatar.glyphCeiling, RoostSpacing.xxl + RoostSpacing.sm)
    }

    func testBothPeopleAreOffered() {
        for person in RoostPerson.allCases {
            let avatar = RoostAvatar(person: person)
            XCTAssertEqual(avatar.person, person)
        }
    }
}
