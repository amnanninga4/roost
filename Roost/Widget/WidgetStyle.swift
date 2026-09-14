// The widget's two mappings from the snapshot to RoostDesign meanings: which colour role a stage wears,
// and which role a person wears.
//
// These deliberately mirror `Roost/Sources/Tasks/TaskStyle.swift` and `RoostPerson`. The extension cannot
// import the app, so the ladder is written twice — but it is written once *per binary*, in one file each,
// so the two can be compared at a glance rather than hunted through views. `WidgetSnapshotTests` pins the
// app's half of it.
import RoostDesign
import SwiftUI

extension RoostSnapshot.Stage {
    /// The nudge's own blue, then a warning, then danger — the Tasks tab's ladder, not three reds.
    var role: RoostColor.Role {
        switch self {
        case .dueToday: .textSecondary
        case .nudge: .nudge
        case .pointed: .warning
        case .alert: .danger
        }
    }

    /// The dot beside a title on the medium family. A row that is merely due today gets no dot: anything
    /// carrying colour on the widget is something running late.
    var carriesColour: Bool {
        self != .dueToday
    }
}

extension RoostSnapshot.Person {
    /// Anne is the green, Wes the blue — the mockup's avatar colours, through `RoostPerson`.
    var design: RoostPerson {
        RoostPerson(rawValue: id) ?? .anne
    }
}

extension RoostSnapshot.Person {
    /// The stage of the most-overdue top row, or `.alert` when the overdue count is positive but the
    /// top list is empty — the chip still needs a colour from the ladder.
    var loudestOverdueStage: RoostSnapshot.Stage {
        let overdue = top.filter { $0.daysOverdue > 0 }
        guard let loudest = overdue.max(by: { $0.daysOverdue < $1.daysOverdue }) else {
            return .alert
        }
        return loudest.stage
    }
}
