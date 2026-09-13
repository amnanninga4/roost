// The two mappings the Tasks tab needs between RoostCore's facts and RoostDesign's meanings:
// which colour role each escalation stage wears, and which person a row belongs to.
//
// Keeping them here means no screen decides what "five days late" looks like, and the ladder can be
// asserted in a test (Tests/TodayBoardTests.swift) instead of being read off a view.
import RoostCore
import RoostDesign

extension EscalationStage {
    /// The role the title, the subtitle, and the late badge take. The ladder is deliberately three
    /// different meanings rather than three reds: information, then a warning, then danger.
    var role: RoostColor.Role {
        switch self {
        case .dueToday: .textPrimary
        case .nudge: .notice
        case .pointed: .warning
        case .alert: .danger
        }
    }

    /// The fill behind an overdue row. `nil` for a row that is only due today: it sits on the card with
    /// no fill, so anything carrying colour on the card is something that is running late.
    var fillRole: RoostColor.Role? {
        switch self {
        case .dueToday: nil
        case .nudge: .noticeSoft
        case .pointed: .warningSoft
        case .alert: .dangerSoft
        }
    }

    /// From three days late the row is not just yours any more: it is bright on the other phone, and at
    /// five the server pushes it there (`server/src/push.js`).
    var isSharedWithTheOther: Bool {
        self >= .pointed
    }
}

// `Person.design` — the RoostPerson a Person maps to, which the column header's dot and the week bar's two
// halves both read — lives in `Onboarding/OnboardingPage.swift`, next to `Person.initial`. One definition,
// wherever it was first needed.
