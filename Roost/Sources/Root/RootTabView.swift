import RoostDesign

// The root of the app: three tabs. Home is arrival (with the board one segment away); Lists holds
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

/// The two halves of the Home tab. Home is arrival; the board is the two columns, which are the
/// same screen they have always been.
enum HomeSegment: String, CaseIterable, Identifiable {
    case home, board

    /// Where the remembered segment is written, spelled once so the app, the tests and the UI-test
    /// launch reset cannot disagree. Renaming it silently sends every phone back to Home.
    static let storageKey = "roost.home.segment"

    /// What a stored string means, including one this build has never heard of: `.home`, the arrival
    /// screen, rather than nothing. Same read as `Appearance.stored`.
    static func stored(_ raw: String?) -> HomeSegment {
        raw.flatMap(HomeSegment.init(rawValue:)) ?? .home
    }

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .home: Strings.Home.segmentHome
        case .board: Strings.Home.segmentBoard
        }
    }

    var symbol: String {
        switch self {
        case .home: Strings.Home.segmentHomeSymbol
        case .board: Strings.Home.segmentBoardSymbol
        }
    }
}

/// Cross-tab navigation, as state the tabs read rather than requests they must catch: a chore row's
/// "Show in All chores" sets the More tab's path *and then* selects the tab, so the tab's
/// `NavigationStack` is born already showing the list. (Pushing after the tab appears is the
/// alternative, and on iOS 26 a push made during the tab transition either loops layout or is
/// dropped — both seen in the simulator.)
@Observable
final class RootNavigation {
    var selected: RootTab = .home

    /// Which half of the Home tab is showing. Lives here rather than inside the screen so a cross-tab
    /// jump can set both at once, and so a minute tick in the board's TimelineView cannot invalidate it.
    ///
    /// Remembered across launches, so whoever lives on the board is not sent back to the foyer every
    /// morning. The write is by hand rather than `@AppStorage`, and not by preference: `@AppStorage`
    /// cannot be a property of an `@Observable` class — the macro and the wrapper both synthesize
    /// `_segment`, which does not compile — and `@ObservationIgnored @AppStorage` gets past that only by
    /// taking the property out of observation, which is the one thing the segmented control and
    /// `showBoard()` depend on. The key and the stored raw string are what an `@AppStorage` would have
    /// written, so either could read the other's value.
    var segment: HomeSegment = .home {
        didSet {
            guard segment != oldValue else { return }
            defaults.set(segment.rawValue, forKey: HomeSegment.storageKey)
        }
    }

    /// The More tab's navigation path. Empty is the More page itself.
    var morePath: [MoreRoute] = []

    @ObservationIgnored private let defaults: UserDefaults

    /// `defaults` is a parameter so a test can pin the key against its own suite rather than the
    /// phone's. The remembered segment is read here, which is what makes a relaunch land where the
    /// reader left off.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        segment = HomeSegment.stored(defaults.string(forKey: HomeSegment.storageKey))
    }

    func showAllChores() {
        morePath = [.allChores]
        selected = .more
    }

    /// From Home's "Anne still has 4" line: the board, in the tab the reader is already in.
    func showBoard() {
        segment = .board
        selected = .home
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
            navigation.selected = .home
            navigation.segment = .home
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
