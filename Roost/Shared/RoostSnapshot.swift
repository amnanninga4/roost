// The one thing the app and the widget both know about: a small JSON file in the App Group container.
//
// This file is compiled into both targets (see `project.yml`: `Shared` is in the sources of `Roost` and of
// `RoostWidget`). It is deliberately dumb — no SwiftData, no RoostCore, no network. The app plans, encodes,
// and writes; the widget decodes and draws. Nothing else crosses the process boundary, which is why the
// widget can never be slow, can never be offline, and can never see the bearer token.
import Foundation

/// What the widget draws. Written after every plan the app makes; read on every timeline request.
///
/// Versioned, because the widget extension is a separate binary that iOS may keep running across an app
/// update: a snapshot from a newer app than the installed widget decodes or it doesn't, and `version` is
/// what lets the widget say "open Roost" instead of drawing nonsense.
struct RoostSnapshot: Codable, Equatable, Sendable {
    /// Bumped when a field changes meaning. A widget that reads a higher version shows its unavailable state.
    static let currentVersion = 1

    /// One person's day, already counted. The widget does no arithmetic beyond picking a plural.
    struct Person: Codable, Equatable, Sendable, Identifiable {
        /// `anne` / `wes` — the same raw value `RoostCore.Person` uses, so the widget can map it to a colour.
        let id: String
        /// "Anne" / "Wes", already resolved, so the widget never owns a name.
        let name: String
        /// Everything this person owes today, overdue included — the Tasks tab's "N DUE".
        let due: Int
        /// How many of those are past their day.
        let overdue: Int
        /// Days in a row with nothing left undone.
        let streak: Int
        /// The three loudest rows, in the order the Tasks tab draws them.
        let top: [Item]
    }

    /// How late a row is, as a name rather than a number, so the JSON stays readable and the widget's
    /// switch over it is exhaustive. Mirrors `RoostCore.EscalationStage`, which the widget cannot import.
    enum Stage: String, Codable, Equatable, Sendable, CaseIterable {
        case dueToday, nudge, pointed, alert

        /// An unrecognised stage from a newer app reads as `dueToday` rather than failing the whole
        /// snapshot: one row drawn calmly beats a blank widget.
        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Stage(rawValue: raw) ?? .dueToday
        }
    }

    /// One chore on the widget: its title and how late it is.
    struct Item: Codable, Equatable, Sendable, Identifiable {
        let title: String
        let stage: Stage
        /// 0 for a row that is merely due today.
        let daysOverdue: Int

        var id: String {
            "\(stage.rawValue):\(daysOverdue):\(title)"
        }
    }

    let version: Int
    /// When the app made this plan. The widget prints it as a relative time, and stale is visible rather
    /// than hidden: a phone that has not opened Roost in two days should say so.
    let generatedAt: Date
    /// The person this phone is paired as, or nil when it is not paired. The small and lock-screen families
    /// are about *you*, so without this they have nothing to show.
    let me: String?
    /// Both people, Anne first, always — the medium family is a comparison and a stable order is the point.
    let people: [Person]

    init(generatedAt: Date, me: String?, people: [Person], version: Int = RoostSnapshot.currentVersion) {
        self.version = version
        self.generatedAt = generatedAt
        self.me = me
        self.people = people
    }

    /// The paired person's own row, when there is one.
    var mine: Person? {
        guard let me else { return nil }
        return people.first { $0.id == me }
    }

    /// The other person's row. nil on an unpaired phone, where neither side is "the other".
    var theirs: Person? {
        guard let me else { return nil }
        return people.first { $0.id != me }
    }

    /// True when this phone has no pairing: the widget's "not paired yet" state.
    var isPaired: Bool {
        me != nil
    }

    /// True when the app that wrote this is newer than the widget reading it.
    var isReadable: Bool {
        version <= Self.currentVersion
    }
}

// MARK: - JSON

extension RoostSnapshot {
    /// ISO-8601 dates, so a snapshot on disk can be read by a human debugging the App Group container.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func encoded() throws -> Data {
        try Self.encoder().encode(self)
    }

    static func decoded(from data: Data) throws -> RoostSnapshot {
        try decoder().decode(RoostSnapshot.self, from: data)
    }
}
