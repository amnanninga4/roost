// Bridges between the SwiftData records and RoostCore's value types.
import Foundation
import RoostCore

enum ConversionError: Error, CustomStringConvertible {
    case badCadence(String, id: String)
    case badCategory(String, id: String)
    case badPerson(String, id: String)

    var description: String {
        switch self {
        case .badCadence(let v, let id): return "chore \(id): unknown cadence '\(v)'"
        case .badCategory(let v, let id): return "chore \(id): unknown category '\(v)'"
        case .badPerson(let v, let id): return "record \(id): unknown person '\(v)'"
        }
    }
}

extension ChoreRecord {
    convenience init(_ chore: Chore, sortOrder: Int) {
        self.init(
            id: chore.id,
            title: chore.title,
            cadence: chore.cadence.rawValue,
            fixedAssignee: chore.fixedAssignee?.rawValue,
            category: chore.category.rawValue,
            sortOrder: sortOrder
        )
    }

    /// Copies every field from the value type except `sortOrder`, which the caller owns.
    func apply(_ chore: Chore, sortOrder: Int) {
        title = chore.title
        cadence = chore.cadence.rawValue
        fixedAssignee = chore.fixedAssignee?.rawValue
        category = chore.category.rawValue
        self.sortOrder = sortOrder
        retired = false
    }

    func toChore() throws -> Chore {
        guard let cadence = Cadence(rawValue: cadence) else { throw ConversionError.badCadence(cadence, id: id) }
        guard let category = ChoreCategory(rawValue: category) else { throw ConversionError.badCategory(category, id: id) }
        var person: Person? = nil
        if let raw = fixedAssignee {
            guard let p = Person(rawValue: raw) else { throw ConversionError.badPerson(raw, id: id) }
            person = p
        }
        return Chore(id: id, title: title, cadence: cadence, fixedAssignee: person, category: category)
    }
}

extension CompletionRecord {
    convenience init(_ completion: Completion, syncedAt: Date? = nil) {
        self.init(
            id: completion.id,
            choreId: completion.choreId,
            person: completion.person.rawValue,
            completedAt: completion.completedAt,
            syncedAt: syncedAt
        )
    }

    /// Nil when soft-deleted: RoostCore never sees deleted completions.
    func toCompletion() throws -> Completion? {
        guard !deleted else { return nil }
        guard let p = Person(rawValue: person) else { throw ConversionError.badPerson(person, id: id) }
        return Completion(id: id, choreId: choreId, person: p, completedAt: completedAt)
    }
}
