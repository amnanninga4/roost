// The person avatar the app's rows used to assemble by hand: the initial on a filled circle in the
// person's own colours, driven by `RoostPerson` so no screen names a colour. The accessibility label
// is a parameter because what the avatar *means* is the caller's to say — "Added by Anne" on a list
// row, "For Wes" on a project step.
import SwiftUI

public struct RoostAvatar: View {
    /// Past this, a badge stops reading as decoration: a 24-pt circle at three times the text size is
    /// a button, not a marker. The value the app's `listGlyphCeiling` pinned before this component
    /// absorbed it.
    public static let glyphCeiling: CGFloat = RoostSpacing.xxl + RoostSpacing.sm

    public let person: RoostPerson
    /// What VoiceOver says for the avatar. Defaults to the person's name; callers pass the meaning.
    public let label: String?

    @ScaledMetric(relativeTo: .caption) private var scaled: CGFloat = RoostSpacing.xl

    public init(person: RoostPerson, label: String? = nil) {
        self.person = person
        self.label = label
    }

    private var side: CGFloat {
        min(scaled, Self.glyphCeiling)
    }

    public var body: some View {
        Text(String(person.shortName.prefix(1)))
            .roostType(.caption)
            .fontWeight(.bold)
            .foregroundStyle(RoostColor.Role.onAccent.color)
            .frame(width: side, height: side)
            .background(person.color, in: Circle())
            .accessibilityLabel(label ?? person.shortName)
    }
}
