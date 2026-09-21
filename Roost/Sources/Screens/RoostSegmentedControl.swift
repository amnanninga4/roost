// The Lists tab's page picker: one segment per page, and the selection a pill that slides between
// them on matchedGeometryEffect with the `quick` spring — the job the system segmented control did,
// drawn from the kit instead. At accessibility text sizes the segments show their symbols only and
// keep each page's name as the VoiceOver label, which is what the audits reach for. The selection
// itself is the caller's (`AppStorage` under `roost.lists.page`); this control only draws it.
import RoostDesign
import SwiftUI

struct RoostSegmentedControl<Item: Identifiable & Hashable>: View where Item.ID == String {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let symbol: (Item) -> String

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: RoostSpacing.xxs) {
            ForEach(items) { item in
                Button {
                    withAnimation(RoostMotion.reduceMotionAware(.quick, reduceMotion: reduceMotion)) {
                        selection = item
                    }
                } label: {
                    segment(item)
                }
                // Quiet: the sliding pill is the answer to the tap.
                .buttonStyle(.roostPressQuiet)
                .accessibilityLabel(title(item))
                .accessibilityAddTraits(selection == item ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("listsPicker.\(item.id)")
            }
        }
        .padding(RoostSpacing.xxs)
    }

    @ViewBuilder
    private func segment(_ item: Item) -> some View {
        let selected = selection == item
        Group {
            if typeSize.isAccessibilitySize {
                Image(systemName: symbol(item))
                    .roostType(.body)
            } else {
                Text(title(item))
                    .roostType(.subheadline)
                    .fontWeight(selected ? .semibold : .regular)
            }
        }
        .foregroundStyle(selected ? RoostColor.Role.accent.color : RoostColor.Role.textSecondary.color)
        .frame(maxWidth: .infinity)
        .frame(minHeight: RoostSpacing.minTapTarget)
        .overlay(alignment: .bottom) {
            if selected {
                Rectangle()
                    .fill(RoostColor.Role.accent.color)
                    .frame(height: RoostSpacing.xxs)
                    .matchedGeometryEffect(id: "underline", in: pill)
            }
        }
        .contentShape(Rectangle())
    }
}
