// The way in for a phone that cannot use a code.
//
// `mktoken.js` still exists — it is how you get back in when the API is not answering, and how a device that
// never sees the pairing screen is set up — so the app keeps a place to paste its 43 characters. It is a
// sheet behind a small link, not a step, because nobody should meet it on a first run.
import RoostCore
import RoostDesign
import SwiftUI

struct TokenSheet: View {
    let onPaired: (Person) -> Void

    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var error: String?
    @State private var busy = false

    private var trimmed: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Not a SecureField: this is pasted once, on a phone in your own hand, and a field that
                    // hides what you pasted cannot be checked against what you copied.
                    TextField(Strings.Onboarding.tokenField, text: $token, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .roostType(.callout)
                        .disabled(busy)
                } footer: {
                    Text(Strings.Onboarding.tokenLine)
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .roostType(.subheadline)
                            .foregroundStyle(RoostColor.Role.danger.color)
                    }
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Text(busy ? Strings.Onboarding.tokenWorking : Strings.Onboarding.tokenAction)
                            if busy {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(busy || trimmed.isEmpty)
                }
            }
            .navigationTitle(Strings.Onboarding.tokenTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Onboarding.cancel) { dismiss() }
                }
            }
        }
        .tint(RoostColor.Role.accent.color)
    }

    private func connect() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let person = try await sync.pair(token: trimmed)
            token = ""
            dismiss()
            onPaired(person)
        } catch let e as SyncAPIError {
            error = e.description
        } catch {
            self.error = error.localizedDescription
        }
    }
}
