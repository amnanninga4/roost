// Bridges between the SwiftData records and RoostCore's value types.
import Foundation
import RoostCore

enum ConversionError: Error, CustomStringConvertible {
    case badCadence(String, id: String)
    case badCategory(String, id: String)
    case badPerson(String, id: String)
    case badState(String, id: String)

    var description: String {
        switch self {
        case let .badCadence(v, id): "chore \(id): unknown cadence '\(v)'"
        case let .badCategory(v, id): "chore \(id): unknown category '\(v)'"
        case let .badPerson(v, id): "record \(id): unknown person '\(v)'"
        case let .badState(v, id): "handoff \(id): unknown state '\(v)'"
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
        guard let category = ChoreCategory(rawValue: category)
        else { throw ConversionError.badCategory(category, id: id) }
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
        guard !removed else { return nil }
        guard let p = Person(rawValue: person) else { throw ConversionError.badPerson(person, id: id) }
        return Completion(id: id, choreId: choreId, person: p, completedAt: completedAt)
    }
}

extension HandoffRecord {
    /// Nil when soft-deleted, the same rule completions follow: RoostCore never sees a deleted row.
    func toHandoff() throws -> Handoff? {
        guard !removed else { return nil }
        guard let from = Person(rawValue: fromPerson) else { throw ConversionError.badPerson(fromPerson, id: id) }
        guard let to = Person(rawValue: toPerson) else { throw ConversionError.badPerson(toPerson, id: id) }
        guard let cad = Cadence(rawValue: cadence) else { throw ConversionError.badCadence(cadence, id: id) }
        guard let handoffState = Handoff.State(rawValue: state) else {
            throw ConversionError.badState(state, id: id)
        }
        return Handoff(
            id: id,
            choreId: choreId,
            from: from,
            to: to,
            periodIndex: periodIndex,
            cadence: cad,
            createdAt: createdAt,
            state: handoffState
        )
    }

    /// The planner's input: the value type plus the three facts that live only on the phone.
    func toSnapshot() throws -> HandoffSnapshot? {
        guard let handoff = try toHandoff() else { return nil }
        return HandoffSnapshot(
            handoff: handoff,
            reachedServer: reachedServer,
            refused: rejected,
            noticeCleared: noticeCleared
        )
    }
}
