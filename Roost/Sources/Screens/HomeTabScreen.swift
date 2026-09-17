// The Home tab: two segments over one navigation stack. Home is arrival; "Anne & Wes" is the
// board that used to be this tab's whole content. The board is not gone and not demoted to More —
// it is one tap away, in the tab the reader is already in.
//
// The segment lives on RootNavigation rather than in @AppStorage here, so the "Anne still has 4"
// line on Home can switch it, and so the board's minute-by-minute TimelineView cannot invalidate
// the picker above it.
import RoostCore
import RoostDesign
import SwiftUI

struct HomeTabScreen: View {
    @Environment(RootNavigation.self) private var navigation
    @State private var personPath: [Person] = []

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $personPath) {
            VStack(spacing: 0) {
                if personPath.isEmpty {
                    RoostSegmentedControl(
                        items: HomeSegment.allCases,
                        selection: $navigation.segment,
                        title: { $0.title },
                        symbol: { $0.symbol }
                    )
                    .padding(.horizontal, RoostSpacing.screenMargin)
                    .padding(.vertical, RoostSpacing.sm)
                }

                switch navigation.segment {
                case .home: HomeScreen(onOpenPerson: { personPath.append($0) })
                case .board: TodayScreen()
                }
            }
            .background(RoostColor.Role.background.color)
            .navigationTitle(Strings.appTitle)
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(for: Person.self) { person in
                PersonDayScreen(person: person)
            }
        }
        .tint(RoostColor.Role.accent.color)
        .onChange(of: navigation.segment) { _, segment in
            if segment != .home {
                personPath = []
            }
        }
    }
}
