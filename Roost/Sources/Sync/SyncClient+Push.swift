// The push half of the sync client: the base URL and the bearer live here, so this is where the two
// `/push/token` calls are made from.
//
// Neither call is part of a sync pass. A failure is not queued and not retried on a timer: the next launch
// or foreground hands the same token over again and `PushRegistration` will still say "send", because
// nothing was ever acknowledged. That is the retry, and it costs nothing.
import Foundation

/// What went out, in the three flavours the caller cares about.
enum PushSendResult: Equatable, Sendable {
    /// The server took it.
    case sent
    /// This phone is not paired, so there is no bearer and no server to tell. Not a failure.
    case unpaired
    /// The call was made and did not succeed. The description is the server's or the system's words.
    case failed(String)

    var didSend: Bool {
        self == .sent
    }
}

/// The slice of the client the push service needs, so `PushService` can be tested against a fake.
protocol PushSender: Sendable {
    func registerPushToken(_ token: String) async -> PushSendResult
    func unregisterPushToken(_ token: String) async -> PushSendResult
}

extension SyncClient: PushSender {
    /// `POST /push/token`. Idempotent server-side (it is an upsert), so a retry is free.
    func registerPushToken(_ token: String) async -> PushSendResult {
        await callPush(token) { api, token in try await api.registerPushToken(token) }
    }

    /// `DELETE /push/token`. Best effort: on unpair the local token is cleared whatever this answers, the
    /// same rule `unpairDevice()` already follows.
    func unregisterPushToken(_ token: String) async -> PushSendResult {
        await callPush(token) { api, token in try await api.unregisterPushToken(token) }
    }

    private func callPush(
        _ token: String,
        _ call: (SyncAPI, String) async throws -> Void
    ) async -> PushSendResult {
        do {
            guard let api = try pushAPI() else { return .unpaired }
            try await call(api, token)
            return .sent
        } catch let e as SyncAPIError {
            return .failed(e.description)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// A client aimed at the paired server with the paired bearer, or nil when this phone has neither.
    private func pushAPI() throws -> SyncAPI? {
        let state = try ChoreSeeder.syncState(in: modelContext)
        guard let base = state.baseURL.flatMap(URL.init(string:)), let token = try tokenStore.read() else {
            return nil
        }
        return SyncAPI(baseURL: base, token: token, session: session)
    }
}
