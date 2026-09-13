@testable import Roost

// The header's "Synced …" line: four bands and the edges between them.
import XCTest

final class SyncStatusCopyTests: XCTestCase {
    /// A fixed clock, and a fixed zone so the last band's time reads the same everywhere.
    private let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:13:20 UTC

    private func line(secondsAgo: TimeInterval) -> String {
        SyncStatusCopy.synced(at: now.addingTimeInterval(-secondsAgo), now: now)
    }

    // MARK: band 1 — a moment

    func testAFreshPassReadsAsAMomentNotADuration() {
        // The bug this replaces: RelativeDateTimeFormatter answered "in 0 sec." here.
        XCTAssertEqual(line(secondsAgo: 0), "Synced just now")
        XCTAssertEqual(line(secondsAgo: 1), "Synced just now")
        XCTAssertEqual(line(secondsAgo: 4.9), "Synced just now")
    }

    func testAClockThatMovedBackwardsStillReadsAsAMoment() {
        XCTAssertEqual(line(secondsAgo: -30), "Synced just now")
    }

    // MARK: band 2 — seconds

    func testSecondsCountUpOnceThePassIsNoLongerAMoment() {
        XCTAssertEqual(line(secondsAgo: 5), "Synced 5 sec. ago")
        XCTAssertEqual(line(secondsAgo: 28), "Synced 28 sec. ago")
        XCTAssertEqual(line(secondsAgo: 59), "Synced 59 sec. ago")
    }

    // MARK: band 3 — minutes

    func testMinutesTakeOverAtOneMinuteAndTruncate() {
        XCTAssertEqual(line(secondsAgo: 60), "Synced 1 min. ago")
        XCTAssertEqual(line(secondsAgo: 119), "Synced 1 min. ago")
        XCTAssertEqual(line(secondsAgo: 120), "Synced 2 min. ago")
        XCTAssertEqual(line(secondsAgo: 59 * 60), "Synced 59 min. ago")
    }

    // MARK: band 4 — the clock

    func testAnHourOldPassGivesTheTimeItHappened() {
        let syncedAt = now.addingTimeInterval(-60 * 60)
        let expected = "Synced at " + syncedAt.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(SyncStatusCopy.synced(at: syncedAt, now: now), expected)
        // Not a count any more: whatever the locale's short time is, it is not "min. ago".
        XCTAssertFalse(SyncStatusCopy.synced(at: syncedAt, now: now).contains("ago"))
    }

    func testYesterdayStillGivesATimeRatherThanACount() {
        let syncedAt = now.addingTimeInterval(-26 * 60 * 60)
        let expected = "Synced at " + syncedAt.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(SyncStatusCopy.synced(at: syncedAt, now: now), expected)
    }

    // MARK: the whole ladder

    func testEveryBandIsReachedAndNoBandEverSaysIn() {
        let samples: [TimeInterval] = [0, 2, 4.999, 5, 30, 59.999, 60, 600, 3599, 3600, 86400]
        let lines = samples.map { line(secondsAgo: $0) }
        // The reported bug was the word "in", from the formatter's future phrasing.
        for line in lines {
            XCTAssertFalse(line.hasPrefix("Synced in "), "\(line) reads as a duration")
        }
        XCTAssertEqual(
            Set(lines.filter { $0 == "Synced just now" }).count, 1,
            "the moment band should be reached"
        )
        XCTAssertTrue(lines.contains { $0.hasSuffix("sec. ago") })
        XCTAssertTrue(lines.contains { $0.hasSuffix("min. ago") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("Synced at ") })
    }
}
