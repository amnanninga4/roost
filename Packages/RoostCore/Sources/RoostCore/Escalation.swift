import Foundation

/// How loud an overdue task is. The ladder is the one in the concept mockup; copy lives in the app.
public enum EscalationStage: Int, Sendable, Comparable, CaseIterable {
    /// Due in the current period, nothing missed yet.
    case dueToday = 0
    /// 1–2 days past the period.
    case nudge = 1
    /// 3–4 days past.
    case pointed = 3
    /// 5+ days past: shown to both people until done.
    case alert = 5

    public static func stage(daysOverdue: Int) -> EscalationStage {
        switch daysOverdue {
        case ..<1: return .dueToday
        case 1..<3: return .nudge
        case 3..<5: return .pointed
        default: return .alert
        }
    }

    public static func < (lhs: EscalationStage, rhs: EscalationStage) -> Bool { lhs.rawValue < rhs.rawValue }
}
