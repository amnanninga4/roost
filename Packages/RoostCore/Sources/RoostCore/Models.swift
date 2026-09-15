import Foundation

/// The household. Mirrors `PEOPLE` in server/src/db.js and the `fixedAssignee` values in data/chores.json.
public enum Person: String, Codable, CaseIterable, Sendable, Hashable {
    case anne
    case wes

    /// The other person in the household.
    public var other: Person {
        self == .anne ? .wes : .anne
    }
}

public enum Cadence: String, Codable, CaseIterable, Sendable, Hashable {
    case daily
    case weekly
    case biweekly
    case monthly
    case bimonthly
    case quarterly

    /// How many calendar months one period spans, for the month-based cadences; nil for the day-based ones.
    public var monthsPerPeriod: Int? {
        switch self {
        case .daily, .weekly, .biweekly: nil
        case .monthly: 1
        case .bimonthly: 2
        case .quarterly: 3
        }
    }
}

public enum ChoreCategory: String, Codable, CaseIterable, Sendable, Hashable {
    case chore
    case catCare = "cat_care"
}

/// The months a chore is in season: `"season": { "months": [4, 5, 6, 7, 8, 9, 10] }` in data/chores.json.
/// A chore with a season is due only in periods whose first day falls in one of these months.
public struct Season: Codable, Sendable, Hashable {
    public let months: Set<Int>

    public init(months: Set<Int>) {
        self.months = months
    }

    /// Whether a period whose first day falls in `month` (1...12) is in season.
    public func contains(month: Int) -> Bool {
        months.contains(month)
    }
}

/// How an unpinned chore picks its person, when the chore states it rather than taking the default
/// hash-and-alternate. Decoded from `"rotation"` in data/chores.json.
public enum ChoreRotation: Codable, Sendable, Hashable {
    /// One to four Monday-first week tables, used in turn. Daily chores only: a daily chore's period
    /// index is its day index from the anchor, and the anchor is a Monday.
    case weekdayCycle(weeks: [[Person]])
    /// `start` owns every even period index, the other person the odd ones. Not keyed off activeFrom:
    /// a rotation that moved when the household start date changed would reassign months already lived.
    case alternate(start: Person)

    public func assignee(periodIndex: Int) -> Person {
        switch self {
        case let .weekdayCycle(weeks):
            guard !weeks.isEmpty else { return .anne }
            let week = weeks[mod(floorDiv(periodIndex, 7), weeks.count)]
            guard week.count == 7 else { return .anne }
            return week[mod(periodIndex, 7)]
        case let .alternate(start):
            return mod(periodIndex, 2) == 0 ? start : start.other
        }
    }

    enum CodingKeys: String, CodingKey { case kind, weeks, start }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "weekdayCycle": self = try .weekdayCycle(weeks: c.decode([[Person]].self, forKey: .weeks))
        case "alternate": self = try .alternate(start: c.decode(Person.self, forKey: .start))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: c,
                debugDescription: "unknown rotation kind '\(other)'"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .weekdayCycle(weeks):
            try c.encode("weekdayCycle", forKey: .kind); try c.encode(weeks, forKey: .weeks)
        case let .alternate(start):
            try c.encode("alternate", forKey: .kind); try c.encode(start, forKey: .start)
        }
    }
}

/// Hand this chore's period to whoever missed more than `overMisses` days of `watch` inside it.
public struct MissPenalty: Codable, Sendable, Hashable {
    public let watch: String
    public let overMisses: Int
    public init(watch: String, overMisses: Int) {
        self.watch = watch; self.overMisses = overMisses
    }
}

private func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}

private func mod(_ a: Int, _ b: Int) -> Int {
    let r = a % b
    return r < 0 ? r + b : r
}

/// One row of data/chores.json.
public struct Chore: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let cadence: Cadence
    public let fixedAssignee: Person?
    public let category: ChoreCategory
    /// Absent for almost every chore. Present: due only in periods that start in one of these months.
    public let season: Season?
    /// Owed by both people at once: a row in each column, one check-off clears both, credit for both,
    /// no handoffs and no balancing. Never pinned (`fixedAssignee` is nil).
    public let together: Bool
    /// Weekly only: ISO weekdays (Monday = 1 … Sunday = 7) the chore is due on; the window runs from the
    /// earliest to the latest. Nil for a whole-week chore.
    public let weekdays: [Int]?
    /// Monthly, bimonthly and quarterly: the day of the period's last month the chore is due by (1...28);
    /// the window is the seven days ending on it. Nil for a whole-period chore.
    public let dueDay: Int?
    /// Optional stated rotation; when present, beats the default hash round-robin and is never balanced.
    public let rotation: ChoreRotation?
    /// Optional miss consequence: move this chore's period to whoever missed too many days of `watch`.
    public let missPenalty: MissPenalty?

    public init(
        id: String,
        title: String,
        cadence: Cadence,
        fixedAssignee: Person? = nil,
        category: ChoreCategory,
        season: Season? = nil,
        together: Bool = false,
        weekdays: [Int]? = nil,
        dueDay: Int? = nil,
        rotation: ChoreRotation? = nil,
        missPenalty: MissPenalty? = nil
    ) {
        self.id = id
        self.title = title
        self.cadence = cadence
        self.fixedAssignee = fixedAssignee
        self.category = category
        self.season = season
        self.together = together
        self.weekdays = weekdays
        self.dueDay = dueDay
        self.rotation = rotation
        self.missPenalty = missPenalty
    }

    enum CodingKeys: String, CodingKey {
        case id, title, cadence, fixedAssignee, category, season, together, weekdays, dueDay, rotation, missPenalty
    }

    /// Optional keys default when absent, so a version-1–4 file and every fixture keep decoding.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        cadence = try c.decode(Cadence.self, forKey: .cadence)
        fixedAssignee = try c.decodeIfPresent(Person.self, forKey: .fixedAssignee)
        category = try c.decode(ChoreCategory.self, forKey: .category)
        season = try c.decodeIfPresent(Season.self, forKey: .season)
        together = try c.decodeIfPresent(Bool.self, forKey: .together) ?? false
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays)
        dueDay = try c.decodeIfPresent(Int.self, forKey: .dueDay)
        rotation = try c.decodeIfPresent(ChoreRotation.self, forKey: .rotation)
        missPenalty = try c.decodeIfPresent(MissPenalty.self, forKey: .missPenalty)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(cadence, forKey: .cadence)
        try c.encodeIfPresent(fixedAssignee, forKey: .fixedAssignee)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(season, forKey: .season)
        try c.encode(together, forKey: .together)
        try c.encodeIfPresent(weekdays, forKey: .weekdays)
        try c.encodeIfPresent(dueDay, forKey: .dueDay)
        try c.encodeIfPresent(rotation, forKey: .rotation)
        try c.encodeIfPresent(missPenalty, forKey: .missPenalty)
    }

    public var isPinned: Bool {
        fixedAssignee != nil
    }

    public var hasWindow: Bool {
        !(weekdays ?? []).isEmpty || dueDay != nil
    }
}

/// A chore that was done. Mirrors the server's completion rows; soft-deleted rows are simply absent here.
public struct Completion: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let choreId: String
    public let person: Person
    public let completedAt: Date

    public init(id: String, choreId: String, person: Person, completedAt: Date) {
        self.id = id
        self.choreId = choreId
        self.person = person
        self.completedAt = completedAt
    }
}
