// A preview surface: every color token in the current scheme, the semantic pairs, and the type ramp.
import SwiftUI

public struct RoostSwatchbook: View {
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("ROOST DESIGN · \(scheme == .dark ? "DARK" : "LIGHT")")
                    .font(RoostFont.mono(size: RoostFont.Size.eyebrow, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(RoostColor.accent)

                section("Tokens") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(RoostColor.all, id: \.name) { token in
                            swatch(token)
                        }
                    }
                }

                section("Pairs") {
                    VStack(spacing: 8) {
                        ForEach(RoostColor.pairs, id: \.strong.name) { pair in
                            HStack {
                                Text(pair.strong.name.uppercased())
                                    .font(RoostFont.mono(size: RoostFont.Size.badge, weight: .semibold))
                                    .foregroundStyle(pair.strong.color)
                                Spacer()
                                Text(pair.strong.hex(scheme) + " on " + pair.soft.hex(scheme))
                                    .font(RoostFont.mono(size: RoostFont.Size.caption))
                                    .foregroundStyle(pair.strong.color)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(pair.soft.color, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                section("Type") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Chores, cat care, and a little competition")
                            .font(RoostFont.display(size: RoostFont.Size.title, weight: .bold))
                        Text("Section title").font(RoostFont.display(size: RoostFont.Size.sectionTitle, weight: .semibold))
                        Text("Body copy at fifteen points, the size every task row uses.")
                            .font(RoostFont.body(size: RoostFont.Size.body))
                        Text("Meta at 13.5 · Nunito Sans")
                            .font(RoostFont.body(size: RoostFont.Size.meta))
                            .foregroundStyle(RoostColor.inkSoft)
                        Text("EYEBROW · IBM PLEX MONO")
                            .font(RoostFont.mono(size: RoostFont.Size.eyebrow, weight: .semibold))
                            .kerning(1.2)
                            .foregroundStyle(RoostColor.accent)
                        Text(fontStatus)
                            .font(RoostFont.mono(size: RoostFont.Size.caption))
                            .foregroundStyle(RoostColor.inkSoft)
                    }
                    .foregroundStyle(RoostColor.ink)
                }
            }
            .padding(24)
        }
        .background(RoostColor.bg)
    }

    private var fontStatus: String {
        let d = RoostFont.isAvailable(RoostFont.Family.display) ? "Fraunces ✓" : "Fraunces → serif fallback"
        let b = RoostFont.isAvailable(RoostFont.Family.body) ? "Nunito Sans ✓" : "Nunito Sans → system fallback"
        let m = RoostFont.isAvailable(RoostFont.Family.mono) ? "Plex Mono ✓" : "Plex Mono → mono fallback"
        return [d, b, m].joined(separator: " · ")
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(RoostFont.display(size: RoostFont.Size.sectionTitle, weight: .semibold))
                .foregroundStyle(RoostColor.ink)
            content()
        }
    }

    private func swatch(_ token: RoostColorToken) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(token.color)
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(RoostColor.line, lineWidth: 1))
            Text(token.name).font(RoostFont.body(size: RoostFont.Size.caption, weight: .semibold))
            Text(token.hex(scheme)).font(RoostFont.mono(size: RoostFont.Size.badge))
                .foregroundStyle(RoostColor.inkSoft)
        }
        .foregroundStyle(RoostColor.ink)
        .padding(8)
        .background(RoostColor.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview("Light") {
    let _ = try? RoostFonts.register()
    RoostSwatchbook().preferredColorScheme(.light)
}

#Preview("Dark") {
    let _ = try? RoostFonts.register()
    RoostSwatchbook().preferredColorScheme(.dark)
}
