// The Lists tab: Shopping, Meals, Projects and Wishlist under one roof. A segmented control picks the
// page and a paged TabView under it scrolls to the same page, so a tap and a swipe do the same thing and
// every page keeps its own state — its draft, its open cards, its five-second undo — while another one is
// showing. The chosen page is remembered per phone. The list chrome is applied here, once, so the pages
// are plain `List` bodies.
import RoostDesign
import SwiftUI

/// The four pages, in bar order. The raw values are what `AppStorage` writes, so they must not change.
enum ListPage: String, CaseIterable, Identifiable {
    case shopping, meals, projects, wishlist

    static let storageKey = "roost.lists.page"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .shopping: Strings.Tabs.shopping
        case .meals: Strings.Tabs.meals
        case .projects: Strings.Tabs.projects
        case .wishlist: Strings.Tabs.wishlist
        }
    }

    /// What the segments show at accessibility text sizes, where four words no longer fit.
    var symbol: String {
        switch self {
        case .shopping: "cart"
        case .meals: "fork.knife"
        case .projects: "hammer"
        case .wishlist: "gift"
        }
    }
}

struct ListsScreen: View {
    @AppStorage(ListPage.storageKey) private var page: ListPage = .shopping
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                picker
                    .padding(.horizontal, RoostSpacing.screenMargin)
                    .padding(.vertical, RoostSpacing.sm)
                TabView(selection: $page) {
                    ForEach(ListPage.allCases) { page in
                        pageBody(page)
                            .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .listTabChrome()
        }
        .tint(RoostColor.Role.accent.color)
    }

    private var picker: some View {
        Picker(Strings.Tabs.lists, selection: $page) {
            ForEach(ListPage.allCases) { page in
                if typeSize.isAccessibilitySize {
                    Image(systemName: page.symbol)
                        .accessibilityLabel(page.title)
                        .tag(page)
                } else {
                    Text(page.title)
                        .tag(page)
                }
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("listsPicker")
    }

    @ViewBuilder
    private func pageBody(_ page: ListPage) -> some View {
        switch page {
        case .shopping: ShoppingScreen()
        case .meals: MealsScreen()
        case .projects: ProjectsScreen()
        case .wishlist: WishlistScreen()
        }
    }
}
