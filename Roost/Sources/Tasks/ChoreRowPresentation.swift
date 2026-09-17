import RoostCore
import RoostDesign

enum ChoreRowPresentation {
    static func titleRole(isDone: Bool, stage: EscalationStage, style: ChoreRowView.Style) -> RoostColor.Role {
        if isDone || style == .quiet {
            return .textSecondary
        }
        if stage == .alert {
            return .danger
        }
        return .textPrimary
    }

    /// Home drops the escalation subtitle; it repeats the title as "X emergency".
    static func showsSubtitle(_ subtitle: String, title: String, allowed: Bool) -> Bool {
        guard allowed else { return false }
        return !subtitle.lowercased().hasPrefix(title.lowercased())
    }
}
