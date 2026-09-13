// Picks the subtitle for an overdue row from RoostCore's stage and the chore's category. Text lives in Strings.swift.
import Foundation
import RoostCore

enum EscalationCopy {
    /// nil for dueToday: the row shows only its title.
    static func subtitle(stage: EscalationStage, title: String, category: ChoreCategory) -> String? {
        switch stage {
        case .dueToday: nil
        case .nudge: Strings.Escalation.nudge(title: title)
        case .pointed: category == .catCare ? Strings.Escalation.pointedCat : Strings.Escalation.pointedHome
        case .alert: Strings.Escalation.alert(title: title)
        }
    }

    static func subtitle(for row: TodayRow) -> String? {
        guard !row.isDone else { return nil }
        return subtitle(stage: row.stage, title: row.chore.title, category: row.chore.category)
    }
}
