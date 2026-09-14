// Copy shared by the app and the widget. Both binaries compile `Shared/`; neither can import the
// other, so wording that must match lives here rather than being duplicated and drifting.
import Foundation

enum RoostCopy {
    /// "1 DAY LATE" / "3 DAYS LATE". The overdue badge on Tasks, Kitchen cards, and the widget chip.
    static func daysLate(_ days: Int) -> String {
        days == 1 ? "1 DAY LATE" : "\(days) DAYS LATE"
    }
}
