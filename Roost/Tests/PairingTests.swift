// D-4: the pairing state machine, the server endpoint, and the device name.
//
// The state machine gets a mock service, so "what does the screen do about a 429" is a test and not a thing
// somebody has to reproduce against a rate limiter. The HTTP half is in PairAPITests.swift.
@testable import Roost
import RoostCore
import SwiftData
import XCTest

// MARK: - the mock

@MainActor
final class MockPairingService: PairingService {
    /// Answers, in order. The last one repeats once the list runs out.
    var answers: [Result<Person, Error>] = [.success(.anne)]
    var unpairOutcome: UnpairOutcome = .unpaired
    private(set) var calls: [(code: String, deviceName: String)] = []
    private(set) var unpairCalls = 0

    func pair(code: String, deviceName: String) async throws -> Person {
        calls.append((code, deviceName))
        let answer = answers.count > 1 ? answers.removeFirst() : (answers.first ?? .success(.anne))
        return try answer.get()
    }

    func unpairDevice() async -> UnpairOutcome {
        unpairCalls += 1
        return unpairOutcome
    }
}

// MARK: - the state machine

@MainActor
final class PairingModelTests: XCTestCase {
    private var service: MockPairingService!

    override func setUpWithError() throws {
        service = MockPairingService()
    }

    private func model(deviceName: String = "Anne's iPhone") -> PairingModel {
        PairingModel(service: service, deviceName: deviceName)
    }

    func testSixthDigitSubmitsAndPairs() async {
        let m = model()
        for digit in "04821" {
            m.input(m.code + String(digit))
        }
        XCTAssertEqual(m.phase, .entering, "five digits do not submit")
        XCTAssertTrue(service.calls.isEmpty)

        m.input("048213")
        XCTAssertEqual(m.phase, .submitting, "the phase changes before the await, so a second tap cannot")
        await m.settle()

        XCTAssertEqual(m.phase, .paired(.anne))
        XCTAssertEqual(service.calls.count, 1)
        XCTAssertEqual(service.calls.first?.code, "048213")
        XCTAssertEqual(service.calls.first?.deviceName, "Anne's iPhone")
        XCTAssertNil(m.failure)
    }

    func testInvalidCodeClearsTheBoxesAndShakes() async {
        service.answers = [.failure(SyncAPIError.notFound)]
        let m = model()
        m.input("111111")
        await m.settle()

        XCTAssertEqual(m.phase, .entering)
        XCTAssertEqual(m.failure, .invalidCode)
        XCTAssertEqual(m.failure?.text, Strings.Onboarding.codeInvalid)
        XCTAssertEqual(m.code, "", "a dead code is not worth retrying as typed")
        XCTAssertEqual(m.rejectionCount, 1)
        XCTAssertFalse(m.canRetry)
    }

    func testRateLimitedKeepsTheCodeAndOffersARetry() async {
        service.answers = [.failure(SyncAPIError.rateLimited)]
        let m = model()
        m.input("048213")
        await m.settle()

        XCTAssertEqual(m.failure, .rateLimited)
        XCTAssertEqual(m.failure?.text, Strings.Onboarding.codeRateLimited)
        XCTAssertEqual(m.code, "048213")
        XCTAssertTrue(m.canRetry)
    }

    func testBadRequestReadsAsRejected() async {
        service.answers = [.failure(SyncAPIError.badRequest("code must be 6 digits"))]
        let m = model()
        m.input("048213")
        await m.settle()

        XCTAssertEqual(m.failure, .rejected)
        XCTAssertEqual(m.code, "")
    }

    func testTransportFailureKeepsTheCodeAndTheRetrySucceeds() async {
        service.answers = [.failure(SyncAPIError.transport("offline")), .success(.wes)]
        let m = model()
        m.input("048213")
        await m.settle()

        XCTAssertEqual(m.failure, .offline)
        XCTAssertEqual(m.failure?.text, Strings.Onboarding.codeOffline)
        XCTAssertEqual(m.code, "048213", "the code was probably fine; retyping it would be our fault")
        XCTAssertTrue(m.canRetry)

        m.submit()
        await m.settle()

        XCTAssertEqual(m.phase, .paired(.wes))
        XCTAssertNil(m.failure)
        XCTAssertEqual(service.calls.count, 2)
        XCTAssertEqual(service.calls.map(\.code), ["048213", "048213"])
    }

    func testPasteFillsEveryBoxAndSubmitsOnce() async {
        let m = model()
        m.input("  04 82 13 ")
        XCTAssertEqual(m.code, "048213")
        await m.settle()

        XCTAssertEqual(m.phase, .paired(.anne))
        XCTAssertEqual(service.calls.count, 1)
    }

    func testPasteIgnoresEverythingThatIsNotADigitAndStopsAtSix() async {
        let m = model()
        m.input("code: 048213 (expires soon)")
        await m.settle()
        XCTAssertEqual(m.code, "048213")
        XCTAssertEqual(service.calls.count, 1)
    }

    func testAShortPasteWaitsForTheRestOfTheCode() {
        let m = model()
        m.input("12345")
        XCTAssertEqual(m.code, "12345")
        XCTAssertEqual(m.phase, .entering)
        XCTAssertTrue(service.calls.isEmpty)
    }

    func testDeletingADigitClearsTheFailureAndDoesNotResubmit() async {
        service.answers = [.failure(SyncAPIError.rateLimited)]
        let m = model()
        m.input("048213")
        await m.settle()
        XCTAssertNotNil(m.failure)

        m.input("04821")
        XCTAssertNil(m.failure)
        XCTAssertEqual(m.code, "04821")
        XCTAssertEqual(service.calls.count, 1)
    }

    func testDigitsArrivingDuringAnAttemptAreIgnored() async {
        let m = model()
        m.input("048213")
        m.input("9")
        XCTAssertEqual(m.code, "048213")
        await m.settle()
        XCTAssertEqual(service.calls.count, 1)
    }

    func testUnpairReportsWhatTheServerSaid() async {
        let m = model()
        service.unpairOutcome = .unpaired
        var outcome = await m.unpair()
        XCTAssertEqual(outcome, .unpaired)
        XCTAssertNil(outcome.note, "a clean unpair has nothing to explain")

        service.unpairOutcome = .handMinted
        outcome = await m.unpair()
        XCTAssertEqual(outcome, .handMinted)
        XCTAssertEqual(outcome.note, Strings.Settings.unpairHandMinted)
        XCTAssertEqual(service.unpairCalls, 2)

        service.unpairOutcome = .localOnly("offline")
        outcome = await m.unpair()
        XCTAssertEqual(outcome.note, Strings.Settings.unpairOffline)
    }

    func testDeviceNameIsTrimmedToWhatTheServerAccepts() {
        XCTAssertEqual(DeviceName.trimmed("  Anne's iPhone \n"), "Anne's iPhone")
        XCTAssertEqual(DeviceName.trimmed(String(repeating: "x", count: 200)).count, DeviceName.maxLength)
        XCTAssertEqual(DeviceName.trimmed("   "), DeviceName.fallback, "an empty deviceName is a 400")
        XCTAssertFalse(DeviceName.current.isEmpty)
        XCTAssertLessThanOrEqual(DeviceName.current.count, DeviceName.maxLength)
    }

    func testEveryStatusCodeMapsToOneSentence() {
        XCTAssertEqual(PairingModel.failure(for: .notFound), .invalidCode)
        XCTAssertEqual(PairingModel.failure(for: .rateLimited), .rateLimited)
        XCTAssertEqual(PairingModel.failure(for: .badRequest("nope")), .rejected)
        XCTAssertEqual(PairingModel.failure(for: .transport("offline")), .offline)
        XCTAssertEqual(PairingModel.failure(for: .http(502)), .offline)
        XCTAssertEqual(PairingModel.failure(for: .decoding("junk")), .offline)
    }
}

// MARK: - the endpoint

final class ServerEndpointTests: XCTestCase {
    func testStoredURLWinsOverProductionAndJunkDoesNot() {
        XCTAssertEqual(ServerEndpoint.resolved(stored: nil), ServerEndpoint.production)
        XCTAssertEqual(
            ServerEndpoint.resolved(stored: "http://127.0.0.1:8790").absoluteString,
            "http://127.0.0.1:8790"
        )
        XCTAssertEqual(ServerEndpoint.resolved(stored: "127.0.0.1:8790"), ServerEndpoint.production)
        XCTAssertEqual(ServerEndpoint.resolved(stored: ""), ServerEndpoint.production)
    }

    func testDisplayKeepsThePortOnlyWhenThereIsOne() throws {
        XCTAssertEqual(ServerEndpoint.display(ServerEndpoint.production), "roost.hinescreative.xyz")
        XCTAssertEqual(
            try ServerEndpoint.display(XCTUnwrap(URL(string: "http://127.0.0.1:8790"))),
            "127.0.0.1:8790"
        )
    }
}
