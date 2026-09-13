@testable import RoostCore
import XCTest

/// The streak walks back over past days, so it has to honour the handoffs that were accepted for those days —
/// the same three-layer answer `Scheduler.assignee(for:periodIndex:on:handoffs:)` gives, judged against the day
/// being walked rather than against today. Without it the phone and the status board disagree the first time one
/// of them hands a daily to the other and it gets done.
final class StreakHandoffTests: XCTestCase {
    let cal = HouseholdCalendar()
    /// One pinned daily each, so a day is only complete when that person's own chore is done, plus one unpinned
    /// daily the rotation always hands to Anne. The unpinned one is what gets offered to Wes.
    let anneDaily = Chore(
        id: "am-wet-cat-food",
        title: "AM wet cat food",
        cadence: .daily,
        fixedAssignee: .anne,
        category: .catCare
    )
    let wesDaily = Chore(
        id: "pm-wet-cat-food",
        title: "PM wet cat food",
        cadence: .daily,
        fixedAssignee: .wes,
        category: .catCare
    )
    let litter = Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, category: .catCare)

    // The household starts Monday 2026-09-14, so the walk floors at Monday and every streak here is short
    // enough to check by hand. Tuesday the 15th is the day that gets handed off.
    lazy var activeFrom = cal.date(year: 2026, month: 9, day: 14, hour: 0)
    lazy var wed = cal.date(year: 2026, month: 9, day: 16, hour: 9)
    lazy var thu = cal.date(year: 2026, month: 9, day: 17, hour: 9)
    lazy var tueIndex = cal.periodIndex(.daily, containing: cal.date(year: 2026, month: 9, day: 15))
    lazy var scheduler = Scheduler(
        chores: [anneDaily, wesDaily, litter],
        activeFrom: activeFrom,
        rotation: FixedRotation(person: .anne),
        calendar: cal
    )
    lazy var tallies = Tallies(scheduler: scheduler)

    /// Monday everything got done. Tuesday each of them did their own pinned daily; the litter is the variable.
    lazy var throughTuesday = [
        c(anneDaily, .anne, day: 14),
        c(wesDaily, .wes, day: 14),
        c(litter, .anne, day: 14),
        c(anneDaily, .anne, day: 15),
        c(wesDaily, .wes, day: 15),
    ]

    func c(_ chore: Chore, _ person: Person, day: Int, hour: Int = 12) -> Completion {
        Completion(
            id: "\(chore.id)-\(day)-\(hour)",
            choreId: chore.id,
            person: person,
            completedAt: cal.date(year: 2026, month: 9, day: day, hour: hour)
        )
    }

    /// Anne offering Tuesday's litter to Wes, in whatever state the test needs.
    func offer(_ state: Handoff.State, day: Int = 15) -> Handoff {
        Handoff(
            id: "h1",
            choreId: litter.id,
            from: .anne,
            to: .wes,
            periodIndex: cal.periodIndex(.daily, containing: cal.date(year: 2026, month: 9, day: day)),
            cadence: .daily,
            createdAt: cal.date(year: 2026, month: 9, day: day, hour: 8),
            state: state
        )
    }

    func testHandedOffDailyMovesThatDayToTheReceiver() {
        let accepted = offer(.accepted)
        let wesScooped = throughTuesday + [c(litter, .wes, day: 15, hour: 19)]

        // Wednesday morning, nothing done yet — an unfinished today never breaks a streak, so both walks start
        // at Tuesday and reach Monday. Anne's streak survives the day she gave away, and the litter Wes did is
        // what makes his Tuesday complete.
        XCTAssertEqual(tallies.streak(for: .anne, asOf: wed, completions: wesScooped, handoffs: [accepted]), 2)
        XCTAssertEqual(tallies.streak(for: .wes, asOf: wed, completions: wesScooped, handoffs: [accepted]), 2)

        // The same Tuesday with nobody scooping: it was his, so his day breaks and hers does not — the exact
        // opposite of the answer the walk gives when it ignores handoffs.
        XCTAssertEqual(tallies.streak(for: .anne, asOf: wed, completions: throughTuesday, handoffs: [accepted]), 2)
        XCTAssertEqual(tallies.streak(for: .wes, asOf: wed, completions: throughTuesday, handoffs: [accepted]), 0)
        XCTAssertEqual(
            tallies.streak(for: .anne, asOf: wed, completions: throughTuesday),
            0,
            "with no handoffs Tuesday's litter is still hers, and undone"
        )
        XCTAssertEqual(tallies.streak(for: .wes, asOf: wed, completions: throughTuesday), 2)
    }

    func testUnacceptedHandoffChangesNothing() {
        // Nobody scooped on Tuesday, so the walk is sensitive to who owed it: Anne's day breaks, Wes's does not.
        let baseAnne = tallies.streak(for: .anne, asOf: wed, completions: throughTuesday)
        let baseWes = tallies.streak(for: .wes, asOf: wed, completions: throughTuesday)
        XCTAssertEqual(baseAnne, 0)
        XCTAssertEqual(baseWes, 2)

        for state in [Handoff.State.pending, .declined, .expired] {
            let handoffs = [offer(state)]
            XCTAssertEqual(
                tallies.streak(for: .anne, asOf: wed, completions: throughTuesday, handoffs: handoffs),
                baseAnne,
                "\(state.rawValue) is not an override"
            )
            XCTAssertEqual(
                tallies.streak(for: .wes, asOf: wed, completions: throughTuesday, handoffs: handoffs),
                baseWes,
                "\(state.rawValue) is not an override"
            )
        }
    }

    func testAcceptedHandoffForAPastDayStillAppliesThen() {
        // Anne gave Tuesday's litter away and Wes never scooped it. Wednesday both of them were caught up.
        let completions = throughTuesday + [
            c(anneDaily, .anne, day: 16),
            c(wesDaily, .wes, day: 16),
            c(litter, .anne, day: 16),
        ]
        let accepted = offer(.accepted)

        // By Thursday the offer is over, and asked from Thursday the scheduler says Tuesday's litter is Anne's.
        XCTAssertTrue(accepted.hasExpired(on: thu, calendar: cal))
        XCTAssertEqual(HandoffRules.effectiveState(accepted, on: thu, calendar: cal), .expired)
        XCTAssertEqual(
            scheduler.assignee(for: litter, periodIndex: tueIndex, on: thu, handoffs: [accepted]),
            .anne,
            "asked from Thursday, the expired offer is not an override"
        )

        // The streak asks about Tuesday as Tuesday, so the offer still stands there: Mon, Tue (not hers), Wed.
        XCTAssertEqual(tallies.streak(for: .anne, asOf: thu, completions: completions, handoffs: [accepted]), 3)
        XCTAssertEqual(
            tallies.streak(for: .anne, asOf: thu, completions: completions),
            1,
            "judged against today instead, the litter she gave away would break Tuesday"
        )
        XCTAssertEqual(
            tallies.streak(for: .wes, asOf: thu, completions: completions, handoffs: [accepted]),
            1,
            "Tuesday's litter was his and he never did it"
        )
    }
}
