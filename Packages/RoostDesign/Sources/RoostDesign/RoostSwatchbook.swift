// The design system, on one scrollable page: colour roles in both schemes, the raw tokens,
// the type ramp (and what it does at three Dynamic Type sizes), the spacing and radius
// scales, the elevation steps, the four springs on a row that actually checks off, and a
// glass sample. If something is in RoostDesign and not on this page, that is a bug.
import SwiftUI

public struct RoostSwatchbook: View {
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RoostSpacing.xl) {
                header
                RolesSection()
                TokensSection(scheme: scheme)
                PairsSection(scheme: scheme)
                TypeSection()
                DynamicTypeSection()
                SpacingSection()
                RadiusSection()
                ElevationSection()
                MotionSection()
                GlassSection()
                Text(fontStatus)
                    .roostType(.caption)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
            }
            .padding(RoostSpacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RoostColor.Role.background.color)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.xs) {
            Text("ROOST DESIGN · \(scheme == .dark ? "DARK" : "LIGHT")")
                .roostType(.monoLabel)
                .foregroundStyle(RoostColor.Role.accent.color)
            Text("Chores, cat care, and a little competition")
                .roostType(.displayLarge)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
        }
    }

    private var fontStatus: String {
        RoostType.Face.allCases.map { face in
            face.isAvailable ? "\(face.family) ✓" : "\(face.family) → system \(face.fallbackDesign)"
        }
        .joined(separator: " · ")
    }
}

// MARK: - Shared chrome

struct SwatchSection<Content: View>: View {
    let title: String
    let note: String?
    @ViewBuilder var content: Content

    init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.md) {
            VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                Text(title)
                    .roostType(.title)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                if let note {
                    Text(note)
                        .roostType(.footnote)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SwatchCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(RoostSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .roostCard()
    }
}

// MARK: - Previews

#Preview("Light") {
    // swiftlint:disable:next redundant_discardable_let - a ViewBuilder needs a declaration here.
    let _ = try? RoostFonts.register()
    RoostSwatchbook().preferredColorScheme(.light)
}

#Preview("Dark") {
    // swiftlint:disable:next redundant_discardable_let - a ViewBuilder needs a declaration here.
    let _ = try? RoostFonts.register()
    RoostSwatchbook().preferredColorScheme(.dark)
}

#Preview("Accessibility 3") {
    // swiftlint:disable:next redundant_discardable_let - a ViewBuilder needs a declaration here.
    let _ = try? RoostFonts.register()
    RoostSwatchbook()
        .preferredColorScheme(.light)
        .dynamicTypeSize(.accessibility3)
}

#Preview("System fonts (unregistered)") {
    RoostSwatchbook().preferredColorScheme(.light)
}
