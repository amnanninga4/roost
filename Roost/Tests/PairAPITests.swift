// D-4: the two /pair calls, and pairing and unpairing through SyncClient.
//
// The whole point of the typed errors is that a status code becomes exactly one of four sentences on the
// code screen, so every status the pairing routes can answer with is checked here against the real client.
@testable import Roost
import RoostCore
import SwiftData
import XCTest

// MARK: - the two /pair calls, through a real SyncAPI

final class PairAPITests: XCTestCase {
    private let base = URL(string: "https://stub.local")!

    private func api(token: String? = nil) -> SyncAPI {
        SyncAPI(baseURL: base, token: token, session: StubURLProtocol.makeSession())
    }

    func testPairPostsTheCodeAndTheDeviceNameWithNoBearer() async throws {
        StubURLProtocol.reset { _ in (200, json(["token": "tok-abc", "person": "anne"])) }
        let response = try await api().pair(code: "048213", deviceName: "Anne's iPhone")

        XCTAssertEqual(response.token, "tok-abc")
        XCTAssertEqual(response.person, "anne")
        let request = try XCTUnwrap(StubURLProtocol.requests("POST").first)
        XCTAssertEqual(request.path, "/pair")
        XCTAssertNil(request.authorization, "POST /pair is the one route with no bearer")
        XCTAssertEqual(request.body?["code"] as? String, "048213")
        XCTAssertEqual(request.body?["deviceName"] as? String, "Anne's iPhone")
    }

    func testPairStatusCodesBecomeTypedErrors() async {
        let cases: [(Int, SyncAPIError)] = [
            (404, .notFound),
            (429, .rateLimited),
            (400, .badRequest("code must be 6 digits and deviceName 1-60 chars")),
            (403, .forbidden),
            (500, .http(500)),
        ]
        for (status, expected) in cases {
            StubURLProtocol.reset { _ in (status, json(["error": "code must be 6 digits and deviceName 1-60 chars"])) }
            do {
                _ = try await api().pair(code: "048213", deviceName: "Anne's iPhone")
                XCTFail("expected \(status) to throw")
            } catch let error as SyncAPIError {
                XCTAssertEqual(error, expected, "status \(status)")
            } catch {
                XCTFail("unexpected error for \(status): \(error)")
            }
        }
    }

    func testAConnectionThatNeverAnswersIsTransport() async {
        StubURLProtocol.reset { _ in (StubURLProtocol.connectionLost, Data()) }
        do {
            _ = try await api().pair(code: "048213", deviceName: "Anne's iPhone")
            XCTFail("expected a transport error")
        } catch let error as SyncAPIError {
            XCTAssertEqual(PairingModel.failure(for: error), .offline)
            XCTAssertTrue(error.isTransient)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testUnpairSendsTheBearerAndReadsTheAnswer() async throws {
        StubURLProtocol.reset { _ in (200, json(["unpaired": true, "person": "anne", "label": "Anne iPhone · 15"])) }
        let response = try await api(token: "tok-abc").unpair()

        XCTAssertTrue(response.unpaired)
        XCTAssertEqual(response.label, "Anne iPhone · 15")
        let request = try XCTUnwrap(StubURLProtocol.requests("DELETE").first)
        XCTAssertEqual(request.path, "/pair/self")
        XCTAssertEqual(request.authorization, "Bearer tok-abc")
    }

    func testUnpairOf403IsForbiddenNotAGenericHTTPError() async {
        StubURLProtocol.reset { _ in (403, json(["error": "this device was set up by hand"])) }
        do {
            _ = try await api(token: "tok-file").unpair()
            XCTFail("expected 403 to throw")
        } catch let error as SyncAPIError {
            XCTAssertEqual(error, .forbidden)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

// MARK: - pairing and unpairing through SyncClient

final class PairByCodeTests: XCTestCase {
    private var container: ModelContainer!
    private var tokens: InMemoryTokenStore!
    private var client: SyncClient!
    private let base = URL(string: "https://stub.local")!

    override func setUp() async throws {
        container = try ModelContainer(
            for: RoostSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        tokens = InMemoryTokenStore()
        client = SyncClient(modelContainer: container)
        await client.configure(
            tokenStore: tokens,
            session: StubURLProtocol.makeSession(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    private func state() throws -> SyncState {
        try ChoreSeeder.syncState(in: ModelContext(container))
    }

    func testPairingByCodeStoresTheTokenTheServerMinted() async throws {
        StubURLProtocol.reset { _ in (200, json(["token": "tok-abc", "person": "wes"])) }
        let person = try await client.pair(baseURL: base, code: "048213", deviceName: "Wes iPhone")

        XCTAssertEqual(person, .wes)
        XCTAssertEqual(try tokens.read(), "tok-abc")
        XCTAssertEqual(try state().person, "wes")
        XCTAssertEqual(try state().baseURL, "https://stub.local")
    }

    func testAFailedPairingStoresNothing() async throws {
        StubURLProtocol.reset { _ in (404, json(["error": "invalid or expired code"])) }
        do {
            _ = try await client.pair(baseURL: base, code: "111111", deviceName: "Wes iPhone")
            XCTFail("expected 404")
        } catch let error as SyncAPIError {
            XCTAssertEqual(error, .notFound)
        }
        XCTAssertNil(try tokens.read())
        XCTAssertNil(try state().person)
    }

    func testUnpairingTellsTheServerThenForgetsTheToken() async throws {
        StubURLProtocol.reset { _ in (200, json(["token": "tok-abc", "person": "anne"])) }
        _ = try await client.pair(baseURL: base, code: "048213", deviceName: "Anne iPhone")

        StubURLProtocol.reset { _ in (200, json(["unpaired": true, "person": "anne", "label": "Anne iPhone"])) }
        let outcome = await client.unpairDevice()

        XCTAssertEqual(outcome, .unpaired)
        XCTAssertEqual(StubURLProtocol.requests("DELETE").first?.path, "/pair/self")
        XCTAssertNil(try tokens.read())
        XCTAssertNil(try state().person)
        XCTAssertNil(try state().baseURL)
        let outcomeAfter = await client.syncNow()
        XCTAssertEqual(outcomeAfter, .unpaired)
    }

    func testAHandMintedDeviceIsForgottenLocallyAndSaysWhy() async throws {
        StubURLProtocol.reset { _ in (200, json(["token": "tok-abc", "person": "anne"])) }
        _ = try await client.pair(baseURL: base, code: "048213", deviceName: "Anne iPhone")

        StubURLProtocol.reset { _ in (403, json(["error": "this device was set up by hand"])) }
        let outcome = await client.unpairDevice()

        XCTAssertEqual(outcome, .handMinted)
        XCTAssertEqual(outcome.note, Strings.Settings.unpairHandMinted)
        XCTAssertNil(try tokens.read(), "the server kept its copy; this phone does not have to")
        XCTAssertNil(try state().person)
    }

    func testAnUnreachableServerStillUnpairsThisPhone() async throws {
        StubURLProtocol.reset { _ in (200, json(["token": "tok-abc", "person": "anne"])) }
        _ = try await client.pair(baseURL: base, code: "048213", deviceName: "Anne iPhone")

        StubURLProtocol.reset { _ in (StubURLProtocol.connectionLost, Data()) }
        let outcome = await client.unpairDevice()

        XCTAssertEqual(outcome.note, Strings.Settings.unpairOffline)
        XCTAssertNil(try tokens.read())
    }

    func testUnpairingAPhoneThatWasNeverPairedSendsNothing() async {
        StubURLProtocol.reset { _ in (500, Data()) }
        let outcome = await client.unpairDevice()
        XCTAssertEqual(outcome, .notPaired)
        XCTAssertTrue(StubURLProtocol.requests("DELETE").isEmpty)
    }
}
