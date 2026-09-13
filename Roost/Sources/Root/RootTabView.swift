// The root of the app: four tabs. Tasks is the R-8 Today screen; the other three are placeholders until
// their tickets land. The gear menu stays on Tasks.
import SwiftUI
import RoostDesign

enum RootTab: String, CaseIterable, Identifiable {
    case tasks, shopping, meals, projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: Strings.Tabs.tasks
        case .shopping: Strings.Tabs.shopping
        case .meals: Strings.Tabs.meals
        case .projects: Strings.Tabs.projects
        }
    }

    var symbol: String {
        switch self {
        case .tasks: "checklist"
        case .shopping: "cart"
        case .meals: "fork.knife"
        case .projects: "hammer"
        }
    }

    /// The one-line body of a placeholder tab; nil for tabs with a real screen.
    var placeholderLine: String? {
        switch self {
        case .tasks: nil
        case .shopping: Strings.Placeholder.shopping
        case .meals: Strings.Placeholder.meals
        case .projects: Strings.Placeholder.projects
        }
    }
}

struct RootTabView: View {
    @State private var selected: RootTab = .tasks

    var body: some View {
        TabView(selection: $selected) {
            ForEach(RootTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    screen(for: tab)
                }
            }
        }
        .tint(RoostColor.accent)
    }

    @ViewBuilder
    private func screen(for tab: RootTab) -> some View {
        if let line = tab.placeholderLine {
            PlaceholderScreen(title: tab.title, line: line)
        } else {
            TodayScreen()
        }
    }
}
