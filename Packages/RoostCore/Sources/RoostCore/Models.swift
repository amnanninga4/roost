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

    public init(
        id: String,
        title: String,
        cadence: Cadence,
        fixedAssignee: Person? = nil,
        category: ChoreCategory,
        season: Season? = nil,
        together: Bool = false
    ) {
        self.id = id
        self.title = title
        self.cadence = cadence
        self.fixedAssignee = fixedAssignee
        self.category = category
        self.season = season
        self.together = together
    }

    enum CodingKeys: String, CodingKey {
        case id, title, cadence, fixedAssignee, category, season, together
    }

    /// The two optional keys default when absent, so a version-1 file and every fixture keep decoding.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        cadence = try c.decode(Cadence.self, forKey: .cadence)
        fixedAssignee = try c.decodeIfPresent(Person.self, forKey: .fixedAssignee)
        category = try c.decode(ChoreCategory.self, forKey: .category)
        season = try c.decodeIfPresent(Season.self, forKey: .season)
        together = try c.decodeIfPresent(Bool.self, forKey: .together) ?? false
    }

    public var isPinned: Bool {
        fixedAssignee != nil
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
