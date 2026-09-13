// D-5: the phone's side of remote notifications.
//
// Three things are worth pinning: the hex encoding the server validates, the idempotency rule that decides
// whether a token goes out at all, and what `PushService` actually does with the sequence iOS puts it
// through — the same token every foreground, a rotated token, and an unpair followed by a fresh pair.
@testable import Roost
import XCTest

// MARK: - fakes

/// Records the two calls and answers with whatever the test sets.
final class FakePushSender: PushSender, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var registered: [String] = []
    private(set) var unregistered: [String] = []
    var registerResult: PushSendResult = .sent
    var unregisterResult: PushSendResult = .sent

    func registerPushToken(_ token: String) async -> PushSendResult {
        lock.withLock { registered.append(token) }
        return lock.withLock { registerResult }
    }

    func unregisterPushToken(_ token: String) async -> PushSendResult {
        lock.withLock { unregistered.append(token) }
        return lock.withLock { unregisterResult }
    }
}

/// Counts how many times the service asked iOS for a token, and never touches UIKit.
@MainActor
final class FakeRemoteNotifications: RemoteNotificationRegistrar {
    private(set) var registerCalls = 0
    var authorized = true

    func registerForRemoteNotifications() {
        registerCalls += 1
    }

    func isAuthorized() async -> Bool {
        authorized
    }
}

// MARK: - the hex encoding

final class PushTokenTests: XCTestCase {
    func testHexIsLowercaseAndTwoCharactersPerByte() {
        XCTAssertEqual(PushToken.hex(Data([0x00, 0x0F, 0xAB, 0xFF])), "000fabff")
    }

    func testHexOfARealLengthTokenIs64Characters() {
        let token = PushToken.hex(Data(repeating: 0xC3, count: 32))
        XCTAssertEqual(token.count, 64)
        XCTAssertEqual(token, String(repeating: "c3", count: 32))
        XCTAssertTrue(PushToken.isWellFormed(token))
    }

    func testHexOfNothingIsEmptyAndNotWellFormed() {
        XCTAssertEqual(PushToken.hex(Data()), "")
        XCTAssertFalse(PushToken.isWellFormed(""))
    }

    func testWellFormedMeansExactly64LowercaseHexCharacters() {
        XCTAssertFalse(PushToken.isWellFormed(String(repeating: "a", count: 63)), "too short")
        XCTAssertFalse(PushToken.isWellFormed(String(repeating: "a", count: 65)), "too long")
        XCTAssertFalse(PushToken.isWellFormed(String(repeating: "A", count: 64)), "uppercase")
        XCTAssertFalse(PushToken.isWellFormed(String(repeating: "g", count: 64)), "not hex")
        XCTAssertTrue(PushToken.isWellFormed(String(repeating: "0", count: 64)))
    }
}

// MARK: - the idempotency rule

final class PushRegistrationTests: XCTestCase {
    private let token = String(repeating: "a", count: 64)
    private let other = String(repeating: "b", count: 64)

    func testAFirstTokenIsSent() {
        XCTAssertEqual(PushRegistration.decide(token: token, lastRegistered: nil), .send(token))
    }

    func testTheSameTokenAgainIsNotSent() {
        XCTAssertEqual(PushRegistration.decide(token: token, lastRegistered: token), .alreadyRegistered)
    }

    func testARotatedTokenIsSent() {
        XCTAssertEqual(PushRegistration.decide(token: other, lastRegistered: token), .send(other))
    }

    func testATokenTheServerWouldRefuseIsNeverSent() {
        XCTAssertEqual(PushRegistration.decide(token: "not-a-token", lastRegistered: nil), .malformed)
        XCTAssertEqual(PushRegistration.decide(token: "", lastRegistered: token), .malformed)
    }
}

// MARK: - the service

@MainActor
final class PushServiceTests: XCTestCase {
    private let token = String(repeating: "a", count: 64)
    private let rotated = String(repeating: "b", count: 64)

    /// The service with its three collaborators faked, all four handed back so a test can assert on any
    /// of them. Built inside rather than in default arguments, which are evaluated off the main actor.
    private struct Rig {
        let push: PushService
        let sender: FakePushSender
        let memory: InMemoryPushTokenMemory
        let registrar: FakeRemoteNotifications
    }

    private func makeRig(
        sender: FakePushSender? = nil,
        registrar: FakeRemoteNotifications? = nil
    ) -> Rig {
        let sender = sender ?? FakePushSender()
        let registrar = registrar ?? FakeRemoteNotifications()
        let memory = InMemoryPushTokenMemory()
        return Rig(
            push: PushService(sender: sender, memory: memory, registrar: registrar),
            sender: sender,
            memory: memory,
            registrar: registrar
        )
    }

    // MARK: registration

    func testTheFirstTokenIsPostedAndRemembered() async {
        let rig = makeRig()
        let decision = await rig.push.deviceTokenArrived(Data(repeating: 0xAA, count: 32))

        XCTAssertEqual(decision, .send(String(repeating: "aa", count: 32)))
        XCTAssertEqual(rig.sender.registered, [String(repeating: "aa", count: 32)])
        XCTAssertEqual(rig.memory.lastRegistered, String(repeating: "aa", count: 32))
        XCTAssertEqual(rig.push.registeredToken, String(repeating: "aa", count: 32))
    }

    /// iOS hands the same token over on every launch and every foreground. The server is an upsert, so this
    /// is about not making four pointless round trips a day on a home tunnel.
    func testTheSameTokenOnEveryForegroundIsSentOnce() async {
        let rig = makeRig()
        for _ in 0 ..< 4 {
            await rig.push.deviceTokenArrived(token)
        }
        XCTAssertEqual(rig.sender.registered, [token])
    }

    func testARotatedTokenIsSentAgain() async {
        let rig = makeRig()
        await rig.push.deviceTokenArrived(token)
        await rig.push.deviceTokenArrived(rotated)

        XCTAssertEqual(rig.sender.registered, [token, rotated])
        XCTAssertEqual(rig.memory.lastRegistered, rotated)
    }

    /// The whole reason the memory is cleared on unpair: the token iOS hands over after a fresh pair is the
    /// same one, and a server that dropped the row needs to be told about it again.
    func testUnpairThenPairRegistersTheSameTokenAgain() async {
        let rig = makeRig()
        await rig.push.deviceTokenArrived(token)
        await rig.push.unregisterBeforeUnpair()

        XCTAssertEqual(rig.sender.unregistered, [token])
        XCTAssertNil(rig.memory.lastRegistered, "the unpair has to forget it or the next pair looks registered")
        XCTAssertNil(rig.push.registeredToken)

        await rig.push.deviceTokenArrived(token)
        XCTAssertEqual(rig.sender.registered, [token, token])
    }

    func testAFailedRegistrationIsNotRememberedSoTheNextForegroundRetries() async {
        let sender = FakePushSender()
        sender.registerResult = .failed("Could not reach the server")
        let rig = makeRig(sender: sender)

        await rig.push.deviceTokenArrived(token)
        XCTAssertNil(rig.memory.lastRegistered)

        sender.registerResult = .sent
        await rig.push.deviceTokenArrived(token)
        XCTAssertEqual(rig.sender.registered, [token, token])
        XCTAssertEqual(rig.memory.lastRegistered, token)
    }

    /// An unpaired phone has no bearer, so there is nothing to tell. Not remembered either: the token goes
    /// out for real on the first foreground after pairing.
    func testAnUnpairedPhoneRemembersNothing() async {
        let sender = FakePushSender()
        sender.registerResult = .unpaired
        let rig = makeRig(sender: sender)

        await rig.push.deviceTokenArrived(token)
        XCTAssertEqual(rig.sender.registered, [token])
        XCTAssertNil(rig.memory.lastRegistered)
    }

    func testAMalformedTokenIsNeverSent() async {
        let rig = makeRig()
        let decision = await rig.push.deviceTokenArrived("nope")

        XCTAssertEqual(decision, .malformed)
        XCTAssertTrue(rig.sender.registered.isEmpty)
        XCTAssertNil(rig.memory.lastRegistered)
    }

    func testUnregisteringWithNothingRegisteredSendsNothing() async {
        let rig = makeRig()
        await rig.push.unregisterBeforeUnpair()
        XCTAssertTrue(rig.sender.unregistered.isEmpty)
    }

    /// A server that cannot be reached must not stop the unpair: the token is forgotten locally either way,
    /// the same rule `SyncClient.unpairDevice()` follows for the bearer.
    func testAFailedUnregisterStillForgetsTheTokenLocally() async {
        let sender = FakePushSender()
        sender.unregisterResult = .failed("Could not reach the server")
        let rig = makeRig(sender: sender)
        await rig.push.deviceTokenArrived(token)

        await rig.push.unregisterBeforeUnpair()
        XCTAssertNil(rig.memory.lastRegistered)
    }

    // MARK: asking iOS

    func testRegisteringOnlyHappensOncePermissionIsGiven() async {
        let registrar = FakeRemoteNotifications()
        registrar.authorized = false
        let rig = makeRig(registrar: registrar)

        await rig.push.registerIfAuthorized()
        XCTAssertEqual(registrar.registerCalls, 0, "a token with no permission can show nothing")

        registrar.authorized = true
        await rig.push.registerIfAuthorized()
        XCTAssertEqual(registrar.registerCalls, 1)
    }

    /// The onboarding step just got a yes out of the system prompt; asking the status again would be a
    /// round trip for an answer we already have.
    func testAGrantRegistersWithoutRecheckingTheStatus() {
        let registrar = FakeRemoteNotifications()
        registrar.authorized = false
        let rig = makeRig(registrar: registrar)

        rig.push.registerAfterGrant()
        XCTAssertEqual(registrar.registerCalls, 1)
    }

    // MARK: arriving pushes

    func testAForegroundPushKicksASyncAndDoesNotChangeTheTab() {
        let rig = makeRig()
        var syncs = 0
        rig.push.onPushArrived = { syncs += 1 }

        rig.push.pushArrivedInForeground()
        XCTAssertEqual(syncs, 1)
        XCTAssertEqual(rig.push.openTasksRequests, 0)
        XCTAssertNotNil(rig.push.lastPushAt)
    }

    /// A counter, not a flag: two taps in a row both have to land the reader back on Tasks even if they
    /// wandered off to Shopping in between.
    func testATappedPushSyncsAndAsksForTheTasksTabEveryTime() {
        let rig = makeRig()
        var syncs = 0
        rig.push.onPushArrived = { syncs += 1 }

        rig.push.pushTapped()
        rig.push.pushTapped()
        XCTAssertEqual(syncs, 2)
        XCTAssertEqual(rig.push.openTasksRequests, 2)
    }
}
