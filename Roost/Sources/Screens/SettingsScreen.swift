// More → Settings: what this phone is paired to, and the one way to undo it.
//
// A `Form`, because iOS already knows how a settings screen behaves — rows that grow with the reader's text
// size, a field that lifts itself above the keyboard, a footer that belongs to its section. What the Form
// does not keep here is the system's grey-and-blue look: the page is the app's background, the headers are
// the app's mono eyebrow, the rows sit on the app's surface, and the one red on the screen is the `danger`
// role rather than `Color.red`. Native in behaviour, Roost in look.
//
// The device line comes from the server (`GET /me`), because the name the household recognises — the label
// typed into `mkcode`, joined to the name the phone sent — only exists there. `SettingsModel` owns that call
// and its fallback.
//
// Unpair sits alone at the bottom, and the note it can come back with is shown *before* the app drops back
// to onboarding, because "the server kept your token" is the kind of sentence that has to arrive while there
// is still a screen to read it on.
import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

struct SettingsScreen: View {
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var syncStates: [SyncState]

    /// The same key `RoostApp` reads. Two `@AppStorage`s on one key are one value: writing it here moves
    /// the window's `preferredColorScheme` in the same frame, so the sheet and the screen behind it change
    /// together with nothing to relaunch.
    @AppStorage(Appearance.storageKey) private var storedAppearance = Appearance.system.rawValue

    @State private var model: SettingsModel?
    @State private var confirmingUnpair = false
    @State private var showingNote = false
    @State private var unpairNote = ""
    @State private var unpairing = false
    @State private var serverDraft = ""

    private var state: SyncState? {
        syncStates.first
    }

    /// The server's answer when there is one, else what pairing wrote locally.
    private var person: Person? {
        model?.person ?? state?.person.flatMap(Person.init(rawValue:))
    }

    private var endpoint: URL {
        ServerEndpoint.resolved(stored: state?.baseURL)
    }

    var body: some View {
        Form {
            phoneSection
            appearanceSection
            serverSection
            syncSection
            unpairSection
        }
        .scrollContentBackground(.hidden)
        .background(RoostColor.Role.background.color)
        .roostAnimation(.gentle, value: model?.identity)
        .navigationTitle(Strings.Settings.title)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(Strings.Settings.title)
                    .roostType(.title)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
            }
        }
        .task { await loadIdentity() }
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
        .tint(RoostColor.Role.accent.color)
        // The same answer `RoostApp` gives the window, said again for this sheet. A sheet presented while
        // the window already carries an override keeps the scheme it was born with — verified in the
        // simulator: with Dark already on, picking Light repainted the Tasks screen behind and left this
        // sheet dark until it was dismissed. One line here is what makes the picker turn its own screen
        // over in the same frame as the rest of the app.
        .preferredColorScheme(appearance.wrappedValue.colorScheme)
    }

    // MARK: this phone

    private var phoneSection: some View {
        Section {
            SettingsRow(Strings.Settings.pairedAs) {
                if let person {
                    Label(person.displayName, systemImage: "person.fill")
                        .labelStyle(.titleAndIcon)
                        .roostType(.callout)
                        .foregroundStyle(person.design.color)
                } else {
                    SettingsValue(text: Strings.Settings.notPaired)
                }
            }
            SettingsRow(Strings.Settings.device, value: model?.deviceLine ?? DeviceName.current)
            // Only once the server has said. A phone from the tokens file gets a sentence instead of a date.
            if let since = model?.pairedSince {
                SettingsRow(Strings.Settings.pairedSince, value: since)
            }
        } header: {
            SettingsHeader(Strings.Settings.phoneHeader)
        }
    }

    // MARK: appearance

    /// Three words side by side, because the choice is one glance and one tap rather than a screen to
    /// navigate into. The selection is the app's lightest haptic: the change is already visible everywhere,
    /// so the feel only has to confirm which segment took the tap.
    private var appearanceSection: some View {
        Section {
            appearancePicker
                .accessibilityLabel(Strings.Settings.appearanceLabel)
                .roostHaptic(.selection, trigger: appearance.wrappedValue)
                .listRowBackground(RoostColor.Role.surface.color)
        } header: {
            SettingsHeader(Strings.Settings.appearanceHeader)
        } footer: {
            Text(Strings.Settings.appearanceFooter)
                .roostType(.footnote)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
        }
    }

    /// Segments up to the accessibility sizes, a menu past them. A segmented control divides one row's
    /// width between its choices, which is fine for three short words and unreadable once each word is
    /// 50-odd points tall — at AX1 and up "System" and "Light" are both cut to a letter or two. The menu
    /// style is the same `Picker` drawn as a row: the label leads, the choice sits on the trailing side,
    /// and it grows with the text like every other row on this screen.
    @ViewBuilder
    private var appearancePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private var picker: some View {
        Picker(Strings.Settings.appearanceLabel, selection: appearance) {
            ForEach(Appearance.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        }
    }

    /// The stored raw value, read as a choice. Anything unrecognised reads as `.system` rather than leaving
    /// the picker with no selection.
    private var appearance: Binding<Appearance> {
        Binding(
            get: { Appearance.stored(storedAppearance) },
            set: { storedAppearance = $0.rawValue }
        )
    }

    // MARK: server

    private var serverSection: some View {
        Section {
            #if DEBUG
                TextField(Strings.Settings.serverField, text: $serverDraft)
                    .roostType(.callout)
                    // A placeholder is not a label: it goes away the moment there is a URL in the field,
                    // and then VoiceOver reads the URL with nothing to say what it is.
                    .accessibilityLabel(Strings.Settings.serverField)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { commitServerDraft() }
                    .onAppear { serverDraft = endpoint.absoluteString }
                    .listRowBackground(RoostColor.Role.surface.color)
            #else
                SettingsRow(Strings.Settings.serverField, value: ServerEndpoint.display(endpoint))
            #endif
        } header: {
            SettingsHeader(Strings.Settings.serverHeader)
        } footer: {
            #if DEBUG
                Text(Strings.Settings.serverFooter)
                    .roostType(.footnote)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
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

    // MARK: sync

    private var syncSection: some View {
        Section {
            SettingsRow(Strings.Settings.lastSync, value: lastSyncText)
            SettingsRow(Strings.Settings.status, value: statusText)
        } header: {
            SettingsHeader(Strings.Settings.syncHeader)
        }
    }

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

    private var unpairSection: some View {
        Section {
            // Destructive for the role it plays, `.plain` for the look: a system destructive button paints
            // itself `Color.red`, and the only red this app owns is the danger role.
            Button(role: .destructive) {
                confirmingUnpair = true
            } label: {
                HStack(spacing: RoostSpacing.sm) {
                    Text(Strings.Settings.unpair)
                        .roostType(.headline)
                    if unpairing {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
                .foregroundStyle(RoostColor.Role.danger.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(unpairing)
            .listRowBackground(RoostColor.Role.surface.color)
        } footer: {
            VStack(spacing: RoostSpacing.sm) {
                Text(Strings.Settings.unpairFooter)
                    .roostType(.footnote)
                Text(AppVersion.line)
                    .roostType(.caption)
            }
            .foregroundStyle(RoostColor.Role.textSecondary.color)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, RoostSpacing.xs)
        }
    }

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

    // MARK: identity

    private func loadIdentity() async {
        let model = model ?? SettingsModel(service: sync)
        self.model = model
        await model.refresh()
    }
}

// MARK: - the parts a settings row is made of

/// A section header in the app's mono eyebrow, not the system's grey caps. `textCase(nil)` because the
/// strings are already written in caps, the same as the onboarding eyebrows.
private struct SettingsHeader: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .roostType(.monoLabel)
            .foregroundStyle(RoostColor.Role.textSecondary.color)
            .textCase(nil)
    }
}

/// The value half of a row: the callout rung on the secondary ink.
private struct SettingsValue: View {
    let text: String

    var body: some View {
        Text(text)
            .roostType(.callout)
            .foregroundStyle(RoostColor.Role.textSecondary.color)
    }
}

/// One row: label in the body rung, value on the trailing side, both on the app's surface.
///
/// `LabeledContent` rather than an `HStack` for two reasons that only show up at the edges — VoiceOver reads
/// the pair as one element ("Device, Anne test · iPhone 17 Pro"), and at the largest accessibility sizes it
/// stacks the value under the label instead of squeezing both.
private struct SettingsRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        LabeledContent {
            value
        } label: {
            Text(label)
                .roostType(.body)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
        }
        .listRowBackground(RoostColor.Role.surface.color)
    }
}

extension SettingsRow where Value == SettingsValue {
    /// The common case: a value that is only text.
    init(_ label: String, value: String) {
        self.init(label) { SettingsValue(text: value) }
    }
}

/// "Roost 0.1.0 (1)" — from the bundle, so it is whatever this build actually is. Settings and More both show it.
enum AppVersion {
    static var line: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return Strings.Settings.version(short, build: build)
    }
}
