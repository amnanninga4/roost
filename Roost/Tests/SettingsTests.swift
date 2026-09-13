// D-4b: the Settings model, and `GET /me` through a real SyncAPI.
//
// The model decides which of three things the device row says — the server's label, this phone's own name,
// or a pairing date that may not exist — so it gets a mock and no server. The HTTP half is a stub session:
// the bearer, the path, and how the JSON becomes a `DeviceIdentity`.
@testable import Roost
import RoostCore
import XCTest

// MARK: - the mock

@MainActor
final class MockIdentityService: IdentityService {
    var answer: Result<DeviceIdentity?, Error> = .success(nil)
    private(set) var calls = 0
    /// While true, `identity()` parks until `release()`, so a test can hold one call open and prove the
    /// second `refresh()` joins it instead of asking again.
    var holdsCalls = false
    private var parked: [CheckedContinuation<Void, Never>] = []

    func identity() async throws -> DeviceIdentity? {
        calls += 1
        if holdsCalls {
            await withCheckedContinuation { parked.append($0) }
        }
        return try answer.get()
    }

    func release() {
        let waiting = parked
        parked = []
        for continuation in waiting {
            continuation.resume()
        }
    }
}

// MARK: - the model

@MainActor
final class SettingsModelTests: XCTestCase {
    private var service: MockIdentityService!
    /// 2026-09-13, so the formatted date is stable whatever the calendar does around it.
    private let pairedAt = Date(timeIntervalSince1970: 1_789_000_000)

    override func setUpWithError() throws {
        service = MockIdentityService()
    }

    private func model(localName: String = "iPhone 17 Pro") -> SettingsModel {
        SettingsModel(service: service, localName: localName)
    }

    private func identity(
        person: Person? = .anne,
        label: String? = "Anne test · iPhone 17 Pro",
        handMinted: Bool = false,
        pairedAt: Date? = nil
    ) -> DeviceIdentity {
        DeviceIdentity(
            person: person,
            label: label,
            isHandMinted: handMinted,
            pairedAt: pairedAt ?? self.pairedAt,
            lastSeen: nil
        )
    }

    func testTheServersLabelReplacesThePhonesOwnName() async {
        service.answer = .success(identity())
        let m = model()
        XCTAssertEqual(m.deviceLine, "iPhone 17 Pro", "before the call, the phone only knows itself")
        XCTAssertTrue(m.isLocalOnly)

        await m.refresh()

        XCTAssertEqual(m.deviceLine, "Anne test · iPhone 17 Pro")
        XCTAssertFalse(m.isLocalOnly)
        XCTAssertFalse(m.didFail)
        XCTAssertFalse(m.isLoading)
    }

    func testAFailedCallLeavesThePhonesOwnName() async {
        service.answer = .failure(SyncAPIError.transport("offline"))
        let m = model(localName: "Wes's iPhone")

        await m.refresh()

        XCTAssertEqual(m.deviceLine, "Wes's iPhone", "a server that cannot be reached does not blank the row")
        XCTAssertTrue(m.isLocalOnly)
        XCTAssertTrue(m.didFail)
        XCTAssertNil(m.pairedSince, "no date is better than a wrong one")
    }

    func testASuccessfulCallAfterAFailureClearsIt() async {
        service.answer = .failure(SyncAPIError.transport("offline"))
        let m = model()
        await m.refresh()
        XCTAssertTrue(m.didFail)

        service.answer = .success(identity())
        await m.refresh()

        XCTAssertFalse(m.didFail)
        XCTAssertEqual(m.deviceLine, "Anne test · iPhone 17 Pro")
        XCTAssertEqual(service.calls, 2, "a second refresh really asks again")
    }

    func testAnUnpairedPhoneIsNotAFailure() async {
        service.answer = .success(nil)
        let m = model()

        await m.refresh()

        XCTAssertFalse(m.didFail, "there is nothing stored to ask with; that is not an error")
        XCTAssertEqual(m.deviceLine, "iPhone 17 Pro")
        XCTAssertNil(m.pairedSince)
        XCTAssertNil(m.person)
    }

    func testPairedSinceIsTheDateTheServerGave() async {
        service.answer = .success(identity())
        let m = model()

        await m.refresh()

        XCTAssertEqual(m.pairedSince, pairedAt.formatted(date: .abbreviated, time: .omitted))
    }

    func testAHandMintedDeviceSaysSoInsteadOfShowingADate() async {
        service.answer = .success(identity(label: "Wes laptop", handMinted: true))
        let m = model()

        await m.refresh()

        XCTAssertEqual(m.pairedSince, Strings.Settings.pairedHandMinted)
        XCTAssertEqual(m.deviceLine, "Wes laptop")
    }

    func testAPairedDeviceWithNoDateShowsNoRow() async {
        service.answer = .success(DeviceIdentity(
            person: .wes,
            label: "Wes test · iPhone",
            isHandMinted: false,
            pairedAt: nil,
            lastSeen: nil
        ))
        let m = model()

        await m.refresh()

        XCTAssertNil(m.pairedSince)
        XCTAssertEqual(m.person, .wes, "the person still comes through")
    }

    func testThePersonComesFromTheServerNotFromPairing() async {
        service.answer = .success(identity(person: .wes))
        let m = model()

        await m.refresh()

        XCTAssertEqual(m.person, .wes)
    }

    func testASecondRefreshJoinsTheCallInFlight() async {
        service.holdsCalls = true
        service.answer = .success(identity())
        let m = model()

        let first = Task { await m.refresh() }
        while service.calls == 0 {
            await Task.yield()
        }
        async let joined: Void = m.refresh()
        for _ in 0 ..< 8 {
            await Task.yield()
        }
        service.release()
        await first.value
        await joined

        XCTAssertEqual(service.calls, 1, "appearing twice in a moment is one request")
        XCTAssertEqual(m.deviceLine, "Anne test · iPhone 17 Pro")
    }
}

// MARK: - GET /me through a real SyncAPI

final class MeAPITests: XCTestCase {
    private let base = URL(string: "https://stub.local")!

    private func api(token: String? = "tok-abc") -> SyncAPI {
        SyncAPI(baseURL: base, token: token, session: StubURLProtocol.makeSession())
    }

    func testMeSendsTheBearerAndBecomesAnIdentity() async throws {
        StubURLProtocol.reset { _ in
            (200, json([
                "person": "anne",
                "label": "Anne test · iPhone 17 Pro",
                "source": "paired",
                "createdAt": "2026-09-13T05:20:00.000Z",
                "lastSeen": "2026-09-13T06:00:00.000Z",
            ]))
        }
        let identity = try await DeviceIdentity(api().me())

        XCTAssertEqual(identity.person, .anne)
        XCTAssertEqual(identity.label, "Anne test · iPhone 17 Pro")
        XCTAssertFalse(identity.isHandMinted)
        XCTAssertEqual(identity.pairedAt, SyncAPI.parseDate("2026-09-13T05:20:00.000Z"))
        XCTAssertEqual(identity.lastSeen, SyncAPI.parseDate("2026-09-13T06:00:00.000Z"))

        let request = try XCTUnwrap(StubURLProtocol.requests("GET").first)
        XCTAssertEqual(request.path, "/me")
        XCTAssertEqual(request.authorization, "Bearer tok-abc")
    }

    func testAFileTokenHasNoPairingDate() async throws {
        StubURLProtocol.reset { _ in
            (200, json([
                "person": "wes",
                "label": "Wes laptop",
                "source": "file",
                "createdAt": NSNull(),
                "lastSeen": NSNull(),
            ]))
        }
        let identity = try await DeviceIdentity(api().me())

        XCTAssertTrue(identity.isHandMinted, "only the tokens file can revoke this one")
        XCTAssertNil(identity.pairedAt)
        XCTAssertNil(identity.lastSeen)
        XCTAssertEqual(identity.person, .wes)
    }

    func testALabelTheServerLeftEmptyReadsAsNoLabel() async throws {
        StubURLProtocol.reset { _ in
            (200, json([
                "person": "anne",
                "label": "   ",
                "source": "paired",
                "createdAt": "2026-09-13T05:20:00.000Z",
                "lastSeen": NSNull(),
            ]))
        }
        let identity = try await DeviceIdentity(api().me())

        XCTAssertNil(identity.label, "whitespace is not a device name; Settings falls back to the phone's own")
    }

    func testADeadTokenIsUnauthorizedNotAGenericHTTPError() async {
        StubURLProtocol.reset { _ in (401, json(["error": "unauthorized"])) }
        do {
            _ = try await api(token: "tok-revoked").me()
            XCTFail("expected 401 to throw")
        } catch let error as SyncAPIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
