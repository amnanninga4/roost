// Gear → Settings: what this phone is paired to, and the one way to undo it.
//
// A `Form`, because this is a settings screen and iOS already has a look for those. The one thing worth
// saying about the shape: Unpair sits alone at the bottom in red, and the note it can come back with is
// shown *before* the app drops back to onboarding, because "the server kept your token" is the kind of
// sentence that has to arrive while there is still a screen to read it on.
import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

struct SettingsScreen: View {
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var syncStates: [SyncState]

    @State private var confirmingUnpair = false
    @State private var showingNote = false
    @State private var unpairNote = ""
    @State private var unpairing = false
    @State private var serverDraft = ""

    private var state: SyncState? {
        syncStates.first
    }

    private var person: Person? {
        state?.person.flatMap(Person.init(rawValue:))
    }

    private var endpoint: URL {
        ServerEndpoint.resolved(stored: state?.baseURL)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(Strings.Settings.phoneHeader) {
                    LabeledContent(Strings.Settings.pairedAs) {
                        if let person {
                            Label(person.displayName, systemImage: "person.fill")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(person.design.color)
                        } else {
                            Text(Strings.Settings.notPaired)
                                .foregroundStyle(RoostColor.Role.textSecondary.color)
                        }
                    }
                    LabeledContent(Strings.Settings.device, value: DeviceName.current)
                }

                serverSection

                Section(Strings.Settings.syncHeader) {
                    LabeledContent(Strings.Settings.lastSync, value: lastSyncText)
                    LabeledContent(Strings.Settings.status, value: statusText)
                }

                Section {
                    Button(role: .destructive) {
                        confirmingUnpair = true
                    } label: {
                        HStack {
                            Text(Strings.Settings.unpair)
                            if unpairing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(unpairing)
                } footer: {
                    VStack(spacing: RoostSpacing.sm) {
                        Text(Strings.Settings.unpairFooter)
                        Text(Self.versionLine)
                            .roostType(.caption)
                            .foregroundStyle(RoostColor.Role.textSecondary.color)
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, RoostSpacing.xs)
                }
            }
            .navigationTitle(Strings.Settings.title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Settings.close) { dismiss() }
                }
            }
            .confirmationDialog(
                Strings.Settings.unpairConfirmTitle,
                isPresented: $confirmingUnpair,
                titleVisibility: .visible
            ) {
                Button(Strings.Settings.unpairConfirm, role: .destructive) {
                    Task { await unpair() }
                }
                Button(Strings.Settings.cancel, role: .cancel) {}
            } message: {
                Text(Strings.Settings.unpairFooter)
            }
            .alert(Strings.Settings.unpairNoticeTitle, isPresented: $showingNote) {
                Button(Strings.Settings.unpairNoticeAction) {
                    sync.returnToOnboarding()
                }
            } message: {
                Text(unpairNote)
            }
        }
        .tint(RoostColor.Role.accent.color)
    }

    // MARK: server

    private var serverSection: some View {
        Section {
            #if DEBUG
                TextField(Strings.Settings.serverHeader, text: $serverDraft)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { commitServerDraft() }
                    .onAppear { serverDraft = endpoint.absoluteString }
            #else
                LabeledContent(Strings.Settings.serverHeader, value: ServerEndpoint.display(endpoint))
            #endif
        } header: {
            Text(Strings.Settings.serverHeader)
        } footer: {
            #if DEBUG
                Text(Strings.Settings.serverFooter)
            #endif
        }
    }

    #if DEBUG
        /// Debug only: point this phone at another server. It does not re-pair — the token is per server —
        /// so the next step after changing this is Unpair and a fresh code.
        private func commitServerDraft() {
            guard let url = ServerEndpoint
                .absoluteURL(from: serverDraft.trimmingCharacters(in: .whitespacesAndNewlines)),
                let state
            else {
                serverDraft = endpoint.absoluteString
                return
            }
            state.baseURL = url.absoluteString
            try? context.save()
            serverDraft = url.absoluteString
        }
    #endif

    // MARK: sync line

    /// One phrase for the state of the last pass. Not `SyncCoordinator.statusLine`, which folds the time
    /// into the sentence and would say "Synced 34 sec. ago" next to a row that already says that.
    private var statusText: String {
        if sync.isSyncing {
            return Strings.Settings.statusSyncing
        }
        switch sync.lastOutcome {
        case .none: return Strings.Settings.neverSynced
        case .unpaired: return Strings.Settings.notPaired
        case .coalesced: return Strings.Settings.statusSyncing
        case .failed: return Strings.Settings.statusOffline
        case .synced: return Strings.Settings.statusUpToDate
        }
    }

    private var lastSyncText: String {
        guard let at = state?.lastSyncAt ?? sync.lastSyncAt else { return Strings.Settings.neverSynced }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: at, relativeTo: Date())
    }

    // MARK: unpair

    private func unpair() async {
        unpairing = true
        let outcome = await sync.unpairDevice()
        unpairing = false
        if let note = outcome.note {
            unpairNote = note // the alert's button is what sends the app back to onboarding
            showingNote = true
        } else {
            sync.returnToOnboarding()
        }
    }

    /// "Roost 0.1.0 (1)" — from the bundle, so it is whatever this build actually is.
    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return Strings.Settings.version(short, build: build)
    }
}
