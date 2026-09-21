// Native sans typography. Semantic text styles provide the system Dynamic Type ramp.
import SwiftUI

public enum RoostType {
    /// The three faces, with their fallback when the family is not registered.
    public enum Face: String, Sendable, CaseIterable {
        case display, body, mono

        public var family: String {
            switch self {
            case .display: RoostFont.Family.display
            case .body: RoostFont.Family.body
            case .mono: RoostFont.Family.mono
            }
        }

        /// The system design used when the custom family is missing (previews, tests, a failed register).
        public var fallbackDesign: Font.Design {
            switch self {
            case .display: .default
            case .body: .default
            case .mono: .default
            }
        }

        public var isAvailable: Bool {
            RoostFont.isAvailable(family)
        }
    }

    /// One rung of the ramp: a face, a base size, the text style it scales with, and its trimmings.
    public struct Spec: Sendable, Hashable, Identifiable {
        public let name: String
        public let face: Face
        /// Base size at the `.large` (default) Dynamic Type setting.
        public let size: CGFloat
        /// The system text style this rung scales with.
        public let textStyle: Font.TextStyle
        public let weight: Font.Weight
        /// Extra letter-spacing. Non-zero only for the uppercase mono labels, where caps need it.
        public let tracking: CGFloat
        /// Added to the natural line height, for the styles that set running text.
        public let lineSpacing: CGFloat
        /// Display sizes read better with the font's tight leading.
        public let tightLeading: Bool
        /// Keeps digit columns from shifting width as numbers change.
        public let monospacedDigit: Bool
        public let usage: String

        public var id: String {
            name
        }

        public init(
            name: String,
            face: Face,
            size: CGFloat,
            textStyle: Font.TextStyle,
            weight: Font.Weight,
            tracking: CGFloat = 0,
            lineSpacing: CGFloat = 0,
            tightLeading: Bool = false,
            monospacedDigit: Bool = false,
            usage: String
        ) {
            self.name = name
            self.face = face
            self.size = size
            self.textStyle = textStyle
            self.weight = weight
            self.tracking = tracking
            self.lineSpacing = lineSpacing
            self.tightLeading = tightLeading
            self.monospacedDigit = monospacedDigit
            self.usage = usage
        }

        /// Native semantic font, scaling with Dynamic Type independently of bundled fonts.
        public var font: Font {
            var resolved = Font.system(textStyle, design: face.fallbackDesign, weight: weight)
            if tightLeading {
                resolved = resolved.leading(.tight)
            }
            if monospacedDigit {
                resolved = resolved.monospacedDigit()
            }
            return resolved
        }
    }

    /// The ramp. `RoostType.Style.body.font` or, more usually, `.roostType(.body)` on a view.
    public enum Style: String, Sendable, CaseIterable {
        case displayLarge, display, title, rowTitle
        case headline, body, callout, subheadline, footnote, caption
        case monoTally, monoLabel

        public var spec: Spec {
            switch self {
            case .displayLarge:
                Spec(
                    name: "displayLarge", face: .display, size: 34, textStyle: .largeTitle, weight: .semibold,
                    tightLeading: true, usage: "Screen title — \"Today\". One per screen."
                )
            case .display:
                Spec(
                    name: "display", face: .display, size: 28, textStyle: .title, weight: .semibold,
                    tightLeading: true, usage: "Hero line: empty states, celebration screens, a streak number."
                )
            case .title:
                Spec(
                    name: "title", face: .display, size: 22, textStyle: .title2, weight: .semibold,
                    tightLeading: true, usage: "Card and section titles."
                )
            case .rowTitle:
                Spec(
                    name: "rowTitle", face: .display, size: 17, textStyle: .headline, weight: .semibold,
                    usage: "The title of a chore row."
                )
            case .headline:
                Spec(
                    name: "headline", face: .body, size: 17, textStyle: .headline, weight: .semibold,
                    usage: "Emphasised sans line: a form label, a row title that is not a chore."
                )
            case .body:
                Spec(
                    name: "body", face: .body, size: 17, textStyle: .body, weight: .regular,
                    lineSpacing: 3, usage: "Body copy. The default for anything read in sentences."
                )
            case .callout:
                Spec(
                    name: "callout", face: .body, size: 16, textStyle: .callout, weight: .regular,
                    lineSpacing: 3, usage: "Slightly smaller body: notes, explanations under a control."
                )
            case .subheadline:
                Spec(
                    name: "subheadline", face: .body, size: 15, textStyle: .subheadline, weight: .regular,
                    lineSpacing: 2, usage: "Row subtitle and meta line (\"Anne · due Friday\")."
                )
            case .footnote:
                Spec(
                    name: "footnote", face: .body, size: 13, textStyle: .footnote, weight: .regular,
                    lineSpacing: 2, usage: "Hints and secondary detail."
                )
            case .caption:
                Spec(
                    name: "caption", face: .body, size: 12, textStyle: .caption, weight: .regular,
                    usage: "The smallest readable sans text. Timestamps, tag text."
                )
            case .monoLabel:
                Spec(
                    name: "monoLabel", face: .mono, size: 12, textStyle: .caption, weight: .semibold,
                    tracking: 1, usage: "Uppercase eyebrow label (\"CAT CARE\"). Tracking is the caps allowance."
                )
            case .monoTally:
                Spec(
                    name: "monoTally", face: .mono, size: 13, textStyle: .footnote, weight: .medium,
                    monospacedDigit: true, usage: "Tallies, counts, streak numbers. Digits hold their column."
                )
            }
        }

        public var font: Font {
            spec.font
        }
    }

    /// Every rung, in ramp order.
    public static let all: [Spec] = Style.allCases.map(\.spec)

    // MARK: Fonts

    public static var displayLarge: Font {
        Style.displayLarge.font
    }

    public static var display: Font {
        Style.display.font
    }

    public static var title: Font {
        Style.title.font
    }

    public static var rowTitle: Font {
        Style.rowTitle.font
    }

    public static var headline: Font {
        Style.headline.font
    }

    public static var body: Font {
        Style.body.font
    }

    public static var callout: Font {
        Style.callout.font
    }

    public static var subheadline: Font {
        Style.subheadline.font
    }

    public static var footnote: Font {
        Style.footnote.font
    }

    public static var caption: Font {
        Style.caption.font
    }

    public static var monoLabel: Font {
        Style.monoLabel.font
    }

    public static var monoTally: Font {
        Style.monoTally.font
    }

    // MARK: Dynamic Type reference

    /// The system `.body` point size at each Dynamic Type setting: 14 pt at `.xSmall` through 53 pt at
    /// `.accessibility5`.
    public static func referenceBodySize(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 14
        case .small: 15
        case .medium: 16
        case .large: 17
        case .xLarge: 19
        case .xxLarge: 21
        case .xxxLarge: 23
        case .accessibility1: 28
        case .accessibility2: 33
        case .accessibility3: 40
        case .accessibility4: 47
        case .accessibility5: 53
        @unknown default: 17
        }
    }

    /// How much text grows at a Dynamic Type setting, relative to `.large`.
    public static func multiplier(for size: DynamicTypeSize) -> CGFloat {
        referenceBodySize(for: size) / referenceBodySize(for: .large)
    }

    /// The approximate rendered size of a rung at a Dynamic Type setting.
    ///
    /// This is a reference number, not the mechanism: The native semantic font does the real
    /// scaling, and the system compresses growth at the largest sizes for the big text styles. Use this
    /// for layout maths that has to reserve space, for measuring, and in tests.
    public static func scaledSize(_ style: Style, at size: DynamicTypeSize) -> CGFloat {
        style.spec.size * multiplier(for: size)
    }
}

// MARK: - Modifiers

private struct RoostTypeModifier: ViewModifier {
    let spec: RoostType.Spec

    func body(content: Content) -> some View {
        content
            .font(spec.font)
            .tracking(spec.tracking)
            .lineSpacing(spec.lineSpacing)
    }
}

public extension View {
    /// Applies a rung of the ramp: font, tracking, and line spacing together.
    ///
    ///     Text(chore.title).roostType(.rowTitle)
    ///     Text("CAT CARE").roostType(.monoLabel)
    func roostType(_ style: RoostType.Style) -> some View {
        modifier(RoostTypeModifier(spec: style.spec))
    }
}

public extension Text {
    /// Same as `roostType`, kept on `Text` so it can be chained before `Text`-only modifiers.
    func roostFont(_ style: RoostType.Style) -> Text {
        var text = font(style.font)
        if style.spec.tracking != 0 {
            text = text.tracking(style.spec.tracking)
        }
        return text
    }
}
