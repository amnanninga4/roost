// Pieces the three list tabs share: the header block, the composer, the check circle, the initial
// avatar, the badges, the empty state, the undo bar, and the list chrome.
//
// Every colour here is a `RoostColor.Role`, every size a `RoostType` rung, every gap a `RoostSpacing`
// or `RoostRadius` step, and the two raised surfaces go through `.roostElevation`. Nothing in this
// file, or in the three screens, carries a hex value or a point size — see Packages/RoostDesign.
import RoostCore
import RoostDesign
import SwiftUI

/// An inset-grouped card's own side margin: one screen margin plus the step the List adds. The
/// header rows use it so the title lines up with the cards under it.
let listCardMargin = RoostSpacing.lg + RoostSpacing.xs

/// The composer's border: dashed at rest, a solid accent line while the field has focus. Stroke
/// geometry is the one thing RoostDesign has no scale for, so the two numbers live here, named once.
private enum ComposerBorder {
    static let width: CGFloat = 1.5
    static let dash: [CGFloat] = [5, 4]
}

/// A text-only action — "Clear bought", "Undo", "Try again", "Not now" — that still holds a 44 pt target.
///
/// It exists because of a trap worth naming once. `Button("x", action:).frame(minHeight: 44)` lays the
/// button out 44 pt tall but leaves the button's own tappable area the size of the two words inside it:
/// the frame wraps the button, not its content, and a `.plain` button's hit region is its content. The
/// accessibility audit sees the small one and is right to. A `ButtonStyle` is applied *to* the content, so
/// the height and the shape land where the taps do.
///
/// `alignment` is where the words sit inside the taller band — trailing for a button on the right of a
/// section header, leading for one under a paragraph.
///
/// The press is the kit's vocabulary — `RoostButtonStyle`'s opacity and the `press` haptic — so a text
/// action and a pill button feel the same under a finger.
struct RoostTextActionStyle: ButtonStyle {
    var alignment: Alignment = .leading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minHeight: RoostSpacing.minTapTarget, alignment: alignment)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? RoostButtonStyle.pressedOpacity : 1)
            .animation(
                RoostMotion.reduceMotionAware(.quick, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
            .sensoryFeedback(
                RoostHaptic.press.feedback,
                trigger: configuration.isPressed,
                condition: { _, now in now }
            )
    }
}

extension ButtonStyle where Self == RoostTextActionStyle {
    /// A text-only action that holds 44 pt, with the words at the leading edge of the band.
    static var roostTextAction: RoostTextActionStyle {
        RoostTextActionStyle()
    }

    /// The same, with the words at the trailing edge — a button on the right of a section header.
    static var roostTrailingTextAction: RoostTextActionStyle {
        RoostTextActionStyle(alignment: .trailing)
    }
}

/// Title in the display face over the count line and the sync line, like the Tasks tab's header.
struct ListScreenHeader: View {
    let title: String
    let line: String
    /// The coordinator's status line, the same one the Tasks tab shows. Nil hides it.
    var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
            Text(title)
                .roostType(.title)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
            Text(line)
                .roostType(.monoTally)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
            if let status {
                Text(status)
                    .roostType(.caption)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
                    .padding(.top, RoostSpacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The add row, as a composer: a plus badge that fills in once there is something to add, a field
/// whose border picks up the accent while it has focus, and room for a second field under it.
///
/// Return adds and keeps the keyboard (`refocus`), so lines can be typed in a batch; Return on a
/// blank field clears it and lets the keyboard go. To VoiceOver it is one element — the field, with
/// the hint — because the badge is decoration.
struct ListComposer<Extra: View>: View {
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    @ViewBuilder let extra: () -> Extra

    init(placeholder: String, text: Binding<String>, focused: FocusState<Bool>.Binding,
         onSubmit: @escaping () -> Void,
         @ViewBuilder extra: @escaping () -> Extra = { EmptyView() })
    {
        self.placeholder = placeholder
        _text = text
        self.focused = focused
        self.onSubmit = onSubmit
        self.extra = extra
    }

    private var isFocused: Bool {
        focused.wrappedValue
    }

    private var border: Color {
        isFocused ? RoostColor.Role.accent.color : RoostColor.Role.textSecondary.color
    }

    private var borderStyle: StrokeStyle {
        isFocused
            ? StrokeStyle(lineWidth: ComposerBorder.width)
            : StrokeStyle(lineWidth: ComposerBorder.width, dash: ComposerBorder.dash)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.sm) {
            HStack(spacing: RoostSpacing.md) {
                PlusBadge(isActive: !text.isEmpty)
                TextField(placeholder, text: $text, prompt: Text(placeholder)
                    .foregroundStyle(RoostColor.Role.textSecondary.color))
                    .roostType(.body)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                    .focused(focused)
                    .submitLabel(.done)
                    .onSubmit(onSubmit)
                    .accessibilityLabel(placeholder)
                    .accessibilityHint(Strings.Lists.composerHint)
            }
            extra()
        }
        .padding(RoostSpacing.md)
        .frame(minHeight: RoostSpacing.minTapTarget)
        .background(RoostColor.Role.surface.color, in: RoostRadius.rowShape)
        .overlay { RoostRadius.rowShape.stroke(border, style: borderStyle) }
        .roostElevation(.card, cornerRadius: RoostRadius.lg)
        .roostAnimation(.quick, value: isFocused)
        .roostAnimation(.quick, value: text.isEmpty)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(
            top: 0, leading: listCardMargin, bottom: RoostSpacing.sm, trailing: listCardMargin
        ))
        .listRowSeparator(.hidden)
    }
}

/// The little sheet a Shopping or Wishlist row's Edit action presents: the composer's own field
/// styling at the medium detent. Shopping edits its title; the wishlist adds the price line (the
/// same parse-and-clamp path the composer's price field uses, applied by the caller's save).
struct ListEditSheet: View {
    let title: String
    let fieldPlaceholder: String
    @Binding var draft: String
    /// The wishlist's price line; nil binding means Shopping (no price field).
    var priceDraft: Binding<String?>?
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    private var priceText: Binding<String>? {
        priceDraft.map { binding in
            Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0 })
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: RoostSpacing.md) {
                ListComposer(placeholder: fieldPlaceholder, text: $draft, focused: $focused, onSubmit: onSave) {
                    if let priceText {
                        TextField(Strings.Wishlist.price, text: priceText, prompt: Text(Strings.Wishlist.price)
                            .foregroundStyle(RoostColor.Role.textSecondary.color))
                            .roostType(.subheadline)
                            .foregroundStyle(RoostColor.Role.textSecondary.color)
                            .keyboardType(.decimalPad)
                            .submitLabel(.done)
                            .onSubmit(onSave)
                            .padding(.leading, RoostSpacing.xl + RoostSpacing.md)
                            .accessibilityLabel(Strings.Wishlist.price)
                    }
                }
                .listRowInsets(EdgeInsets())
                Spacer(minLength: 0)
            }
            .padding(RoostSpacing.screenMargin)
            .background(RoostColor.Role.background.color)
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Settings.cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Lists.save, action: onSave)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}

/// The composer's affordance: an outline while the field is empty, a filled accent circle once
/// there is something Return would add.
///
/// The badges and glyphs grow with the reader's text size, but not without limit: past
/// `RoostAvatar.glyphCeiling` they would push the row's words off the screen, and a 24-pt circle at
/// three times the size is a button, not a decoration.
struct PlusBadge: View {
    var isActive = false
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = RoostSpacing.xl

    private var side: CGFloat {
        min(scaled, RoostAvatar.glyphCeiling)
    }

    var body: some View {
        Image(systemName: "plus")
            .roostType(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(isActive ? RoostColor.Role.onAccent.color : RoostColor.Role.accent.color)
            .frame(width: side, height: side)
            .background(isActive ? RoostColor.Role.accent.color : RoostColor.Role.accentSoft.color, in: Circle())
            .roostAnimation(.quick, value: isActive)
            .accessibilityHidden(true)
    }
}

/// The check-off circle used by every row that can be ticked. The row around it is the button; the
/// trait is here so the circle reads as one wherever it stands on its own.
struct CheckCircle: View {
    let isOn: Bool

    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .roostType(.title)
            .foregroundStyle(isOn ? RoostColor.Role.success.color : RoostColor.Role.textSecondary.color)
            .contentTransition(.symbolEffect(.replace))
            .roostAnimation(.quick, value: isOn)
            .accessibilityAddTraits(.isButton)
    }
}

/// The mono eyebrow tag from the mockup (`NEXT UP`, `DONE`): strong text on its soft partner.
struct TagBadge: View {
    let text: String
    let role: RoostColor.Role
    var symbol: String?

    var body: some View {
        HStack(spacing: RoostSpacing.xxs) {
            if let symbol {
                Image(systemName: symbol)
                    .roostType(.monoLabel)
                    .accessibilityHidden(true)
            }
            Text(text)
                .roostType(.monoLabel)
        }
        .foregroundStyle(role.color)
        .padding(.horizontal, RoostSpacing.sm)
        .padding(.vertical, RoostSpacing.xxs)
        .background((role.soft ?? role).color, in: RoostRadius.shape(RoostRadius.sm))
    }
}

/// A small mixed-case chip: a meal's tag, read as a word rather than a label.
struct MetaChip: View {
    let text: String
    let role: RoostColor.Role

    var body: some View {
        Text(text)
            .roostType(.caption)
            .foregroundStyle(role.color)
            .padding(.horizontal, RoostSpacing.sm)
            .padding(.vertical, RoostSpacing.xxs)
            .background((role.soft ?? role).color, in: RoostRadius.shape(RoostRadius.md))
    }
}

/// The marker on a row the server refused (`rejected`). Quiet on purpose: it is information, not an
/// alarm, and the row still works locally. The row's accessibility value carries the same words.
struct NotSyncedMarker: View {
    var body: some View {
        HStack(spacing: RoostSpacing.xxs) {
            Image(systemName: "exclamationmark.icloud")
                .roostType(.caption)
            Text(Strings.Lists.didNotSync)
                .roostType(.caption)
        }
        .foregroundStyle(RoostColor.Role.notice.color)
        .padding(.horizontal, RoostSpacing.xs)
        .padding(.vertical, RoostSpacing.xxs)
        .background(RoostColor.Role.noticeSoft.color, in: RoostRadius.shape(RoostRadius.sm))
        .accessibilityHidden(true)
    }
}

/// What a tab shows before anything is on it: the tab's own symbol, the plain line, and what to do.
struct ListEmptyState: View {
    let symbol: String
    let line: String
    let hint: String

    var body: some View {
        VStack(spacing: RoostSpacing.sm) {
            Image(systemName: symbol)
                .roostType(.display)
                .foregroundStyle(RoostColor.Role.separator.color)
                .accessibilityHidden(true)
            Text(line)
                .roostType(.title)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
            Text(hint)
                .roostType(.callout)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, RoostSpacing.xl)
        .accessibilityElement(children: .combine)
        .listRowBackground(RoostColor.Role.surface.color)
    }
}

/// A swipe-delete that can be taken back for five seconds.
///
/// The row is soft-deleted in the store at once, so the list is right before the network is
/// involved and offline behaves the same as online. What waits is the *sync*: the removal sits in
/// the queue and `commit` — the `syncSoon()` that would send it — is held until the window closes.
/// An undo inside the window therefore never has to chase a request that has already gone out; it
/// is a local un-remove and nothing was ever sent.
///
/// Another trigger (the app coming back to the foreground, a write on another tab) can still flush
/// the queue mid-window, so `ListActions.restore*` covers that too: a row whose DELETE the server
/// has acknowledged cannot be un-deleted there, so a fresh copy goes out as a new create and the old
/// row stays a tombstone. Either way the queue holds one intent per row.
@MainActor
@Observable
final class ListUndo {
    /// How long the bar stays up. The screens use the default; the tests pass a short one.
    static let window = Duration.seconds(5)

    let window: Duration
    private(set) var message: String?
    private var restore: (() -> Void)?
    private var commit: (() -> Void)?
    private var expiry: Task<Void, Never>?

    init(window: Duration = ListUndo.window) {
        self.window = window
    }

    /// Puts up the bar. `restore` puts the row back; `commit` sends the removal, and runs when the
    /// window closes without an undo — or right away if another deletion replaces this one, because
    /// there is one bar and the older removal must still reach the server.
    func offer(_ message: String, restore: @escaping () -> Void, commit: @escaping () -> Void) {
        finish()
        self.message = message
        self.restore = restore
        self.commit = commit
        expiry = Task { [weak self] in
            guard let window = self?.window else { return }
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    func undo() {
        let action = restore
        clear()
        action?()
    }

    /// The window is over: send what was held back.
    func dismiss() {
        finish()
    }

    private func finish() {
        let action = commit
        clear()
        action?()
    }

    private func clear() {
        expiry?.cancel()
        expiry = nil
        message = nil
        restore = nil
        commit = nil
    }
}

/// The floating bar the undo window puts up. Glass and floating elevation, because it sits over the
/// list rather than in it.
struct UndoBar: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: RoostSpacing.md) {
            Text(message)
                .roostType(.subheadline)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
            Button(Strings.Lists.undo, action: undo)
                .roostType(.headline)
                .foregroundStyle(RoostColor.Role.accent.color)
                .buttonStyle(.roostTextAction)
                .accessibilityHint(Strings.Lists.undoHint)
        }
        .padding(.horizontal, RoostSpacing.lg)
        .padding(.vertical, RoostSpacing.md)
        .frame(minHeight: RoostSpacing.minTapTarget)
        .roostGlass(.clear, in: RoostRadius.pillShape)
        .roostElevation(.floating, cornerRadius: RoostRadius.pill)
        .padding(.bottom, RoostSpacing.lg)
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
    /// The chrome every list tab shares: inset cards on the page colour, the app title in the bar.
    func listTabChrome() -> some View {
        listStyle(.insetGrouped)
            .listSectionSpacing(RoostSpacing.sm)
            .contentMargins(.top, RoostSpacing.sm, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(RoostColor.Role.background.color)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Strings.appTitle)
            .toolbarTitleDisplayMode(.inline)
    }

    /// The header block's row settings, matching the Tasks tab.
    func listHeaderRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: RoostSpacing.xs, leading: listCardMargin, bottom: RoostSpacing.xs, trailing: listCardMargin
            ))
    }

    /// The trailing swipe every list row has. Tinted explicitly: the screens tint the whole stack with the
    /// accent, which would otherwise paint a destructive button green. A row the server refused reads
    /// "Remove", because there is nothing on the server to delete.
    func swipeToDelete(rejected: Bool = false, _ action: @escaping () -> Void) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: action) {
                Label(rejected ? Strings.Lists.remove : Strings.Lists.delete, systemImage: "trash")
            }
            .tint(RoostColor.Role.danger.color)
        }
    }

    /// The undo bar, over the bottom of a list tab.
    func undoBar(_ undo: ListUndo) -> some View {
        overlay(alignment: .bottom) {
            if let message = undo.message {
                UndoBar(message: message) { undo.undo() }
                    .roostTransition(.badge)
            }
        }
        .roostAnimation(.standard, value: undo.message)
    }
}
