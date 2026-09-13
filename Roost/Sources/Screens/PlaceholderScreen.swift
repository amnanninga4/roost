// A tab that exists but has no content yet: the title and one plain line.
import SwiftUI
import RoostDesign

struct PlaceholderScreen: View {
    let title: String
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(RoostFont.display(size: RoostFont.Size.title, weight: .bold))
                .foregroundStyle(RoostColor.ink)
            Text(line)
                .font(RoostFont.body(size: RoostFont.Size.meta))
                .foregroundStyle(RoostColor.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .background(RoostColor.bg)
    }
}
