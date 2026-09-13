// Screen two: six digits.
//
// No "Pair" button: the sixth digit submits. What is left to show is what went wrong, and the difference
// between the four answers — a dead code clears the boxes, a rate limit or a dead connection leaves them
// alone and offers one tap to try the same code again.
//
// The token link is deliberately small. `mktoken.js` still exists, and a phone that cannot use a code has to
// have a way in, but it is the path nobody should take first.
import RoostCore
import RoostDesign
import SwiftUI

struct CodeStep: View {
    @State private var model: PairingModel
    @State private var showingTokenSheet = false
    private let onPaired: (Person) -> Void

    /// The service is handed in by the flow, which reads it from the environment; the model is built once,
    /// here, so the code survives a re-render of the flow.
    init(service: any PairingService, onPaired: @escaping (Person) -> Void) {
        _model = State(initialValue: PairingModel(service: service))
        self.onPaired = onPaired
    }

    var body: some View {
        OnboardingPage(
            eyebrow: Strings.Onboarding.codeEyebrow,
            title: Strings.Onboarding.codeTitle,
            line: Strings.Onboarding.codeLine
        ) {
            VStack(alignment: .leading, spacing: RoostSpacing.lg) {
                CodeEntryField(model: model)
                    .padding(.top, RoostSpacing.sm)

                if let failure = model.failure {
                    FailureNote(failure: failure, canRetry: model.canRetry) { model.submit() }
                        .roostTransition(.row)
                } else if model.isSubmitting {
                    Label(Strings.Onboarding.codeWorking, systemImage: "arrow.triangle.2.circlepath")
                        .roostType(.subheadline)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                        .roostTransition(.row)
                }

                Button(Strings.Onboarding.tokenLink) { showingTokenSheet = true }
                    .buttonStyle(.plain)
                    .roostType(.footnote)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
                    .frame(minHeight: RoostSpacing.minTapTarget, alignment: .leading)
            }
            .roostAnimation(.standard, value: AnimationKey(failure: model.failure, submitting: model.isSubmitting))
        }
        .onChange(of: model.phase) { _, phase in
            if case let .paired(person) = phase {
                onPaired(person)
            }
        }
        .sheet(isPresented: $showingTokenSheet) {
            TokenSheet(onPaired: onPaired)
        }
    }

    /// Both pieces of state that move the block under the boxes, so they move together rather than fighting.
    private struct AnimationKey: Equatable {
        let failure: PairingModel.Failure?
        let submitting: Bool
    }
}

/// What went wrong, and the one tap worth offering. Colour is not the only signal: the icon and the sentence
/// say it too, for a reader who cannot see the red.
private struct FailureNote: View {
    let failure: PairingModel.Failure
    let canRetry: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.sm) {
            Label {
                Text(failure.text)
                    .roostType(.subheadline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(RoostColor.Role.danger.color)

            if canRetry {
                Button(Strings.Onboarding.retry, action: retry)
                    .roostType(.headline)
                    .foregroundStyle(RoostColor.Role.accent.color)
                    .frame(minHeight: RoostSpacing.minTapTarget, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RoostSpacing.md)
        .background(RoostColor.Role.dangerSoft.color, in: RoostRadius.shape(RoostRadius.lg))
        .accessibilityElement(children: .contain)
    }
}
