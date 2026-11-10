import XCTest
@testable import KCNA26Core

/// Port of reminders/GoingReminderPlannerTest.kt: the reminder planner with starred ("Going")
/// sessions mixed in with my own talks.
final class GoingReminderPlannerTests: XCTestCase {

    private let repo = TestData.repo
    private let lucy = "Lucy Sweet"

    private let rb220 = "1251049" // "In-Place Pod Resizing Like I'm 5…", Regency Ballroom B (Hyatt L4), Wed 2:20 PM
    private let rb500 = "1251218" // "Feeling Lost? A Newcomer's Guide to the Gateway API", Regency Ballroom B, Wed 5:00 PM
    private let off = "1344383" // Agent Rush Hackathon, Off-site, Sun 9:00 AM

    private func at(_ iso: String) -> Date { TestData.instant(iso) }

    private func plan(_ me: String?, _ now: String, _ going: Set<String>, _ minutes: Int = 10) -> [PlannedReminder] {
        ReminderPlanner.plan(repo.sessions, repo.rooms, me, at(now), going, minutes)
    }

    /// Kotlin `single()`: the only element; throws (failing the test) otherwise.
    private func single(_ xs: [PlannedReminder], file: StaticString = #filePath, line: UInt = #line) throws -> PlannedReminder {
        try XCTUnwrap(xs.count == 1 ? xs[0] : nil, "single: \(xs.count) elements", file: file, line: line)
    }

    func testAStarredSessionGetsOneReminderWithTheGoingText() throws {
        let r = try single(plan(nil, "2026-11-10T12:00", [rb220]))
        XCTAssertEqual(rb220, r.sessionId)
        XCTAssertEqual(ReminderKind.going, r.kind)
        XCTAssertEqual(10, r.minutesBefore)
        XCTAssertEqual(at("2026-11-11T14:10"), r.triggerAt)
        XCTAssertEqual(repo.session(rb220)!.title, r.title)
        XCTAssertEqual("Starting in 10 min · Regency Ballroom B, Level 4", r.text)
        XCTAssertEqual("\(rb220)/10", r.key)
    }

    func testTheLeadTimeFollowsTheSetting() throws {
        for m in [5, 10, 15] {
            let r = try single(plan(nil, "2026-11-10T12:00", [rb220], m))
            XCTAssertEqual(m, r.minutesBefore)
            XCTAssertEqual(repo.session(rb220)!.start.plusSeconds(-Int64(m) * 60), r.triggerAt)
            XCTAssertEqual("Starting in \(m) min · Regency Ballroom B, Level 4", r.text)
        }
    }

    func testOffMeansNoGoingRemindersButMyTalksKeepTheirs() {
        XCTAssertTrue(plan(nil, "2026-11-10T12:00", [rb220, rb500], 0).isEmpty)
        let mine = plan(lucy, "2026-11-10T12:00", [rb220, rb500], 0)
        XCTAssertEqual(6, mine.count)
        XCTAssertTrue(mine.allSatisfy { $0.kind == .mine })
    }

    func testMyTalksAndStarredSessionsMix() throws {
        let r = plan(lucy, "2026-11-10T12:00", [rb220, rb500])
        XCTAssertEqual(
            [
                "1363905/30", "1363905/10",
                "1249844/30", "1249844/10", "\(rb220)/10",
                "1289660/30", "\(rb500)/10", "1289660/10",
            ],
            r.map(\.key)
        )
        XCTAssertEqual(r.stableSorted(on: { $0.triggerAt }), r)
        // Same trigger time for my 2:20 talk's 10-minute reminder and the starred 2:20 session: both
        // arm (different sessions), ordered by id.
        XCTAssertEqual(at("2026-11-11T14:10"), try single(r.filter { $0.key == "1249844/10" }).triggerAt)
        XCTAssertEqual(at("2026-11-11T14:10"), try single(r.filter { $0.key == "\(rb220)/10" }).triggerAt)
        XCTAssertEqual("Your talk in 10 min · Grand Ballroom GI, Level 1", try single(r.filter { $0.key == "1249844/10" }).text)
        XCTAssertEqual("Starting in 10 min · Regency Ballroom B, Level 4", try single(r.filter { $0.key == "\(rb220)/10" }).text)
    }

    func testLucysWednesdayTalksStarredTooAreNotDoubleNotified() {
        let talks: Set<String> = ["1363905", "1249844", "1289660"]
        for m in [5, 10, 15] {
            let r = plan(lucy, "2026-11-10T12:00", talks.union([rb220]), m)
            // Still exactly the six talk reminders (30 and 10), plus the one starred session.
            XCTAssertEqual(7, r.count)
            XCTAssertEqual(6, r.filter { $0.kind == .mine }.count)
            for id in talks {
                XCTAssertEqual([30, 10], r.filter { $0.sessionId == id }.map(\.minutesBefore))
                XCTAssertTrue(r.filter { $0.sessionId == id }.allSatisfy { $0.text.kotlinStartsWith("Your talk in ") })
            }
            XCTAssertEqual([m], r.filter { $0.sessionId == rb220 }.map(\.minutesBefore))
        }
        // The keys stay unique, so every alarm is distinct.
        let keys = plan(lucy, "2026-11-10T12:00", talks.union([rb220])).map(\.key)
        XCTAssertEqual(keys.count, Set(keys).count)
    }

    func testWhenTheSpeakingAsChangesAStarredTalkBecomesAGoingReminder() throws {
        // Lucy's 2:20 talk, starred, while speaking as someone else (or None).
        let r = try single(plan(nil, "2026-11-10T12:00", ["1249844"]))
        XCTAssertEqual(ReminderKind.going, r.kind)
        XCTAssertEqual("Starting in 10 min · Grand Ballroom GI, Level 1", r.text)
        XCTAssertEqual(1, plan("Ryan Hallisey", "2026-11-10T12:00", ["1249844"]).filter { $0.sessionId == "1249844" }.count)
    }

    func testPastSessionsAndPastRemindersAreDropped() {
        let going: Set<String> = [rb220, rb500]
        // 2:12: the 2:10 reminder for RB 2:20 is past; the 4:50 one for 5:00 stays.
        XCTAssertEqual(["\(rb500)/10"], plan(nil, "2026-11-11T14:12", going).map(\.key))
        // Exactly at the trigger time: not in the future any more.
        XCTAssertEqual(["\(rb500)/10"], plan(nil, "2026-11-11T14:10", going).map(\.key))
        XCTAssertEqual(["\(rb220)/10", "\(rb500)/10"], plan(nil, "2026-11-11T14:09", going).map(\.key))
        // After the start (live or over): nothing.
        XCTAssertTrue(plan(nil, "2026-11-11T16:55", going).isEmpty)
        XCTAssertTrue(plan(nil, "2026-11-12T09:00", going).isEmpty)
        // With 15 min, a session 12 minutes away gets no reminder (it would be in the past).
        XCTAssertTrue(plan(nil, "2026-11-11T14:08", [rb220], 15).isEmpty)
    }

    func testUnknownStarredIdsAreIgnored() {
        XCTAssertTrue(plan(nil, "2026-11-10T12:00", ["gone", "also-gone"]).isEmpty)
        XCTAssertEqual(["\(rb220)/10"], plan(nil, "2026-11-10T12:00", ["gone", rb220]).map(\.key))
    }

    func testGoingTextUsesTheReminderRoomRules() throws {
        XCTAssertEqual("Starting in 10 min · 251 A–C, Level 2", ReminderPlanner.goingText(10, repo.room("251AC")))
        XCTAssertEqual("Starting in 5 min · Off-site", ReminderPlanner.goingText(5, repo.room("OFF")))
        XCTAssertEqual("Starting in 15 min", ReminderPlanner.goingText(15, nil))
        XCTAssertEqual("Starting in 10 min · Off-site", try single(plan(nil, "2026-11-08T08:00", [off])).text)
        XCTAssertEqual("Starting in 10 min · Hyatt lobby, Level 1", ReminderPlanner.text(.going, 10, repo.room("HL")))
        XCTAssertEqual("Your talk in 10 min · Hyatt lobby, Level 1", ReminderPlanner.text(.mine, 10, repo.room("HL")))
    }

    func testSpecForPicksMineFirst() {
        let talk = repo.session("1249844")!
        let other = repo.session(rb220)!
        XCTAssertEqual(ReminderSpec(.mine, [30, 10]), ReminderPlanner.specFor(talk, lucy, [talk.id], 15))
        XCTAssertEqual(ReminderSpec(.going, [15]), ReminderPlanner.specFor(other, lucy, [other.id], 15))
        XCTAssertNil(ReminderPlanner.specFor(other, lucy, [other.id], 0))
        XCTAssertNil(ReminderPlanner.specFor(other, lucy, [], 10))
        XCTAssertEqual(ReminderKind.going, ReminderPlanner.specFor(talk, nil, [talk.id], 10)!.kind)
    }

    func testALateGoingAlarmUsesItsOwnOffsets() {
        let start = at("2026-11-11T14:20")
        let going15 = [15]
        // A 15-minute "Going" reminder that fires 8 minutes late still shows (there's no 10-minute one).
        XCTAssertEqual(7, ReminderPlanner.minutesLeftToShow(start, 15, at("2026-11-11T14:13"), going15))
        XCTAssertEqual(15, ReminderPlanner.minutesLeftToShow(start, 15, at("2026-11-11T14:05"), going15))
        // My talks still drop a 30-minute reminder that runs into the 10-minute one.
        XCTAssertNil(ReminderPlanner.minutesLeftToShow(start, 30, at("2026-11-11T14:12")))
        // Never once it has started.
        XCTAssertNil(ReminderPlanner.minutesLeftToShow(start, 15, start, going15))
    }

    private func planArmed(_ now: String, _ minutes: Int, _ armed: Set<String>, going: Set<String>? = nil, me: String? = nil) -> [PlannedReminder] {
        ReminderPlanner.plan(repo.sessions, repo.rooms, me, at(now), going ?? [rb500], minutes, armed)
    }

    func testRaisingTheLeadTimeTooLateKeepsTheArmedReminder() throws {
        // RB 5:00 PM starred at 5 min (alarm at 4:55). At 4:52 the setting goes to 15 min: 4:45 is
        // past, so the 4:55 one stays (same key, so the reschedule doesn't cancel it).
        let kept = try single(planArmed("2026-11-11T16:52", 15, ["\(rb500)/5"]))
        XCTAssertEqual("\(rb500)/5", kept.key)
        XCTAssertEqual(at("2026-11-11T16:55"), kept.triggerAt)
        XCTAssertEqual(ReminderKind.going, kept.kind)
        XCTAssertEqual("Starting in 5 min · Regency Ballroom B, Level 4", kept.text)
        // Same for 5 → 10 at 4:52.
        XCTAssertEqual(["\(rb500)/5"], planArmed("2026-11-11T16:52", 10, ["\(rb500)/5"]).map(\.key))
        // 10 → 15 at 4:48: the 4:50 one stays.
        XCTAssertEqual(["\(rb500)/10"], planArmed("2026-11-11T16:48", 15, ["\(rb500)/10"]).map(\.key))
        // Without it armed (nothing to keep), or once its time has passed, there is nothing.
        XCTAssertTrue(planArmed("2026-11-11T16:52", 15, []).isEmpty)
        XCTAssertTrue(planArmed("2026-11-11T16:56", 15, ["\(rb500)/5"]).isEmpty)
        // Off means off.
        XCTAssertTrue(planArmed("2026-11-11T16:52", 0, ["\(rb500)/5"]).isEmpty)
        // Unstarred: nothing either.
        XCTAssertTrue(planArmed("2026-11-11T16:52", 15, ["\(rb500)/5"], going: []).isEmpty)
    }

    func testTheArmedSetChangesNothingElse() {
        let armed: Set<String> = ["\(rb500)/5", "\(rb220)/15", "1289660/30", "junk", "\(rb500)/x"]
        // In good time, the new lead time wins and the old key goes (it isn't planned, so it's cancelled).
        XCTAssertEqual(["\(rb500)/15"], planArmed("2026-11-11T12:00", 15, armed).map(\.key))
        // Lowering it close to the start just plans the shorter one (the longer one has fired).
        XCTAssertEqual(["\(rb500)/5"], planArmed("2026-11-11T16:52", 5, ["\(rb500)/15"]).map(\.key))
        // My talks keep their 30/10 whatever is armed.
        let mine = planArmed("2026-11-11T16:45", 15, armed.union(["1289660/5"]), going: [], me: lucy)
        XCTAssertEqual(["1289660/10"], mine.map(\.key))
        // Planning with the store's keys is idempotent: the plan's own keys plan the same again.
        let first = planArmed("2026-11-11T16:52", 15, ["\(rb500)/5"])
        XCTAssertEqual(first, planArmed("2026-11-11T16:52", 15, Set(first.map(\.key))))
    }

    func testTheReceiverAcceptsAKeptShorterGoingAlarm() {
        let going15 = ReminderSpec(.going, [15])
        XCTAssertTrue(ReminderPlanner.accepts(going15, 15))
        XCTAssertTrue(ReminderPlanner.accepts(going15, 10))
        XCTAssertTrue(ReminderPlanner.accepts(going15, 5))
        XCTAssertFalse(ReminderPlanner.accepts(going15, 30))
        XCTAssertFalse(ReminderPlanner.accepts(going15, 0))
        // A longer one left over from before the time was lowered is not shown.
        XCTAssertFalse(ReminderPlanner.accepts(ReminderSpec(.going, [5]), 15))
        // My talks: only 30 and 10.
        let mine = ReminderSpec(.mine, ReminderPlanner.OFFSETS_MIN)
        XCTAssertTrue(ReminderPlanner.accepts(mine, 30))
        XCTAssertTrue(ReminderPlanner.accepts(mine, 10))
        XCTAssertFalse(ReminderPlanner.accepts(mine, 5))
        // The kept 5-minute alarm firing on time shows "5 min".
        XCTAssertEqual(5, ReminderPlanner.minutesLeftToShow(at("2026-11-11T17:00"), 5, at("2026-11-11T16:55"), going15.offsets))
    }

    func testRequestCodesDifferForEveryLeadTime() {
        for id in [rb220, "1249844", "m1318417"] {
            let codes = [30, 15, 10, 5].map { ReminderPlanner.requestCode(id, $0) }
            XCTAssertEqual(4, Set(codes).count)
        }
    }
}
