// Paste a device token, point at the server, connect. The token goes to the Keychain, never anywhere else.
import SwiftUI
import SwiftData
import RoostCore
import RoostDesign

struct PairingScreen: View {
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Query private var syncStates: [SyncState]

    @State private var baseURL = "https://roost.hinescreative.xyz"
    @State private var token = ""
    @State private var error: String?
    @State private var busy = false

    private var state: SyncState? { syncStates.first }

    var body: some View {
        NavigationStack {
            Form {
                if let state, state.isPaired {
                    Section("Paired") {
                        LabeledContent("Person", value: state.person.flatMap(Person.init(rawValue:))?.displayName ?? "?")
                        LabeledContent("Server", value: state.baseURL ?? "")
                        Button("Forget this device", role: .destructive) {
                            Task {
                                try? await sync.unpair()
                                token = ""
                            }
                        }
                    }
                }
                Section {
                    TextField("https://…", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Device token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Connect")
                } footer: {
                    Text("Wes mints a token per phone on the server. Paste it here once; it is stored in this phone's Keychain.")
                }
                if let error {
                    Section {
                        Text(error)
                            .font(RoostFont.body(size: RoostFont.Size.meta))
                            .foregroundStyle(RoostColor.alert)
                    }
                }
                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Text(busy ? "Connecting…" : "Connect")
                            if busy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(busy || token.trimmingCharacters(in: .whitespaces).isEmpty || URL(string: baseURL) == nil)
                }
            }
            .navigationTitle("Pairing")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear { if let b = state?.baseURL { baseURL = b } }
        }
        .tint(RoostColor.accent)
    }

    private func connect() async {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "That is not a valid URL."
            return
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            _ = try await sync.pair(baseURL: url, token: token)
            token = ""
            dismiss()
        } catch let e as SyncAPIError {
            error = e.description
        } catch {
            self.error = error.localizedDescription
        }
    }
}
