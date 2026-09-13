// Pieces the three list tabs share: the header block, the dashed "Add…" row, the check circle, the
// initial avatar, the small mono badge, and the list chrome. Colors and type come from RoostDesign.
/// Title in the display face over one meta line, like the mockup's panel head.
import RoostCore
import RoostDesign
import SwiftUI

struct ListScreenHeader: View {
    let title: String
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(RoostFont.display(size: RoostFont.Size.title, weight: .bold))
                .foregroundStyle(RoostColor.ink)
            Text(line)
                .font(RoostFont.body(size: RoostFont.Size.meta))
                .foregroundStyle(RoostColor.inkSoft)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The dashed add row: a plus badge, a text field, and room for extra fields under it.
struct AddRow<Extra: View>: View {
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    @ViewBuilder let extra: () -> Extra

    init(placeholder: String, text: Binding<String>, focused: FocusState<Bool>.Binding, onSubmit: @escaping () -> Void,
         @ViewBuilder extra: @escaping () -> Extra = { EmptyView() })
    {
        self.placeholder = placeholder
        _text = text
        self.focused = focused
        self.onSubmit = onSubmit
        self.extra = extra
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PlusBadge()
                TextField(placeholder, text: $text)
                    .font(RoostFont.body(size: RoostFont.Size.meta, weight: .semibold))
                    .foregroundStyle(RoostColor.ink)
                    .focused(focused)
                    .submitLabel(.done)
                    .onSubmit(onSubmit)
            }
            extra()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoostColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(RoostColor.line)
        )
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 4, trailing: 20))
        .listRowSeparator(.hidden)
    }
}

struct PlusBadge: View {
    var body: some View {
        Text("+")
            .font(RoostFont.body(size: 14, weight: .bold))
            .foregroundStyle(RoostColor.accent)
            .frame(width: 22, height: 22)
            .background(RoostColor.accentSoft, in: Circle())
            .accessibilityHidden(true)
    }
}

/// The check-off circle used by every row that can be ticked.
struct CheckCircle: View {
    let isOn: Bool

    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(isOn ? RoostColor.accent : RoostColor.line)
    }
}

/// "A" or "W" in a small circle: who added the row.
struct PersonAvatar: View {
    let person: Person

    var body: some View {
        Text(String(person.displayName.prefix(1)))
            .font(RoostFont.body(size: 10, weight: .bold))
            .foregroundStyle(RoostColor.assign)
            .frame(width: 22, height: 22)
            .background(RoostColor.assignSoft, in: Circle())
            .accessibilityLabel("Added by \(person.displayName)")
    }
}

/// The mono tag from the mockup (`NEXT UP`, `3D LATE`): strong text on its soft background.
struct TagBadge: View {
    let text: String
    let color: Color
    let soft: Color

    var body: some View {
        Text(text)
            .font(RoostFont.mono(size: RoostFont.Size.badge, weight: .bold))
            .kerning(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(soft, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// One quiet line inside a card when a list is empty.
struct EmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(RoostFont.body(size: RoostFont.Size.meta))
            .foregroundStyle(RoostColor.inkSoft)
            .listRowBackground(RoostColor.surface)
    }
}

/// Return resigns a text field in a List before `onSubmit` finishes, so setting the focus state
/// inside the handler is a no-op. Take focus back a beat later, so the next line can be typed straight
/// away: groceries and project steps come in batches.
@MainActor
func refocus(_ focus: FocusState<Bool>.Binding) {
    Task { @MainActor in
        focus.wrappedValue = false
        try? await Task.sleep(for: .milliseconds(80))
        focus.wrappedValue = true
    }
}

extension View {
    /// The chrome every list tab shares: inset cards on the page color, "Roost" in the bar.
    func listTabChrome() -> some View {
        listStyle(.insetGrouped)
            .listSectionSpacing(12)
            .scrollContentBackground(.hidden)
            .background(RoostColor.bg)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Roost")
            .toolbarTitleDisplayMode(.inline)
    }

    /// The header block's row settings, matching the Tasks tab.
    func listHeaderRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
    }

    /// The trailing swipe every list row has. Tinted explicitly: the screens tint the whole stack with the
    /// accent, which would otherwise paint a destructive button green.
    func swipeToDelete(_ action: @escaping () -> Void) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: action) {
                Label(Strings.Lists.delete, systemImage: "trash")
            }
            .tint(RoostColor.alert)
        }
    }
}
