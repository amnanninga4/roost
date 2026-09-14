// The two mappings the Tasks tab needs between RoostCore's facts and RoostDesign's meanings:
// which colour role each escalation stage wears, and which person a row belongs to.
//
// Keeping them here means no screen decides what "five days late" looks like, and the ladder can be
// asserted in a test (Tests/TodayBoardTests.swift) instead of being read off a view.
import RoostCore
import RoostDesign

extension EscalationStage {
    /// The role the title, the subtitle, and the late badge take. The ladder is deliberately three
    /// different meanings rather than three reds: the nudge's own blue, then a warning, then danger.
    var role: RoostColor.Role {
        switch self {
        case .dueToday: .textPrimary
        case .nudge: .nudge
        case .pointed: .warning
        case .alert: .danger
        }
    }

    /// The soft partner for the stage: the days-late chip's fill on the Tasks tab, the overdue card's
    /// fill in Kitchen mode. `nil` for a row that is only due today. (The Tasks row itself is no
    /// longer washed — the stage there is the leading edge bar in `role`.)
    var fillRole: RoostColor.Role? {
        switch self {
        case .dueToday: nil
        case .nudge: .nudgeSoft
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
