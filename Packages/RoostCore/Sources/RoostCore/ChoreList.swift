import Foundation

/// The decoded shape of data/chores.json.
public struct ChoreList: Codable, Sendable {
    public let version: Int
    public let source: String?
    public let locked: String?
    public let notes: String?
    public let chores: [Chore]

    public init(version: Int, source: String? = nil, locked: String? = nil, notes: String? = nil, chores: [Chore]) {
        self.version = version
        self.source = source
        self.locked = locked
        self.notes = notes
        self.chores = chores
    }

    public static func load(from url: URL) throws -> ChoreList {
        try JSONDecoder().decode(ChoreList.self, from: Data(contentsOf: url))
    }

    public static func load(json data: Data) throws -> ChoreList {
        try JSONDecoder().decode(ChoreList.self, from: data)
    }

    public var pinned: [Chore] { chores.filter(\.isPinned) }

    public subscript(id: String) -> Chore? { chores.first { $0.id == id } }
}
