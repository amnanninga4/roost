// The More tab: what the gear menu used to hold, as a page. Household things first, then this phone's,
// then the version line Settings also shows. Kitchen mode opens full screen as before; the other rows push.
import RoostDesign
import SwiftUI

struct MoreScreen: View {
    @Environment(SyncCoordinator.self) private var sync
    @Environment(RootNavigation.self) private var navigation
    @State private var showKitchen = false

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.morePath) {
            List {
                Section {
                    Button { navigation.showBoard() } label: {
                        MoreRow(title: Strings.More.board, symbol: "checklist")
                    }
                    .accessibilityIdentifier("more.choreBoard")
                    .listRowBackground(RoostColor.Role.surface.color)
                    Button { showKitchen = true } label: {
                        MoreRow(title: Strings.Kitchen.menuEntry, symbol: "rectangle.on.rectangle")
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(RoostColor.Role.surface.color)
                    NavigationLink(value: MoreRoute.allChores) {
                        MoreRow(title: Strings.Tasks.allChores, symbol: "list.bullet")
                    }
                    .listRowBackground(RoostColor.Role.surface.color)
                } header: {
                    MoreHeader(Strings.More.household)
                }
                Section {
                    NavigationLink {
                        SettingsScreen()
                    } label: {
                        MoreRow(title: Strings.Settings.title, symbol: "iphone.and.arrow.forward")
                    }
                    .listRowBackground(RoostColor.Role.surface.color)
                    Button { sync.syncSoon() } label: {
                        MoreRow(
                            title: Strings.Tasks.syncNow,
                            symbol: "arrow.triangle.2.circlepath",
                            detail: sync.statusLine
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(RoostColor.Role.surface.color)
                } header: {
                    MoreHeader(Strings.More.thisPhone)
                } footer: {
                    Text(AppVersion.line)
                        .accessibilityIdentifier("more.version")
                        .roostType(.caption)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                        .frame(maxWidth: .infinity)
                        .padding(.top, RoostSpacing.sm)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(RoostSpacing.md)
            .scrollContentBackground(.hidden)
            .background(RoostColor.Role.background.color)
            .navigationTitle(Strings.Tabs.more)
            .toolbarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showKitchen) { KitchenScreen() }
            .navigationDestination(for: MoreRoute.self) { route in
                switch route {
                case .allChores: ChoreListScreen()
                }
            }
        }
        .tint(RoostColor.Role.accent.color)
    }
}

/// One row: a symbol in the accent, the title, and an optional second line (the sync status under Sync now).
/// One element to VoiceOver, named by the title, with the second line as its value.
private struct MoreRow: View {
    let title: String
    let symbol: String
    var detail: String?

    var body: some View {
        HStack(spacing: RoostSpacing.md) {
            Image(systemName: symbol)
                .roostType(.body)
                .dynamicTypeSize(.large)
                .foregroundStyle(RoostColor.Role.accent.color)
                .frame(width: RoostSpacing.xl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                Text(title)
                    .roostType(.body)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                if let detail {
                    Text(detail)
                        .roostType(.caption)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, RoostSpacing.xxs)
        .frame(minHeight: RoostSpacing.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(detail ?? "")
    }
}

/// A section header in the app's mono eyebrow, the same as Settings'.
private struct MoreHeader: View {
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
