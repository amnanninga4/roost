// D-5: the two `/push/token` calls against a stub session, and through a real `SyncClient`.
//
// The shape matters more than it looks: `server/src/push.js` validates the platform and the 64-hex token,
// and it decides *which* device a token belongs to from the bearer — so a DELETE with no bearer silently
// does nothing, which is the bug this pins.
@testable import Roost
import RoostCore
import SwiftData
import XCTest

// MARK: - the API

final class PushAPITests: XCTestCase {
    private let base = URL(string: "https://stub.local")!
    private let token = String(repeating: "a", count: 64)

    private func api(bearer: String? = "tok-abc") -> SyncAPI {
        SyncAPI(baseURL: base, token: bearer, session: StubURLProtocol.makeSession())
    }

    func testRegisterPostsTheTokenAndPlatformWithTheBearer() async throws {
        StubURLProtocol.reset { _ in (201, json(["registered": true])) }
        try await api().registerPushToken(token)

        let request = try XCTUnwrap(StubURLProtocol.requests("POST").first)
        XCTAssertEqual(request.path, "/push/token")
        XCTAssertEqual(request.authorization, "Bearer tok-abc")
        XCTAssertEqual(request.body?["token"] as? String, token)
        XCTAssertEqual(request.body?["platform"] as? String, "ios")
    }

    /// 200 is an upsert of a token the server already had; 201 is a new row. Both are success, which is
    /// what makes a retry after a dead connection free.
    func testRegisterTakesBoth200And201() async throws {
        for status in [200, 201] {
            StubURLProtocol.reset { _ in (status, json(["registered": true])) }
            try await api().registerPushToken(token)
        }
    }

    func testUnregisterDeletesTheTokenWithTheBearer() async throws {
        StubURLProtocol.reset { _ in (200, json(["unregistered": true])) }
        try await api().unregisterPushToken(token)

        let request = try XCTUnwrap(StubURLProtocol.requests("DELETE").first)
        XCTAssertEqual(request.path, "/push/token")
        XCTAssertEqual(request.authorization, "Bearer tok-abc")
        XCTAssertEqual(request.body?["token"] as? String, token)
        XCTAssertNil(request.body?["platform"], "the DELETE body is the token alone")
    }

    func testStatusCodesBecomeTypedErrors() async {
        let cases: [(Int, SyncAPIError)] = [
            (400, .badRequest("token must be 64 hex characters")),
            (401, .unauthorized),
            (429, .rateLimited),
            (500, .http(500)),
        ]
        for (status, expected) in cases {
            StubURLProtocol.reset { _ in (status, json(["error": "token must be 64 hex characters"])) }
            do {
                try await api().registerPushToken(token)
                XCTFail("expected \(status) to throw")
            } catch let error as SyncAPIError {
                XCTAssertEqual(error, expected, "status \(status)")
            } catch {
                XCTFail("unexpected error for \(status): \(error)")
            }
        }
    }

    func testADeadConnectionIsTransport() async {
        StubURLProtocol.reset { _ in (StubURLProtocol.connectionLost, Data()) }
        do {
            try await api().registerPushToken(token)
            XCTFail("expected a transport error")
        } catch let error as SyncAPIError {
            XCTAssertTrue(error.isTransient)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

// MARK: - through the client

final class PushClientTests: XCTestCase {
    private var container: ModelContainer!
    private var tokens: InMemoryTokenStore!
    private var client: SyncClient!
    private let base = URL(string: "https://stub.local")!
    private let deviceToken = String(repeating: "a", count: 64)

    override func setUp() async throws {
        container = try ModelContainer(
            for: RoostSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        tokens = InMemoryTokenStore()
        client = SyncClient(modelContainer: container)
        await client.configure(tokenStore: tokens, session: StubURLProtocol.makeSession())
    }

    private func pairAsAnne() async throws {
        StubURLProtocol.reset { _ in (200, syncJSON(person: "anne", cursor: 1)) }
        _ = try await client.pair(baseURL: base, token: "anne-token-0123456789abcdef")
    }

    func testRegisterCarriesThePairedBearerToThePairedServer() async throws {
        try await pairAsAnne()
        StubURLProtocol.reset { _ in (201, json(["registered": true])) }

        let result = await client.registerPushToken(deviceToken)
        XCTAssertEqual(result, .sent)
        let request = try XCTUnwrap(StubURLProtocol.requests("POST").first)
        XCTAssertEqual(request.path, "/push/token")
        XCTAssertEqual(request.authorization, "Bearer anne-token-0123456789abcdef")
    }

    func testUnregisterCarriesTheSameBearer() async throws {
        try await pairAsAnne()
        StubURLProtocol.reset { _ in (200, json(["unregistered": true])) }

        let result = await client.unregisterPushToken(deviceToken)
        XCTAssertEqual(result, .sent)
        let request = try XCTUnwrap(StubURLProtocol.requests("DELETE").first)
        XCTAssertEqual(request.path, "/push/token")
        XCTAssertEqual(request.authorization, "Bearer anne-token-0123456789abcdef")
    }

    /// Not a failure and not a request: a phone with no token has nothing to register and no server to
    /// register it with.
    func testAnUnpairedPhoneSendsNothing() async {
        StubURLProtocol.reset { _ in (201, json(["registered": true])) }
        let registered = await client.registerPushToken(deviceToken)
        let unregistered = await client.unregisterPushToken(deviceToken)
        XCTAssertEqual(registered, .unpaired)
        XCTAssertEqual(unregistered, .unpaired)
        XCTAssertTrue(StubURLProtocol.requests("POST").isEmpty)
        XCTAssertTrue(StubURLProtocol.requests("DELETE").isEmpty)
    }

    func testAFailureComesBackAsTheServersOwnWords() async throws {
        try await pairAsAnne()
        StubURLProtocol.reset { _ in (400, json(["error": "token must be 64 hex characters"])) }

        let result = await client.registerPushToken("short")
        XCTAssertEqual(result, .failed("Rejected by the server: token must be 64 hex characters"))
    }
}
