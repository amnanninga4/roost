// The root of the app: four tabs. Tasks is the R-8 Today screen; Shopping, Meals, and Projects are the
// R-11 list screens. The gear menu stays on Tasks.
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
        switch tab {
        case .tasks: TodayScreen()
        case .shopping: ShoppingScreen()
        case .meals: MealsScreen()
        case .projects: ProjectsScreen()
        }
    }
}
