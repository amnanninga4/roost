import RoostDesign

// The root of the app: three tabs. Tasks is the Today screen; Lists holds Shopping, Meals, Projects and
// Wishlist behind a segmented control; More holds what the gear menu used to. Calendar arrives with the
// reminders design and slots in second; nothing here reserves it a place.
import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case tasks, lists, more

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .tasks: Strings.Tabs.tasks
        case .lists: Strings.Tabs.lists
        case .more: Strings.Tabs.more
        }
    }

    var symbol: String {
        switch self {
        case .tasks: "checklist"
        case .lists: "list.bullet.rectangle"
        case .more: "ellipsis.circle"
        }
    }
}

/// Cross-tab navigation requests, on the counter pattern a tapped push already uses
/// (`PushService.openTasksRequests`): a counter rather than a Bool, so two asks in a row both land
/// even if the reader wandered off between them. The one request today is a chore row's "Show in
/// All chores".
@Observable
final class RootNavigation {
    var selected: RootTab = .tasks
    private(set) var allChoresRequests = 0

    func showAllChores() {
        selected = .more
        allChoresRequests += 1
    }
}

struct RootTabView: View {
    @State private var navigation = RootNavigation()
    @Environment(SyncCoordinator.self) private var sync

    var body: some View {
        TabView(selection: $navigation.selected) {
            ForEach(RootTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    screen(for: tab)
                }
            }
        }
        .tint(RoostColor.accent)
        .environment(navigation)
        // A tapped push lands on Tasks: everything the server pushes is about a chore. A counter rather
        // than a flag, so a second tap works even if the reader has moved to another tab since the first.
        .onChange(of: sync.push.openTasksRequests) {
            navigation.selected = .tasks
        }
    }

    @ViewBuilder
    private func screen(for tab: RootTab) -> some View {
        switch tab {
        case .tasks: TodayScreen()
        case .lists: ListsScreen()
        case .more: MoreScreen()
        }
    }
}
