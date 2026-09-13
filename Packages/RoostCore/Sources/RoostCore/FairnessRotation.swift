import Foundation

/// What one completion is worth when measuring how much someone has done lately.
///
/// PROVISIONAL. Nobody has agreed these numbers; they are a guess that a bigger, rarer job should buy more
/// credit than a two-minute one (cleaning inside the ovens is most of an evening, scooping the litter is not).
/// They are the one knob that changes how `FairnessRotation` behaves, so they live in one place: change them
/// here and the rotation, the README table, and eventually the Node mirror all follow.
public struct FairnessWeights: Codable, Sendable, Hashable {
    public var daily: Int
    public var weekly: Int
    public var biweekly: Int
    public var monthly: Int

    public init(daily: Int, weekly: Int, biweekly: Int, monthly: Int) {
        self.daily = daily
        self.weekly = weekly
        self.biweekly = biweekly
        self.monthly = monthly
    }

    /// daily 1, weekly 3, biweekly 5, monthly 8.
    public static let provisional = FairnessWeights(daily: 1, weekly: 3, biweekly: 5, monthly: 8)

    public func weight(for cadence: Cadence) -> Int {
        switch cadence {
        case .daily: daily
        case .weekly: weekly
        case .biweekly: biweekly
        case .monthly: monthly
        }
    }
}

/// Gives an unpinned chore to whoever has done less lately, instead of strictly taking turns.
///
/// Each person gets a weighted load: every completion inside the trailing `windowDays` Chicago days counts for
/// the weight of its chore's cadence (see `FairnessWeights`). The chore goes to the lower load. When the loads
/// are equal — the common case in a balanced week — it falls through to `tieBreaker`, which is
/// `RoundRobinRotation` by default, so ties still alternate off the same FNV-1a seed per chore and period.
///
/// This is a snapshot: everything it answers is derived from the `(chores, completions, date)` handed to the
/// initializer, so both phones computing from the same rows get the same answer, and the same inputs always
/// give the same output. One consequence of being a snapshot: asking it about a past period answers with
/// *today's* load, not the load back then. That is fine for planning today (the only thing the app asks) and
/// wrong for replaying history, so anything historical should keep using `RoundRobinRotation`.
public struct FairnessRotation: Rotation {
    /// How many trailing Chicago days count toward the load, today included. PROVISIONAL, like the weights.
    public static let windowDays = 14

    public let weights: FairnessWeights
    public let calendar: HouseholdCalendar
    /// Chicago day index of the first day counted (inclusive).
    public let windowFirstDay: Int
    /// Chicago day index of the last day counted (inclusive) — the day containing the reference date.
    public let windowLastDay: Int

    private let loadByPerson: [Person: Int]
    private let tieBreaker: Rotation

    /// - Parameters:
    ///   - chores: used only to look up each completion's cadence. A completion whose chore is not in the list
    ///     is ignored; it cannot be weighted, and guessing would make the answer depend on data we do not have.
    ///   - completions: every completion the caller knows about. Ones outside the window are dropped here.
    ///   - date: "now". The window is the `windowDays` Chicago days ending with this day.
    public init(
        chores: [Chore],
        completions: [Completion],
        asOf date: Date,
        weights: FairnessWeights = .provisional,
        calendar: HouseholdCalendar = HouseholdCalendar(),
        tieBreaker: Rotation = RoundRobinRotation()
    ) {
        self.weights = weights
        self.calendar = calendar
        self.tieBreaker = tieBreaker

        let lastDay = calendar.dayIndex(date)
        let firstDay = lastDay - (FairnessRotation.windowDays - 1)
        windowLastDay = lastDay
        windowFirstDay = firstDay

        let windowStart = calendar.day(at: firstDay)
        let windowEnd = calendar.day(at: lastDay + 1)
        let cadenceByChore = Dictionary(chores.map { ($0.id, $0.cadence) }, uniquingKeysWith: { first, _ in first })

        var loads: [Person: Int] = [:]
        for person in Person.allCases {
            loads[person] = 0
        }
        for completion in completions {
            guard completion.completedAt >= windowStart, completion.completedAt < windowEnd else { continue }
            guard let cadence = cadenceByChore[completion.choreId] else { continue }
            loads[completion.person, default: 0] += weights.weight(for: cadence)
        }
        loadByPerson = loads
    }

    /// Weighted completions for `person` inside the window. Higher means they have done more lately.
    public func load(for person: Person) -> Int {
        loadByPerson[person] ?? 0
    }

    /// The whole board, for the app to show or for tests to assert on.
    public var loads: [Person: Int] {
        loadByPerson
    }

    public func assignee(for chore: Chore, periodIndex: Int) -> Person {
        let anne = load(for: .anne)
        let wes = load(for: .wes)
        if anne != wes {
            return anne < wes ? .anne : .wes
        }
        return tieBreaker.assignee(for: chore, periodIndex: periodIndex)
    }
}
