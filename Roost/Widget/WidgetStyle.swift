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
    /// Information, then a warning, then danger — the Tasks tab's ladder, not three reds.
    var role: RoostColor.Role {
        switch self {
        case .dueToday: .textSecondary
        case .nudge: .notice
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
