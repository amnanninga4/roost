import Foundation

/// The household. Mirrors `PEOPLE` in server/src/db.js and the `fixedAssignee` values in data/chores.json.
public enum Person: String, Codable, CaseIterable, Sendable, Hashable {
    case anne
    case wes
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

    public init(
        id: String,
        title: String,
        cadence: Cadence,
        fixedAssignee: Person? = nil,
        category: ChoreCategory,
        season: Season? = nil,
        together: Bool = false,
        weekdays: [Int]? = nil,
        dueDay: Int? = nil
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
    }

    enum CodingKeys: String, CodingKey {
        case id, title, cadence, fixedAssignee, category, season, together, weekdays, dueDay
    }

    /// Optional keys default when absent, so a version-1–3 file and every fixture keep decoding.
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
    }

    public var isPinned: Bool {
        fixedAssignee != nil
    }

    public var hasWindow: Bool { !(weekdays ?? []).isEmpty || dueDay != nil }
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
