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
}

public enum ChoreCategory: String, Codable, CaseIterable, Sendable, Hashable {
    case chore
    case catCare = "cat_care"
}

/// One row of data/chores.json.
public struct Chore: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let cadence: Cadence
    public let fixedAssignee: Person?
    public let category: ChoreCategory

    public init(id: String, title: String, cadence: Cadence, fixedAssignee: Person? = nil, category: ChoreCategory) {
        self.id = id
        self.title = title
        self.cadence = cadence
        self.fixedAssignee = fixedAssignee
        self.category = category
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
