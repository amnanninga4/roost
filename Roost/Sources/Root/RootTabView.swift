import RoostCore
import RoostDesign

// The root of the app: three tabs. Home is arrival (with profiles and Matchup); Lists holds
// Shopping, Meals, Projects and Wishlist behind a segmented control; More holds what the gear menu
// used to. Calendar arrives with the reminders design and slots in second; nothing here reserves
// it a place.
import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    // The raw value stays "tasks" after the rename to .home. It is what any persisted selection
    // already holds, and changing it would reset the open tab on every phone that upgrades —
    // a silent, confusing one-off for a cosmetic gain.
    case home = "tasks"
    case lists
    case more

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .home: Strings.Home.title
        case .lists: Strings.Tabs.lists
        case .more: Strings.Tabs.more
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .lists: "list.bullet.rectangle"
        case .more: "ellipsis.circle"
        }
    }
}

enum HomeRoute: Hashable {
    case person(Person)
    case matchup
    case board
}

@MainActor
@Observable
final class RootNavigation {
    var selected: RootTab = .home
    var homePath: [HomeRoute] = []
    var morePath: [MoreRoute] = []

    func showHome() {
        homePath = []
        selected = .home
    }

    func showPerson(_ person: Person) {
        if homePath.last != .person(person) {
            homePath.append(.person(person))
        }
        selected = .home
    }

    func showMatchup() {
        if homePath.last != .matchup {
            homePath.append(.matchup)
        }
        selected = .home
    }

    func showBoard() {
        homePath = [.board]
        selected = .home
    }

    func showAllChores() {
        morePath = [.allChores]
        selected = .more
    }
}

/// What the More tab can push. Settings stays a plain link; only routes another tab needs to reach
/// belong here.
enum MoreRoute: Hashable {
    case allChores
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
        // A tapped push lands on Home: everything the server pushes is about a chore, and Home
        // carries this phone's chores. A counter rather than a flag, so a second tap works even if
        // the reader has moved to another tab since the first.
        .onChange(of: sync.push.openTasksRequests) {
            navigation.showHome()
        }
    }

    @ViewBuilder
    private func screen(for tab: RootTab) -> some View {
        switch tab {
        case .home: HomeTabScreen()
        case .lists: ListsScreen()
        case .more: MoreScreen()
        }
    }
}
