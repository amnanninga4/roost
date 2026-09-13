// The swatchbook sections that show values: colour roles in both schemes, the raw tokens, the
// strong/soft pairs, and the type ramp. The page that stacks every section is in
// RoostSwatchbook.swift; the behavioural demos are in RoostSwatchbookDemos.swift.
import SwiftUI

// MARK: - Colour

struct RolesSection: View {
    var body: some View {
        SwatchSection("Roles", note: "Every meaning the app has, in both schemes, with the raw token behind it.") {
            VStack(spacing: RoostSpacing.xs) {
                ForEach(RoostColor.Role.allCases) { role in
                    HStack(spacing: RoostSpacing.sm) {
                        Text(role.rawValue)
                            .roostType(.subheadline)
                            .foregroundStyle(RoostColor.Role.textPrimary.color)
                        Spacer(minLength: RoostSpacing.sm)
                        Text(role.token.name)
                            .roostType(.monoTally)
                            .foregroundStyle(RoostColor.Role.textSecondary.color)
                        chip(role, .light)
                        chip(role, .dark)
                    }
                    .padding(.horizontal, RoostSpacing.md)
                    .padding(.vertical, RoostSpacing.sm)
                    .background(RoostColor.Role.surface.color, in: RoostRadius.rowShape)
                }
            }
        }
    }

    private func chip(_ role: RoostColor.Role, _ scheme: ColorScheme) -> some View {
        RoundedRectangle(cornerRadius: RoostRadius.sm, style: .continuous)
            .fill(role.color(scheme))
            .frame(width: 34, height: 22)
            .overlay {
                RoundedRectangle(cornerRadius: RoostRadius.sm, style: .continuous)
                    .strokeBorder(RoostColor.Role.separator.color, lineWidth: 1)
            }
            .accessibilityLabel("\(role.rawValue) in \(scheme == .dark ? "dark" : "light"), \(role.token.hex(scheme))")
    }
}

struct TokensSection: View {
    let scheme: ColorScheme
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: RoostSpacing.md)]

    var body: some View {
        SwatchSection("Tokens", note: "The raw palette from the mockup. Screens use roles, not these.") {
            LazyVGrid(columns: columns, spacing: RoostSpacing.md) {
                ForEach(RoostColor.all, id: \.name) { token in
                    VStack(alignment: .leading, spacing: RoostSpacing.xs) {
                        RoundedRectangle(cornerRadius: RoostRadius.md, style: .continuous)
                            .fill(token.color)
                            .frame(height: 44)
                            .overlay {
                                RoundedRectangle(cornerRadius: RoostRadius.md, style: .continuous)
                                    .strokeBorder(RoostColor.Role.separator.color, lineWidth: 1)
                            }
                        Text(token.name).roostType(.caption)
                        Text(token.hex(scheme))
                            .roostType(.monoTally)
                            .foregroundStyle(RoostColor.Role.textSecondary.color)
                    }
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                    .padding(RoostSpacing.sm)
                    .background(RoostColor.Role.surface.color, in: RoostRadius.rowShape)
                }
            }
        }
    }
}

struct PairsSection: View {
    let scheme: ColorScheme

    var body: some View {
        SwatchSection("Pairs", note: "A strong colour on its soft background — how every status row is built.") {
            VStack(spacing: RoostSpacing.sm) {
                ForEach(RoostColor.pairs, id: \.strong.name) { pair in
                    HStack {
                        Text(pair.strong.name.uppercased()).roostType(.monoLabel)
                        Spacer()
                        Text(pair.strong.hex(scheme) + " on " + pair.soft.hex(scheme)).roostType(.monoTally)
                    }
                    .foregroundStyle(pair.strong.color)
                    .padding(.horizontal, RoostSpacing.md)
                    .padding(.vertical, RoostSpacing.sm)
                    .background(pair.soft.color, in: RoostRadius.rowShape)
                }
            }
        }
    }
}

// MARK: - Type

struct TypeSection: View {
    var body: some View {
        SwatchSection("Type", note: "Twelve rungs. Each one scales with the reader's text size.") {
            SwatchCard {
                VStack(alignment: .leading, spacing: RoostSpacing.md) {
                    ForEach(RoostType.all) { spec in
                        VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                            Text(sample(for: spec))
                                .font(spec.font)
                                .tracking(spec.tracking)
                                .lineSpacing(spec.lineSpacing)
                                .foregroundStyle(RoostColor.Role.textPrimary.color)
                            Text(
                                "\(spec.name) · \(spec.face.rawValue) \(Int(spec.size))pt / \(styleName(spec.textStyle))"
                            )
                            .roostType(.monoTally)
                            .foregroundStyle(RoostColor.Role.textSecondary.color)
                            Text(spec.usage)
                                .roostType(.footnote)
                                .foregroundStyle(RoostColor.Role.textSecondary.color)
                        }
                    }
                }
            }
        }
    }

    private func sample(for spec: RoostType.Spec) -> String {
        switch spec.face {
        case .display: "Feed the cat"
        case .body: "Rotation puts this one on Anne through Friday."
        case .mono: spec.monospacedDigit ? "14 · 11 · 3" : "CAT CARE"
        }
    }

    // swiftlint:disable:next cyclomatic_complexity - one case per text style; a mapping, not logic.
    private func styleName(_ style: Font.TextStyle) -> String {
        switch style {
        case .largeTitle: "largeTitle"
        case .title: "title"
        case .title2: "title2"
        case .title3: "title3"
        case .headline: "headline"
        case .subheadline: "subheadline"
        case .body: "body"
        case .callout: "callout"
        case .footnote: "footnote"
        case .caption: "caption"
        case .caption2: "caption2"
        @unknown default: "—"
        }
    }
}

struct DynamicTypeSection: View {
    private let sizes: [DynamicTypeSize] = [.xSmall, .large, .accessibility2]

    var body: some View {
        SwatchSection(
            "Dynamic Type",
            note: "The same four rungs at the smallest, default, and a large accessibility size."
        ) {
            VStack(spacing: RoostSpacing.md) {
                ForEach(sizes, id: \.self) { size in
                    SwatchCard {
                        VStack(alignment: .leading, spacing: RoostSpacing.xs) {
                            Text(label(size))
                                .roostType(.monoLabel)
                                .foregroundStyle(RoostColor.Role.accent.color)
                            VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                                Text("Today").roostType(.displayLarge)
                                Text("Feed the cat").roostType(.rowTitle)
                                Text("Anne · every morning").roostType(.subheadline)
                                Text("14 · 11").roostType(.monoTally)
                            }
                            .foregroundStyle(RoostColor.Role.textPrimary.color)
                            .dynamicTypeSize(size)
                        }
                    }
                }
            }
        }
    }

    private func label(_ size: DynamicTypeSize) -> String {
        let name = switch size {
        case .xSmall: "XSMALL"
        case .large: "LARGE (DEFAULT)"
        case .accessibility2: "ACCESSIBILITY 2"
        default: "\(size)".uppercased()
        }
        let body = RoostType.referenceBodySize(for: size)
        return "\(name) · BODY \(Int(body))PT"
    }
}
