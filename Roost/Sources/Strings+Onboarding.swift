// The first-run copy, split out of Strings.swift only because that file hit swiftlint's body-length
// cap; it is still `Strings.Onboarding` to every caller.
extension Strings {
    /// First run: what this is, the pairing code, who the server says you are, notifications.
    /// Four screens, one job each. Sentence case in the body, no terminal period on a button.
    enum Onboarding {
        // MARK: step 1 — what this is

        static let welcomeEyebrow = "WELCOME"
        static let welcomeTitle = "Roost"
        /// One sentence. Anne reads this before she has agreed to anything.
        static let welcomeLine = "Roost is one shared chore list for the two of you."
        static let welcomeAction = "Get started"

        // MARK: step 2 — the code

        static let codeEyebrow = "PAIRING"
        static let codeTitle = "Enter your code"
        static let codeLine = "Wes makes a six-digit code on the server. It works once, and only for 15 minutes."
        static let codeWorking = "Pairing…"
        /// The small link under the boxes, for a phone that was handed a token instead of a code.
        static let tokenLink = "Enter a token instead"
        static let retry = "Try again"

        // MARK: step 2 — what went wrong

        /// 404: unknown, already used, or expired. The server answers all three the same way.
        static let codeInvalid = "That code didn't work. Codes last 15 minutes and work once."
        /// 429: too many attempts, per address or across all of them.
        static let codeRateLimited = "Too many tries. Wait a minute, then try again."
        /// 400: the server would not read the body. Should not happen — the field only sends six digits.
        static let codeRejected = "The server didn't accept that code. Six digits, numbers only."
        /// Transport failure: offline, tunnel down, wrong server.
        static let codeOffline = "Couldn't reach the server. Check the connection and try again."

        // MARK: step 2 — the token fallback

        static let tokenTitle = "Device token"
        static let tokenLine = "For a phone that was set up by hand. Paste the token Wes minted on the server."
        static let tokenField = "Device token"
        static let tokenAction = "Connect"
        static let tokenWorking = "Connecting…"
        static let cancel = "Cancel"

        // MARK: step 3 — who you are

        static let confirmEyebrow = "PAIRED"
        /// "You're Anne"
        static func youAre(_ name: String) -> String {
            "You're \(name)"
        }

        static let confirmLine = "This phone is paired. Your chores show up under your name."
        static let confirmAction = "Continue"

        // MARK: step 4 — notifications

        static let notificationsEyebrow = "ONE LAST THING"
        static let notificationsTitle = "Reminders"
        static let notificationsLine = "Roost can list what's due at 9 in the morning, and say something at 6 in the evening when a chore is late."
        static let notificationsAction = "Turn on reminders"
        static let notificationsSkip = "Not now"
        static let notificationsFootnote = "You can change this later in iOS Settings."

        // MARK: the code field, for VoiceOver

        /// The whole field is one element: the label says what it is, the value says what has been typed.
        static let codeFieldLabel = "Pairing code, six digits"
        static let codeFieldHint = "Type the code, or paste it."
        static let codeFieldEmpty = "Empty"
        /// The dots, read out: "Step 2 of 4".
        static func progress(_ step: Int, of total: Int) -> String {
            "Step \(step) of \(total)"
        }

        /// "0 4 8" — spoken a digit at a time, not as "forty-eight".
        static func codeFieldValue(_ digits: String) -> String {
            digits.isEmpty ? codeFieldEmpty : digits.map(String.init).joined(separator: " ")
        }
    }
}
