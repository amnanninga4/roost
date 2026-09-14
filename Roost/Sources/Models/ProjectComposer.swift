// Pure helpers for the Projects composer: what Return on the title field does, and when the
// first-steps field stays on screen. Tested in ListCraftTests so the start() path cannot wipe
// steps without a test noticing.
import Foundation

enum ProjectComposer {
    /// Whether the first-steps field should stay visible. Visible once there is a title *or* once
    /// the user has already typed steps — Return on a blank title must not hide what they wrote.
    static func showsFirstSteps(title: String, steps: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !steps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Return on the title field. Never creates a project and never clears `steps`. A blank/whitespace
    /// title is trimmed to empty so the keyboard can go away; a real title is left alone for the
    /// Start button.
    static func afterTitleReturn(title: String, steps: String) -> (title: String, steps: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return ("", steps)
        }
        return (title, steps)
    }
}
