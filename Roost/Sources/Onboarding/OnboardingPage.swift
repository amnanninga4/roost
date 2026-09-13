// The shape every onboarding screen shares: eyebrow, title, one line, the screen's own content, and a
// footer pinned to the bottom of the safe area.
//
// The footer is a `safeAreaInset` rather than an overlay, so at the largest accessibility text size the
// content scrolls above the button instead of under it. One purpose per screen, and the thing to tap is
// where the thumb already is.
import RoostCore
import RoostDesign
import SwiftUI

extension Person {
    /// The design system's person, so a screen can take a `RoostCore.Person` and get a colour out of it
    /// without naming the colour. Anne is the green, Wes is the blue, as in the mockup's avatars.
    var design: RoostPerson {
        switch self {
        case .anne: .anne
        case .wes: .wes
        }
    }

    /// "A" / "W" — the avatar letter, taken from the display name so there is one place to rename a person.
    var initial: String {
        String(displayName.prefix(1))
    }
}

struct OnboardingPage<Content: View, Footer: View>: View {
    let eyebrow: String
    let title: String
    let line: String
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    init(
        eyebrow: String,
        title: String,
        line: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.line = line
        self.content = content()
        self.footer = footer()
    }

    /// A page with nothing pinned to the bottom.
    init(eyebrow: String, title: String, line: String, @ViewBuilder content: () -> Content)
        where Footer == EmptyView
    {
        self.init(eyebrow: eyebrow, title: title, line: line, content: content) { EmptyView() }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RoostSpacing.lg) {
                VStack(alignment: .leading, spacing: RoostSpacing.sm) {
                    Text(eyebrow)
                        .roostType(.monoLabel)
                        .foregroundStyle(RoostColor.Role.accent.color)
                    Text(title)
                        .roostType(.displayLarge)
                        .foregroundStyle(RoostColor.Role.textPrimary.color)
                    Text(line)
                        .roostType(.body)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                }
                .accessibilityElement(children: .combine)

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RoostSpacing.screenMargin)
            .padding(.top, RoostSpacing.xl)
            .padding(.bottom, RoostSpacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(RoostColor.Role.background.color)
        .safeAreaInset(edge: .bottom) {
            // The code screen has no footer — its keyboard is the bottom of the screen — so it inherits
            // nothing but padding, and this keeps even that off it.
            if Footer.self != EmptyView.self {
                footer
                    .padding(.horizontal, RoostSpacing.screenMargin)
                    .padding(.top, RoostSpacing.md)
                    .padding(.bottom, RoostSpacing.sm)
            }
        }
    }
}

/// The one thing to tap on a screen, on the one tinted glass surface the screen is allowed.
///
/// Reduce Transparency turns that surface into a flat `accentSoft` panel, and near-white-on-pale-green is
/// unreadable, so the label follows the surface it is actually sitting on.
struct OnboardingActionButton: View {
    let title: String
    let isWorking: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(_ title: String, isWorking: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isWorking = isWorking
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: RoostSpacing.sm) {
                if isWorking {
                    ProgressView().controlSize(.small).tint(label)
                }
                Text(title)
                    .roostType(.headline)
            }
            .foregroundStyle(label)
            .frame(maxWidth: .infinity, minHeight: RoostSpacing.minTapTarget)
            .padding(.vertical, RoostSpacing.xs)
            .contentShape(RoostRadius.pillShape)
        }
        .buttonStyle(.plain)
        .roostGlass(.primary, in: RoostRadius.pillShape)
        .roostElevation(.floating, cornerRadius: RoostRadius.pill)
        .disabled(isWorking)
        .roostAnimation(.quick, value: isWorking)
    }

    private var label: Color {
        reduceTransparency ? RoostColor.Role.accent.color : RoostColor.Role.onAccent.color
    }
}

/// Where the reader is. Dots, not a bar: four steps is a count, not a percentage. The current dot is wider,
/// which says "you are here" without a caption.
///
/// The dots are 8 pt tall and the row they sit in is 44. It is one VoiceOver element — "Step 2 of 4" — and
/// an element that small is one the accessibility audit calls out however little it wants a tap, so the
/// band it lives in is the size a band should be. It also stops the dots sitting right under the status bar.
struct OnboardingProgress: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: RoostSpacing.sm) {
            ForEach(0 ..< total, id: \.self) { index in
                Capsule()
                    .fill(index == step
                        ? RoostColor.Role.accent.color
                        : RoostColor.Role.separator.color)
                    .frame(width: index == step ? RoostSpacing.xl : RoostSpacing.sm, height: RoostSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, minHeight: RoostSpacing.minTapTarget)
        .roostAnimation(.standard, value: step)
        // `.accessibility` rather than the default kinds: this sets the frame the accessibility element
        // reports, which otherwise hugs the 8-pt dots however tall the band around them is.
        .contentShape(.accessibility, Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.Onboarding.progress(step + 1, of: total))
    }
}
