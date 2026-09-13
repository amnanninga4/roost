// Six boxes that look like six boxes and behave like one text field.
//
// There is exactly one real `TextField` here, stretched invisibly across the boxes. That is what makes the
// keyboard appear, what makes a long press offer Paste, and what makes the QuickType bar offer a code sitting
// on the clipboard — none of which six separate fields would do, and all of which matter more than the
// tab-between-boxes behaviour six fields would buy. The boxes are a drawing of the field's contents.
//
// VoiceOver sees one element: label "Pairing code, six digits", value "0 4 8". Double-tapping it opens the
// keyboard. Six elements reading "text field, empty" six times is the version of this screen nobody can use.
//
// The body is split into named stages rather than one chain, because the whole chain in one expression is
// more than the type checker will do in reasonable time.
import RoostDesign
import SwiftUI

struct CodeEntryField: View {
    let model: PairingModel

    @FocusState private var isFocused: Bool
    /// What the hidden field holds. The model normalises it; this follows the model back.
    @State private var raw = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var digits: [Character] {
        Array(model.code)
    }

    var body: some View {
        described
            .roostHaptic(trigger: model.code.count) { old, new in new > old ? .selection : nil }
            .roostHaptic(trigger: model.rejectionCount) { old, new in new > old ? .error : nil }
            .task {
                // A step that appears mid-flow does not get `defaultFocus`, and the keyboard is the whole
                // point of this screen.
                isFocused = true
            }
    }

    /// One element, named and valued. `children: .ignore` is what collapses the boxes and the hidden field
    /// into it; the action is what a double-tap does, since the element it replaced was the thing to tap.
    private var described: some View {
        shaken
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Strings.Onboarding.codeFieldLabel)
            .accessibilityValue(Strings.Onboarding.codeFieldValue(model.code))
            .accessibilityHint(Strings.Onboarding.codeFieldHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { isFocused = true }
    }

    private var shaken: some View {
        boxes
            .overlay { field }
            .shakeOnChange(of: model.rejectionCount, reduceMotion: reduceMotion)
            .onChange(of: model.code) { _, new in
                if raw != new {
                    raw = new
                }
            }
    }

    /// One row while it fits, two rows of three when the reader's text size says it does not.
    private var boxes: some View {
        ViewThatFits(in: .horizontal) {
            row(0 ..< PairingModel.codeLength)
            VStack(spacing: RoostSpacing.sm) {
                row(0 ..< 3)
                row(3 ..< PairingModel.codeLength)
            }
        }
    }

    private func row(_ range: Range<Int>) -> some View {
        HStack(spacing: RoostSpacing.sm) {
            ForEach(range, id: \.self) { index in
                box(at: index)
            }
        }
    }

    private func box(at index: Int) -> some View {
        let digit = index < digits.count ? String(digits[index]) : ""
        let filled = !digit.isEmpty
        let isNext = index == digits.count && isFocused && !model.isSubmitting
        return digitLabel(digit)
            .background(fill(filled: filled), in: RoostRadius.shape(RoostRadius.md))
            .overlay(border(isNext: isNext, filled: filled))
            .roostAnimation(.quick, value: digit)
    }

    private func digitLabel(_ digit: String) -> some View {
        Text(digit)
            .roostType(.display)
            .foregroundStyle(RoostColor.Role.textPrimary.color)
            .frame(minWidth: RoostSpacing.xxl, minHeight: RoostSpacing.minTapTarget)
            .padding(.vertical, RoostSpacing.sm)
            .padding(.horizontal, RoostSpacing.xs)
    }

    private func border(isNext: Bool, filled: Bool) -> some View {
        RoundedRectangle(cornerRadius: RoostRadius.md)
            .strokeBorder(stroke(isNext: isNext, filled: filled), lineWidth: isNext ? 2 : 1)
    }

    private func fill(filled: Bool) -> Color {
        guard filled else { return RoostColor.Role.surfaceElevated.color }
        return model.failure == nil
            ? RoostColor.Role.accentSoft.color
            : RoostColor.Role.dangerSoft.color
    }

    private func stroke(isNext: Bool, filled: Bool) -> Color {
        if model.failure != nil, filled {
            return RoostColor.Role.danger.color
        }
        if isNext || filled {
            return RoostColor.Role.accent.color
        }
        return RoostColor.Role.separator.color
    }

    /// The real field. Invisible, not hidden: an `opacity(0)` view stops taking taps, and taps are how the
    /// keyboard opens.
    ///
    /// Never disabled, not even mid-attempt: disabling a focused field drops the keyboard, and a code that
    /// came back wrong is a code you want to retype straight away. The model ignores input while it is
    /// waiting, which is the same guarantee without the cost.
    private var field: some View {
        TextField("", text: $raw)
            // The system body rather than a `RoostType` rung: nobody ever sees this field's own text — the
            // boxes behind it are the drawing — and the system styles are the only ones the accessibility
            // audit can tell scale with Dynamic Type. A rung here bought nothing and cost a finding.
            .font(.body)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isFocused)
            // Invisible to the eye *and* to VoiceOver: `described` above is the one element, with the
            // label, the value, and the action that opens the keyboard. Saying so explicitly also keeps
            // the field out of the accessibility audit, which otherwise reports the UIKit text field
            // behind it as a control whose (never-rendered) text does not scale.
            .accessibilityHidden(true)
            .opacity(0.01)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onChange(of: raw) { _, new in
                model.input(new)
                if raw != model.code {
                    raw = model.code
                }
            }
    }
}

// MARK: - the shake

/// A rejected code shakes its boxes once: three decaying passes inside `RoostMotion.standard`'s 0.32 s, which
/// is the 300-400 ms an error shake wants, with the amplitude taken off the spacing scale rather than invented.
///
/// This is a keyframe track rather than a fifth named spring, because the package's rule is four springs and
/// `Packages/` is not this ticket's to change. Reduce Motion drops the amplitude to zero: the message and the
/// red boxes still say what happened.
private struct ShakeModifier: ViewModifier {
    let token: Int
    let reduceMotion: Bool

    private var amplitude: CGFloat {
        RoostMotion.kind(.standard, reduceMotion: reduceMotion) == .spring ? RoostSpacing.sm : 0
    }

    private var step: Double {
        RoostMotion.Named.standard.duration / 4
    }

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat.zero, trigger: token) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            CubicKeyframe(amplitude, duration: step)
            CubicKeyframe(-amplitude, duration: step)
            CubicKeyframe(amplitude / 2, duration: step)
            CubicKeyframe(0, duration: step)
        }
    }
}

extension View {
    func shakeOnChange(of token: Int, reduceMotion: Bool) -> some View {
        modifier(ShakeModifier(token: token, reduceMotion: reduceMotion))
    }
}
