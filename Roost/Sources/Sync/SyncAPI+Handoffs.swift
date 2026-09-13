// The /handoffs endpoints of server/ (see server/README.md "Endpoints" and server/src/handoffs.js).
// Same rules as the list calls: typed, no retries, no storage, `SyncAPIError` on anything but 2xx.
// HandoffSync.swift decides what to do with the outcome.
import Foundation
import RoostCore

extension SyncAPI {
    /// A handoff row as `/sync` and the three `/handoffs` routes shape it.
    struct HandoffDTO: Codable, Sendable, Equatable {
        let id: String
        let choreId: String
        let from: String
        let to: String
        let periodIndex: Int
        let cadence: String
        /// `pending` / `accepted` / `declined` / `expired`.
        let state: String
        let createdAt: String
        let updatedAt: String
        let deleted: Bool
        let seq: Int
    }

    /// A `409` from accept or decline: the offer was answered by someone else, or its period ended.
    ///
    /// It carries the server's own copy of the row, which is the only way the phone hears about it: a
    /// `not_pending` conflict changes nothing on the server, so it takes no new `seq` and `/sync` — a
    /// delta on `seq` — would never send it again.
    struct HandoffConflict: Error, Sendable, Equatable {
        let handoff: HandoffDTO?
        let message: String
    }

    private struct HandoffBody: Encodable {
        let id: String
        let choreId: String
        let to: String
        let periodIndex: Int
        let cadence: String
    }

    private struct ConflictBody: Decodable {
        let error: String
        let handoff: HandoffDTO?
    }

    /// `POST /handoffs` — offer a turn away. `from` comes from the token.
    ///
    /// `201` new, `200` replay of an id the server already has; both are success and both return the
    /// stored row. `400` for bad input or a future period, `403` when the caller is not the current
    /// owner, `409` when an open offer already exists for that chore and period — none of which change
    /// on a retry, which is why HandoffSync treats all three as final. The 409 arrives as the ordinary
    /// `SyncAPIError.http(409)`: the row it collides with is a different handoff, so there is nothing in
    /// that body worth carrying, unlike the accept/decline conflict below.
    ///
    /// `periodIndex` and `cadence` ride the body even though the server can work both out: an offer made
    /// offline is replayed later, possibly in the next period, and the phone means the period it was
    /// looking at. The server rejects a future one and takes a past one.
    func postHandoff(
        id: String,
        choreId: String,
        to: Person,
        periodIndex: Int,
        cadence: Cadence
    ) async throws -> Posted<HandoffDTO> {
        let body = HandoffBody(
            id: id, choreId: choreId, to: to.rawValue, periodIndex: periodIndex, cadence: cadence.rawValue
        )
        let (data, status) = try await send(
            method: "POST", url: baseURL.appending(path: "handoffs"), body: JSONEncoder().encode(body)
        )
        try Self.check(status, data)
        return try Posted(row: Self.decode(HandoffDTO.self, data), isNew: status == 201)
    }

    /// `POST /handoffs/:id/accept` or `/decline` — answer an offer. Only the offer's `to` may call it:
    /// anyone else is a `403`. `409` (already answered, or the period ended) throws `HandoffConflict`
    /// carrying the server's row, so the phone can take its own optimistic answer back.
    func answerHandoff(id: String, _ decision: HandoffRules.Decision) async throws -> HandoffDTO {
        let path = "handoffs/\(id)/\(decision == .accept ? "accept" : "decline")"
        let (data, status) = try await send(method: "POST", url: baseURL.appending(path: path), body: nil)
        if status == 409 {
            throw Self.conflict(data)
        }
        try Self.check(status, data)
        return try Self.decode(HandoffDTO.self, data)
    }

    private static func conflict(_ data: Data) -> HandoffConflict {
        let body = try? JSONDecoder().decode(ConflictBody.self, from: data)
        return HandoffConflict(handoff: body?.handoff, message: body?.error ?? "handoff conflict")
    }
}
