// Roost spacing: one 4-pt scale, plus the four semantic values every screen needs.
//
// iOS is laid out on a 4-pt grid, so every value here is a multiple of 4 except `xxs`,
// which is the 2-pt hairline gap used between items inside a single group. Screens use
// the semantic values (`screenMargin`, `cardPadding`, `rowPadding`, `sectionGap`) and
// reach for the raw scale only for one-off gaps. Never type a literal number in a screen.
//
// Provenance: the mockup's phone frame uses 16-pt side margins (`.screen-body`
// padding: 14px 16px 20px), 12-pt row padding (`.item` padding: 10px 6px, rounded up to
// the grid), and roughly 18-24 pt between labelled sections (`.section-label` margin: 18px).
import SwiftUI

public enum RoostSpacing {
    /// 2 — hairline gap inside one group (title over its subtitle's meta line).
    public static let xxs: CGFloat = 2
    /// 4 — icon-to-text, title-to-subtitle. Anything tighter reads as a typo.
    public static let xs: CGFloat = 4
    /// 8 — standard small gap: row content, chips in a line.
    public static let sm: CGFloat = 8
    /// 12 — row padding, compact card padding.
    public static let md: CGFloat = 12
    /// 16 — screen margin, standard card padding.
    public static let lg: CGFloat = 16
    /// 24 — between sections, card to card. Also the breathing room a hero number wants.
    public static let xl: CGFloat = 24
    /// 32 — large break between unrelated blocks.
    public static let xxl: CGFloat = 32
    /// 48 — hero spacing; empty states and celebration screens.
    public static let xxxl: CGFloat = 48

    // MARK: Semantic

    /// 16 — the left/right margin of every screen. Matches the mockup's phone frame.
    public static let screenMargin: CGFloat = lg
    /// 16 — padding inside a card. Cards want the same margin as the screen.
    public static let cardPadding: CGFloat = lg
    /// 12 — vertical padding of a tappable row. With a 21-pt control this clears 44 pt.
    public static let rowPadding: CGFloat = md
    /// 24 — gap between two labelled sections on one screen.
    public static let sectionGap: CGFloat = xl

    /// The scale in order, for the swatchbook and the tests.
    public static let scale: [(name: String, value: CGFloat)] = [
        ("xxs", xxs), ("xs", xs), ("sm", sm), ("md", md),
        ("lg", lg), ("xl", xl), ("xxl", xxl), ("xxxl", xxxl),
    ]

    /// The semantic values in order, for the swatchbook and the tests.
    public static let semantic: [(name: String, value: CGFloat)] = [
        ("screenMargin", screenMargin), ("cardPadding", cardPadding),
        ("rowPadding", rowPadding), ("sectionGap", sectionGap),
    ]

    /// Apple's minimum comfortable tap target. Use with `.frame(minHeight:)`, never a fixed height,
    /// so a row still grows at large Dynamic Type sizes.
    public static let minTapTarget: CGFloat = 44
}
