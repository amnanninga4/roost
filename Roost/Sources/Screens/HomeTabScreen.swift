import RoostCore
import RoostDesign
import SwiftUI

struct HomeTabScreen: View {
    @Environment(RootNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.homePath) {
            HomeScreen(onOpenPerson: navigation.showPerson, onOpenMatchup: navigation.showMatchup)
                .navigationTitle(Strings.appTitle)
                .toolbarTitleDisplayMode(.inline)
                .toolbarBackground(RoostColor.Role.background.color, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case let .person(person):
                        PersonDayScreen(person: person, onOpenMatchup: navigation.showMatchup)
                    case .matchup:
                        MatchupScreen(onOpenPerson: navigation.showPerson)
                    case .board:
                        TodayScreen()
                    }
                }
        }
        .tint(RoostColor.Role.accent.color)
    }
}
