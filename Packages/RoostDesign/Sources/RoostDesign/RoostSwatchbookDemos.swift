// The swatchbook sections that demonstrate behaviour rather than values: the spacing and radius
// scales, the elevation steps, the four springs on a row that checks off, and a glass sample.
import SwiftUI

// MARK: - Space

struct SpacingSection: View {
    var body: some View {
        SwatchSection("Spacing", note: "A 4-pt scale, plus the four values a screen actually reaches for.") {
            SwatchCard {
                VStack(alignment: .leading, spacing: RoostSpacing.sm) {
                    ForEach(RoostSpacing.scale + RoostSpacing.semantic, id: \.name) { item in
                        HStack(spacing: RoostSpacing.md) {
                            Text(item.name)
                                .roostType(.subheadline)
                                .frame(width: 110, alignment: .leading)
                            Rectangle()
                                .fill(RoostColor.Role.accent.color)
                                .frame(width: item.value, height: 12)
                            Text("\(Int(item.value))")
                                .roostType(.monoTally)
                                .foregroundStyle(RoostColor.Role.textSecondary.color)
                        }
                        .foregroundStyle(RoostColor.Role.textPrimary.color)
                    }
                }
            }
        }
    }
}

struct RadiusSection: View {
    var body: some View {
        SwatchSection("Radius", note: "Continuous corners. A row inset by 8 inside a card lands on lg: 22 − 8 = 14.") {
            HStack(alignment: .top, spacing: RoostSpacing.md) {
                ForEach(RoostRadius.scale.filter { $0.name != "pill" }, id: \.name) { item in
                    VStack(spacing: RoostSpacing.xs) {
                        RoundedRectangle(cornerRadius: item.value, style: .continuous)
                            .fill(RoostColor.Role.accentSoft.color)
                            .frame(height: 64)
                            .overlay {
                                RoundedRectangle(cornerRadius: item.value, style: .continuous)
                                    .strokeBorder(RoostColor.Role.accent.color, lineWidth: 1)
                            }
                        Text(item.name).roostType(.caption)
                        Text("\(Int(item.value))")
                            .roostType(.monoTally)
                            .foregroundStyle(RoostColor.Role.textSecondary.color)
                    }
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                }
                VStack(spacing: RoostSpacing.xs) {
                    Capsule()
                        .fill(RoostColor.Role.accentSoft.color)
                        .frame(height: 64)
                        .overlay { Capsule().strokeBorder(RoostColor.Role.accent.color, lineWidth: 1) }
                    Text("pill").roostType(.caption)
                    Text("∞")
                        .roostType(.monoTally)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                }
                .foregroundStyle(RoostColor.Role.textPrimary.color)
            }
        }
    }
}

struct ElevationSection: View {
    var body: some View {
        SwatchSection("Elevation", note: "Ink-tinted in light; smaller shadow plus a hairline in dark.") {
            HStack(spacing: RoostSpacing.lg) {
                ForEach(RoostElevation.all, id: \.name) { level in
                    VStack(spacing: RoostSpacing.xs) {
                        RoundedRectangle(cornerRadius: RoostRadius.card, style: .continuous)
                            .fill(RoostColor.Role.surface.color)
                            .frame(height: 72)
                            .roostElevation(level, cornerRadius: RoostRadius.card)
                        Text(level.name).roostType(.caption)
                    }
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                }
            }
            .padding(.horizontal, RoostSpacing.xs)
        }
    }
}

// MARK: - Motion

struct MotionSection: View {
    var body: some View {
        SwatchSection("Motion", note: "Four springs. Tap a row to feel the one it uses.") {
            SwatchCard {
                VStack(alignment: .leading, spacing: RoostSpacing.md) {
                    ForEach(RoostMotion.Named.allCases) { named in
                        SpringRow(named: named)
                    }
                }
            }
            CheckOffDemo()
        }
    }
}

/// One spring, on a dot that travels when tapped, with its numbers next to it.
struct SpringRow: View {
    let named: RoostMotion.Named
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moved = false

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: RoostSpacing.sm) {
                Text(named.rawValue)
                    .roostType(.headline)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                Spacer(minLength: RoostSpacing.sm)
                Text(RoostMotion.kind(named, reduceMotion: reduceMotion).rawValue)
                    .roostType(.caption)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
            }
            Text("\(named.duration, specifier: "%.2f")s · bounce \(named.bounce, specifier: "%.2f")")
                .roostType(.monoTally)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
            Text(named.usage)
                .roostType(.footnote)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
            ZStack(alignment: moved ? .trailing : .leading) {
                Capsule()
                    .fill(RoostColor.Role.surfaceElevated.color)
                    .frame(height: 26)
                Circle()
                    .fill(RoostColor.Role.accent.color)
                    .frame(width: 22, height: 22)
                    .padding(.horizontal, 2)
            }
            .roostAnimation(named, value: moved)
            .contentShape(Rectangle())
            .onTapGesture { moved.toggle() }
            .accessibilityLabel("\(named.rawValue) spring demo")
        }
    }
}

/// A chore row that checks off: the strike-through, the symbol bounce, the haptic, and the
/// row leaving the list — all on one piece of state, all Reduce Motion aware.
struct CheckOffDemo: View {
    private struct Chore: Identifiable {
        let id: Int
        let title: String
        let person: RoostPerson
        let category: RoostCategory
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var done: Set<Int> = []
    private let chores: [Chore] = [
        Chore(id: 0, title: "Feed cat (AM)", person: .anne, category: .catCare),
        Chore(id: 1, title: "Scoop litter", person: .wes, category: .catCare),
        Chore(id: 2, title: "Run the dishwasher", person: .wes, category: .home),
    ]

    var body: some View {
        SwatchCard {
            VStack(alignment: .leading, spacing: RoostSpacing.sm) {
                HStack {
                    Text("CHECK-OFF")
                        .roostType(.monoLabel)
                        .foregroundStyle(RoostColor.Role.accent.color)
                    Spacer()
                    Text("\(done.count)/\(chores.count)")
                        .roostType(.monoTally)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                }
                ForEach(chores) { chore in
                    row(chore)
                }
                if done.count == chores.count {
                    Text("Everything on the list. Someone is winning.")
                        .roostType(.callout)
                        .foregroundStyle(RoostColor.Role.success.color)
                        .roostTransition(.badge)
                }
                Button("Reset") {
                    withAnimation(RoostMotion.reduceMotionAware(.gentle, reduceMotion: reduceMotion)) { done = [] }
                }
                .roostType(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(RoostColor.Role.notice.color)
            }
            .roostAnimation(.standard, value: done)
        }
    }

    private func row(_ chore: Chore) -> some View {
        let isDone = done.contains(chore.id)
        return HStack(spacing: RoostSpacing.md) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 21))
                .foregroundStyle(isDone ? RoostColor.Role.success.color : RoostColor.Role.separator.color)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isDone)
            VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                Text(chore.title)
                    .roostType(.rowTitle)
                    .strikethrough(isDone, color: RoostColor.Role.textSecondary.color)
                    .foregroundStyle(isDone ? RoostColor.Role.textSecondary.color : RoostColor.Role.textPrimary.color)
                HStack(spacing: RoostSpacing.xs) {
                    Image(systemName: chore.category.symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(chore.category.color)
                    Text(chore.person.shortName)
                        .roostType(.subheadline)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                }
            }
            Spacer(minLength: RoostSpacing.sm)
            Text(chore.person.shortName.prefix(1))
                .roostType(.monoLabel)
                .foregroundStyle(chore.person.color)
                .frame(width: 24, height: 24)
                .background(chore.person.softColor, in: Circle())
        }
        .padding(.horizontal, RoostSpacing.sm)
        .padding(.vertical, RoostSpacing.rowPadding)
        .frame(minHeight: RoostSpacing.minTapTarget)
        .background(
            isDone ? RoostColor.Role.successSoft.color : RoostColor.Role.surfaceElevated.color,
            in: RoostRadius.rowShape
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(RoostMotion.reduceMotionAware(.standard, reduceMotion: reduceMotion)) {
                if isDone {
                    done.remove(chore.id)
                } else {
                    done.insert(chore.id)
                }
            }
        }
        .roostHaptic(trigger: isDone) { _, now in now ? .checkOff : .undo }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chore.title), \(chore.person.shortName), \(isDone ? "done" : "not done")")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Glass

struct GlassSection: View {
    var body: some View {
        SwatchSection("Glass", note: "The floating layer only: one tinted primary action, the rest clear.") {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [RoostColor.Role.accentSoft.color, RoostColor.Role.surface.color],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 190)
                .clipShape(RoostRadius.cardShape)
                .overlay(alignment: .topLeading) {
                    Text("Today")
                        .roostType(.display)
                        .foregroundStyle(RoostColor.Role.textPrimary.color)
                        .padding(RoostSpacing.lg)
                }

                RoostGlassContainer {
                    HStack(spacing: RoostSpacing.sm) {
                        glassButton("chevron.left", style: .clear)
                        glassButton("plus", style: .primary)
                        glassButton("ellipsis", style: .clear)
                    }
                }
                .padding(.bottom, RoostSpacing.lg)
            }
        }
    }

    private func glassButton(_ symbol: String, style: RoostGlassStyle) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(style.tint == nil ? RoostColor.Role.textPrimary.color : RoostColor.Role.onAccent.color)
            .frame(width: 44, height: 44)
            .roostGlass(style)
            .roostElevation(.floating, cornerRadius: 22)
    }
}
