// Semantic colour roles on top of the raw tokens.
//
// `RoostColor.accentToken` is a *value* — the green from the mockup. `RoostColor.Role.success`
// is a *meaning* — "this got done". Screens name meanings, so a screen never has to decide
// whether a finished chore is green, and re-tinting the app later is one edit here.
//
// Several roles deliberately share a token: Anne, cat care, and "done" are all the green.
// That is the mockup's palette, not an accident, and it stays honest because the mapping is
// written down. The one rule: a screen uses `Role`, never a raw `…Token` and never a hex.
import SwiftUI

public extension RoostColor {
    /// Every colour meaning the app has. `.color` resolves light/dark; `.token` is the raw value behind it.
    enum Role: String, Sendable, CaseIterable, Identifiable {
        // MARK: Surfaces

        /// Page background. → `bg`
        case background
        /// Cards, sheets, rows that sit on the background. → `surface`
        case surface
        /// A panel inset inside a card; also a row's pressed/hover fill. → `surface2`
        case surfaceElevated

        // MARK: Text

        /// Titles and body copy. → `ink`
        case textPrimary
        /// Subtitles, meta lines, captions. → `inkSoft`
        case textSecondary

        // MARK: Structure

        /// Hairlines, dividers, the resting stroke of a check control. → `line`
        case separator

        // MARK: Action

        /// The primary action and anything selected. → `accent`
        case accent
        /// The quiet background behind an accent element. → `accentSoft`
        case accentSoft
        /// Text and glyphs sitting *on* an accent fill. → `surface`
        ///
        /// The accent flips lightness between schemes — a dark green in light mode, a pale green
        /// in dark — so a hardcoded white label goes illegible in dark. `surface` is near-white in
        /// light and near-black in dark, which is the right side of the accent in both. The mockup
        /// does the same thing in light mode (`.streak-side.leading .streak-side-name { color: white }`).
        case onAccent

        // MARK: Status — the escalation ladder the app is built around

        /// Done, on time, a claimed chore. Same green as `accent`. → `accent`
        case success
        /// Same green, used as a background. → `accentSoft`
        case successSoft
        /// The nudge: a chore that has been sitting for three days. → `tease`
        case warning
        /// The nudge, as a row background. → `teaseSoft`
        case warningSoft
        /// Five days late. The loudest thing on the screen. → `alert`
        case danger
        /// Five days late, as a row background. → `alertSoft`
        case dangerSoft
        /// Bonus chores and points. → `gold`
        case bonus
        /// Bonus, as a badge background. → `goldSoft`
        case bonusSoft
        /// Auto-assigned or pinned by the rotation. → `assign`
        case assigned
        /// Auto-assigned, as a row background. → `assignSoft`
        case assignedSoft
        /// Neutral notices: sync state, a deadline that is only information. → `info`
        case notice
        /// Neutral notices, as a background. → `infoSoft`
        case noticeSoft

        // MARK: People — the mockup's avatars and tally bars

        /// Anne's colour: `.avatar-a` and `.tally-fill-a` in the mockup. → `accent`
        case anne
        /// Anne's avatar background. → `accentSoft`
        case anneSoft
        /// Wes's colour: `.avatar-p` and `.tally-fill-p` in the mockup. → `info`
        case wes
        /// Wes's avatar background. → `infoSoft`
        case wesSoft

        // MARK: Categories — the mockup's .icon-badge family

        /// Cat care. → `accent`
        case catCare
        /// Cat care badge background. → `accentSoft`
        case catCareSoft
        /// Household chores — the mockup's `.icon-chore`. → `gold`
        case home
        /// Household chores badge background. → `goldSoft`
        case homeSoft
        /// Meals. → `meal`
        case meals
        /// Meals badge background. → `mealSoft`
        case mealsSoft

        // MARK: Depth

        /// Shadow tint. Prefer `.roostElevation(_:)`, which uses this for you. → `shadow`
        case shadow

        public var id: String {
            rawValue
        }

        /// The raw token this role resolves to. Every role maps to a token in `RoostColor.all`.
        public var token: RoostColorToken {
            switch self {
            case .background: RoostColor.bgToken
            case .surface: RoostColor.surfaceToken
            case .surfaceElevated: RoostColor.surface2Token
            case .textPrimary: RoostColor.inkToken
            case .textSecondary: RoostColor.inkSoftToken
            case .separator: RoostColor.lineToken
            case .accent, .success, .anne, .catCare: RoostColor.accentToken
            case .accentSoft, .successSoft, .anneSoft, .catCareSoft: RoostColor.accentSoftToken
            case .onAccent: RoostColor.surfaceToken
            case .warning: RoostColor.teaseToken
            case .warningSoft: RoostColor.teaseSoftToken
            case .danger: RoostColor.alertToken
            case .dangerSoft: RoostColor.alertSoftToken
            case .bonus, .home: RoostColor.goldToken
            case .bonusSoft, .homeSoft: RoostColor.goldSoftToken
            case .assigned: RoostColor.assignToken
            case .assignedSoft: RoostColor.assignSoftToken
            case .notice, .wes: RoostColor.infoToken
            case .noticeSoft, .wesSoft: RoostColor.infoSoftToken
            case .meals: RoostColor.mealToken
            case .mealsSoft: RoostColor.mealSoftToken
            case .shadow: RoostColor.shadowToken
            }
        }

        /// The colour, following the current appearance.
        public var color: Color {
            token.color
        }

        /// The colour pinned to one scheme. For the swatchbook, which shows both at once.
        public func color(_ scheme: ColorScheme) -> Color {
            let rgb = token.rgba(scheme)
            return Color(red: rgb.r, green: rgb.g, blue: rgb.b, opacity: rgb.a)
        }

        /// The soft partner of a strong role, where there is one. `nil` for roles that stand alone.
        public var soft: Role? {
            switch self {
            case .accent: .accentSoft
            case .success: .successSoft
            case .warning: .warningSoft
            case .danger: .dangerSoft
            case .bonus: .bonusSoft
            case .assigned: .assignedSoft
            case .notice: .noticeSoft
            case .anne: .anneSoft
            case .wes: .wesSoft
            case .catCare: .catCareSoft
            case .home: .homeSoft
            case .meals: .mealsSoft
            default: nil
            }
        }
    }

    /// Shorthand for the roles screens touch on every layout pass.
    static var background: Color {
        Role.background.color
    }

    static var textPrimary: Color {
        Role.textPrimary.color
    }

    static var textSecondary: Color {
        Role.textSecondary.color
    }

    static var separator: Color {
        Role.separator.color
    }
}

/// Which of the two of them a thing belongs to. Keeps `Role.anne` / `Role.wes` out of view code.
public enum RoostPerson: String, Sendable, CaseIterable, Identifiable {
    case anne, wes

    public var id: String {
        rawValue
    }

    /// Display name, for a swatch label. App-facing strings live in the app's Strings.swift.
    public var shortName: String {
        switch self {
        case .anne: "Anne"
        case .wes: "Wes"
        }
    }

    public var role: RoostColor.Role {
        switch self {
        case .anne: .anne
        case .wes: .wes
        }
    }

    public var softRole: RoostColor.Role {
        switch self {
        case .anne: .anneSoft
        case .wes: .wesSoft
        }
    }

    public var color: Color {
        role.color
    }

    public var softColor: Color {
        softRole.color
    }
}

/// The kinds of work the app tracks, and the tint each one carries.
public enum RoostCategory: String, Sendable, CaseIterable, Identifiable {
    case catCare, home, meals, bonus

    public var id: String {
        rawValue
    }

    public var role: RoostColor.Role {
        switch self {
        case .catCare: .catCare
        case .home: .home
        case .meals: .meals
        case .bonus: .bonus
        }
    }

    public var softRole: RoostColor.Role {
        switch self {
        case .catCare: .catCareSoft
        case .home: .homeSoft
        case .meals: .mealsSoft
        case .bonus: .bonusSoft
        }
    }

    public var color: Color {
        role.color
    }

    public var softColor: Color {
        softRole.color
    }

    /// The SF Symbol the mockup's badge stands in for.
    public var symbol: String {
        switch self {
        case .catCare: "cat"
        case .home: "house"
        case .meals: "fork.knife"
        case .bonus: "plus.circle"
        }
    }
}
