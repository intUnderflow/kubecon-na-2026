import Foundation
import XCTest
@testable import KCNA26Core

/// The iOS reminder scheduling (Kotlin ReminderScheduler / ReminderNotifier / ReminderReceiver,
/// which have no Kotlin unit tests: their pure parts are tested here with a fake notification
/// center): what gets scheduled, the 64-request limit, cancelling, tidying delivered
/// notifications, the notification content, and the fire-time checks.
@MainActor
final class ReminderSchedulingTests: XCTestCase {
    private let repo = TestData.repo
    private let lucy = "Lucy Sweet"

    private struct Fixture {
        let center: FakeReminderCenter
        let store: ReminderStore
        let settings: SettingsStore
        let going: GoingStore
        let clock: FixedClock
        let wall: FixedClock
        let scheduler: ReminderScheduler
        let logs: Locked<[String]>
    }

    private func fixture(
        _ iso: String,
        wallIso: String? = nil,
        me: String? = nil,
        going ids: Set<String> = [],
        remindMinutes: Int = GoingStore.DEFAULT_REMIND_MINUTES,
        center: FakeReminderCenter = FakeReminderCenter(),
        repository: (@MainActor () async throws -> Repository)? = nil
    ) -> Fixture {
        let settings = SettingsStore(InMemoryStore())
        if let me { settings.setSpeakingAs(me) }
        let going = GoingStore(InMemoryStore())
        for id in ids { going.setGoing(id, true) }
        going.setRemindMinutes(remindMinutes)
        let store = ReminderStore(InMemoryStore())
        let clock = TestData.clockAt(iso)
        let wall = TestData.clockAt(wallIso ?? iso)
        let logs = Locked<[String]>([])
        let repo = repo
        let scheduler = ReminderScheduler(
            center: center,
            store: store,
            settings: settings,
            going: going,
            clock: clock,
            wallClock: wall,
            repository: repository ?? { repo },
            log: { m in logs.withLock { $0.append(m) } }
        )
        return Fixture(center: center, store: store, settings: settings, going: going, clock: clock, wall: wall, scheduler: scheduler, logs: logs)
    }

    private func plan(_ f: Fixture) -> [PlannedReminder] {
        ReminderPlanner.plan(repo.sessions, repo.rooms, f.settings.speakingAs, f.clock.now(), f.going.ids, f.going.remindMinutes, f.store.armed())
    }

    // MARK: - Scheduling

    func testLucysTalksAreScheduledWithTheNotifierTexts() async throws {
        let f = fixture("2026-11-10T12:00:00-07:00", me: lucy)
        let expected = plan(f)
        XCTAssertEqual(6, expected.count)

        let n = await f.scheduler.rescheduleNow()
        XCTAssertEqual(6, n)
        XCTAssertEqual(expected.map(\.key), f.center.addedIds)
        XCTAssertEqual(Set(expected.map(\.key)), f.store.armed())
        XCTAssertEqual(Set(expected.map(\.key)), Set(f.center.pendingIds))

        let gi10 = try XCTUnwrap(f.center.request("1249844/10"))
        XCTAssertEqual("Kubernetes The Hard Way - Live", gi10.content.title)
        XCTAssertEqual("Your talk in 10 min · Grand Ballroom GI, Level 1", gi10.content.body)
        XCTAssertEqual("talk:1249844", gi10.content.threadIdentifier)
        XCTAssertEqual(TestData.instant("2026-11-11T14:10:00-07:00"), gi10.fireDate)
        XCTAssertEqual(1, f.scheduler.runs)
        XCTAssertTrue(f.logs.value.contains { $0.hasPrefix("reminders: me=Lucy Sweet going=0@10m armed=6 of 6 ") }, "\(f.logs.value)")
    }

    func testFireDatesAreRealTimeWhenTheClockIsFaked() async {
        // The app clock says Tuesday noon; the real clock is two days earlier (debug fake time).
        let f = fixture("2026-11-10T12:00:00-07:00", wallIso: "2026-11-08T12:00:00-07:00", me: lucy)
        await f.scheduler.rescheduleNow()
        let r = f.center.request("1363905/30")
        XCTAssertEqual(TestData.instant("2026-11-09T09:15:00-07:00"), r?.fireDate)
        XCTAssertEqual(21 * 3600 + 15 * 60, r?.timeInterval(from: f.wall.now()))
    }

    func testOnlyTheSoonestSixtyAreScheduled() async {
        let all = Set(repo.sessions.map(\.id))
        let f = fixture("2026-11-08T08:00:00-07:00", going: all)
        let full = plan(f)
        XCTAssertGreaterThan(full.count, 200)

        let n = await f.scheduler.rescheduleNow()
        XCTAssertEqual(ReminderScheduler.MAX_PENDING, n)
        XCTAssertEqual(60, ReminderScheduler.MAX_PENDING)
        XCTAssertEqual(Array(full.prefix(60)).map(\.key), f.center.addedIds)
        XCTAssertEqual(60, f.center.pendingIds.count)
        XCTAssertEqual(Set(full.prefix(60).map(\.key)), f.store.armed())
        // Never more than iOS's limit.
        XCTAssertLessThanOrEqual(f.center.pendingIds.count, 64)
    }

    func testTheNextOnesAreScheduledAsTheFirstOnesFire() async {
        let all = Set(repo.sessions.map(\.id))
        let f = fixture("2026-11-08T08:00:00-07:00", going: all)
        await f.scheduler.rescheduleNow()
        let first = f.center.pendingIds

        // Later that day: the earliest have fired (iOS drops fired requests from pending).
        f.clock.instant = TestData.instant("2026-11-10T12:00:00-07:00")
        f.wall.instant = f.clock.instant
        f.center.fireDue(at: f.wall.now())
        let next = plan(f)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual(Array(next.prefix(60)).map(\.key).sorted(), f.center.pendingIds.sorted())
        XCTAssertEqual(Set(next.prefix(60).map(\.key)), f.store.armed())
        // The fired ones were stale in the store: cancelled (a no-op on iOS), not scheduled again.
        let fired = Set(first).subtracting(next.map(\.key))
        XCTAssertFalse(fired.isEmpty)
        XCTAssertTrue(fired.isSubset(of: Set(f.center.removedPendingIds)))
        XCTAssertTrue(fired.isDisjoint(with: Set(f.center.pendingIds)))
    }

    func testSelectKeepsTheSoonestInPlanOrder() {
        let base = TestData.instant("2026-11-10T08:00:00-07:00")
        let plan = (0..<100).map { i in
            PlannedReminder("s\(i)", base.plusMinutes(i), 10, "T\(i)", "Starting in 10 min", .going)
        }
        XCTAssertEqual(Array(plan.prefix(60)), ReminderScheduler.select(plan))
        XCTAssertEqual(Array(plan.prefix(3)), ReminderScheduler.select(plan, max: 3))
        XCTAssertEqual([], ReminderScheduler.select(plan, max: 0))
        XCTAssertEqual(Array(plan.prefix(5)), ReminderScheduler.select(Array(plan.prefix(5))))
    }

    func testChangingSpeakingAsCancelsTheOldTalks() async {
        let f = fixture("2026-11-10T12:00:00-07:00", me: lucy)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual(6, f.center.pendingIds.count)

        f.settings.setSpeakingAs(nil)
        let n = await f.scheduler.rescheduleNow()
        XCTAssertEqual(0, n)
        XCTAssertEqual([], f.center.pendingIds)
        XCTAssertEqual([], f.store.armed())
        XCTAssertEqual(6, f.center.removedPendingIds.count)
        XCTAssertTrue(f.logs.value.last?.contains("cancelled=6") ?? false)
    }

    func testStarsAndTheLeadTimeFollow() async {
        // 1203350: a Wednesday session, not Lucy's.
        let s = repo.session("1203350")!
        let f = fixture("2026-11-10T12:00:00-07:00", going: ["1203350"], remindMinutes: 15)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual(["1203350/15"], f.center.pendingIds)
        XCTAssertEqual(s.start.minusMinutes(15), f.center.request("1203350/15")?.fireDate)
        XCTAssertEqual(
            ReminderPlanner.goingText(15, repo.roomOf(s)),
            f.center.request("1203350/15")?.content.body
        )

        f.going.setRemindMinutes(5)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual(["1203350/5"], f.center.pendingIds)

        f.going.setRemindMinutes(GoingStore.REMIND_OFF)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual([], f.center.pendingIds)

        f.going.setRemindMinutes(10)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual(["1203350/10"], f.center.pendingIds)
        f.going.setGoing("1203350", false)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual([], f.center.pendingIds)
    }

    func testRaisingTheLeadTimeTooLateKeepsTheScheduledReminder() async {
        let s = repo.session("1203350")!
        // 8 minutes before the start, with a 5 minute reminder scheduled.
        let f = fixture(iso(s.start.minusMinutes(8)), going: ["1203350"], remindMinutes: 5)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual(["1203350/5"], f.center.pendingIds)
        // 15 minutes is already past: the 5 minute one stays (not cancelled).
        f.going.setRemindMinutes(15)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual(["1203350/5"], f.center.pendingIds)
        XCTAssertEqual([], f.center.removedPendingIds)
        XCTAssertEqual(["1203350/5"], f.store.armed())
    }

    func testUnknownPendingRemindersAreCancelledOthersLeftAlone() async {
        let center = FakeReminderCenter()
        center.addForeignPending("999999/10")
        center.addForeignPending("welcome-tip")
        let f = fixture("2026-11-10T12:00:00-07:00", me: lucy, center: center)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual(["999999/10"], f.center.removedPendingIds)
        XCTAssertTrue(f.center.pendingIds.contains("welcome-tip"))
        XCTAssertEqual(7, f.center.pendingIds.count)
    }

    func testAReminderDueWhileReschedulingIsNotAddedTwice() async {
        let center = FakeReminderCenter()
        // Wednesday 09:44:59: Lucy's 14:20 and 17:00 talks are still to come (4 reminders).
        let f = fixture("2026-11-11T09:44:59-07:00", me: lucy, center: center)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual(["1249844/30", "1249844/10", "1289660/30", "1289660/10"], center.pendingIds)

        // The next run plans at 13:49:59.5, just before 1249844/30 (13:50) is due; by the time it
        // asks for the pending requests, both clocks are past 13:50 and iOS has fired it.
        let clock = f.clock
        let wall = f.wall
        clock.instant = TestData.instant("2026-11-11T13:49:59-07:00").addingTimeInterval(0.5)
        wall.instant = clock.instant
        center.onPendingQuery = {
            wall.instant = TestData.instant("2026-11-11T13:50:00-07:00").addingTimeInterval(0.2)
            clock.instant = wall.instant
            center.fireDue(at: wall.instant)
        }
        let before = center.addedIds.count
        await f.scheduler.rescheduleNow()
        let addedNow = Array(center.addedIds.dropFirst(before))
        XCTAssertEqual(["1249844/10", "1289660/30", "1289660/10"], addedNow)
        XCTAssertEqual(["1249844/30"], center.fired)
        XCTAssertFalse(center.pendingIds.contains("1249844/30"))
        // It was planned (the plan ran first), so it stays in the store until the next reschedule.
        XCTAssertTrue(f.store.armed().contains("1249844/30"))
    }

    func testShouldAddRules() {
        let content = ReminderContent(identifier: "1/10", sessionId: "1", minutesBefore: 10, kind: .going, title: "T", body: "B")
        let now = TestData.instant("2026-11-10T12:00:00-07:00")
        let r = { (s: TimeInterval) in ReminderRequest(content: content, fireDate: now.addingTimeInterval(s)) }
        XCTAssertTrue(ReminderScheduler.shouldAdd(r(60), alreadyPending: false, realNow: now))
        XCTAssertTrue(ReminderScheduler.shouldAdd(r(60), alreadyPending: true, realNow: now))
        XCTAssertTrue(ReminderScheduler.shouldAdd(r(0.5), alreadyPending: false, realNow: now))
        XCTAssertFalse(ReminderScheduler.shouldAdd(r(0.5), alreadyPending: true, realNow: now))
        XCTAssertFalse(ReminderScheduler.shouldAdd(r(0), alreadyPending: false, realNow: now))
        XCTAssertFalse(ReminderScheduler.shouldAdd(r(-5), alreadyPending: true, realNow: now))
        XCTAssertEqual(1, r(0.5).timeInterval(from: now))
        XCTAssertEqual(1, r(-30).timeInterval(from: now))
        XCTAssertEqual(90, r(90).timeInterval(from: now))
    }

    func testReschedulesRunOneAtATimeAndTheLastSettingWins() async {
        let center = FakeReminderCenter(delayNanos: 3_000_000)
        let f = fixture("2026-11-10T12:00:00-07:00", center: center)
        f.settings.setSpeakingAs(lucy)
        f.scheduler.reschedule()
        // Let the first run start and suspend in the center.
        while center.calls == 0 { await Task.yield() }
        f.settings.setSpeakingAs(nil)
        f.scheduler.reschedule()
        f.going.setGoing("1203350", true)
        f.scheduler.reschedule()
        f.settings.setSpeakingAs(lucy)
        f.scheduler.reschedule()
        await f.scheduler.settle()

        XCTAssertEqual(1, center.maxInFlight)
        // The three requests made while the first run was busy were served by one more run.
        XCTAssertEqual(2, f.scheduler.runs)
        XCTAssertEqual(Set(plan(f).map(\.key)), Set(center.pendingIds))
        XCTAssertEqual(7, center.pendingIds.count)
        XCTAssertTrue(center.pendingIds.contains("1203350/10"))
        // Nothing left to do.
        let runs = f.scheduler.runs
        await f.scheduler.settle()
        XCTAssertEqual(runs, f.scheduler.runs)
    }

    func testAFailingRepositoryArmsNothingAndDoesNotThrow() async {
        struct Broken: Error {}
        let f = fixture("2026-11-10T12:00:00-07:00", me: lucy, repository: { throw Broken() })
        let n = await f.scheduler.rescheduleNow()
        XCTAssertEqual(0, n)
        XCTAssertEqual(0, f.center.calls)
        XCTAssertEqual([], f.store.armed())
        XCTAssertTrue(f.logs.value.contains { $0.hasPrefix("reminders: reschedule failed") })
        XCTAssertEqual(1, f.scheduler.runs)
    }

    func testARefusedRequestIsLoggedAndTheOthersStillGoIn() async {
        let center = FakeReminderCenter()
        center.failing = ["1249844/30"]
        let f = fixture("2026-11-10T12:00:00-07:00", me: lucy, center: center)
        let n = await f.scheduler.rescheduleNow()
        XCTAssertEqual(6, n)
        XCTAssertEqual(5, center.pendingIds.count)
        XCTAssertFalse(center.pendingIds.contains("1249844/30"))
        // Kotlin records every planned key as armed, whether or not arming worked.
        XCTAssertEqual(6, f.store.armed().count)
        XCTAssertTrue(f.logs.value.contains { $0.hasPrefix("reminders: can't schedule 1249844/30") })
    }

    // MARK: - Delivered notifications

    func testDeliveredRemindersAreTidied() async {
        let gi = repo.session("1249844")! // Lucy's, 14:20
        let star = repo.session("1203350")!
        let now = gi.start.minusMinutes(5)
        let delivered = [
            DeliveredReminder(identifier: "1249844/30", sessionId: "1249844", minutesBefore: 30, date: gi.start.minusMinutes(30)),
            DeliveredReminder(identifier: "1249844/10", sessionId: "1249844", minutesBefore: 10, date: gi.start.minusMinutes(10)),
            DeliveredReminder(identifier: "1203350/10", sessionId: "1203350", minutesBefore: 10, date: star.start.minusMinutes(10)),
            DeliveredReminder(identifier: "1363905/10", sessionId: "1363905", minutesBefore: 10, date: now.minusMinutes(300)),
            DeliveredReminder(identifier: "999999/10", sessionId: "999999", minutesBefore: 10, date: now),
            DeliveredReminder(identifier: "welcome-tip", sessionId: nil, minutesBefore: nil, date: now),
        ]
        // Lucy's, and the star still wanted.
        let gone = ReminderScheduler.deliveredToRemove(delivered, repo, lucy, ["1203350"], 10, now)
        // 30 superseded by 10; the star (14:20–14:50) stays; 1363905 (09:45–09:50) has ended by
        // 14:15; 999999 isn't in the data; the tip isn't a reminder.
        XCTAssertTrue(now.isBefore(star.effectiveEnd))
        XCTAssertEqual(["1249844/30", "1363905/10", "999999/10"], gone)

        // Not mine any more, not starred any more.
        XCTAssertEqual(
            ["1249844/30", "1249844/10", "1203350/10", "1363905/10", "999999/10"],
            ReminderScheduler.deliveredToRemove(delivered, repo, nil, [], 10, now)
        )
        // The "Going" reminders off: the star's goes, Lucy's stay.
        XCTAssertTrue(ReminderScheduler.deliveredToRemove(delivered, repo, lucy, ["1203350"], 0, now).contains("1203350/10"))
        // At the end of the session it goes (Kotlin setTimeoutAfter).
        XCTAssertTrue(ReminderScheduler.deliveredToRemove(delivered, repo, lucy, [], 10, gi.effectiveEnd).contains("1249844/10"))
        XCTAssertFalse(ReminderScheduler.deliveredToRemove(delivered, repo, lucy, [], 10, gi.effectiveEnd.addingTimeInterval(-1)).contains("1249844/10"))
    }

    func testOneDeliveredReminderPerSessionPrefersTheLaterOne() {
        let gi = repo.session("1249844")!
        let now = gi.start.minusMinutes(1)
        let at = gi.start.minusMinutes(10)
        // Delivered at the same moment (e.g. after a time change): the shorter lead time is the later one.
        let same = [
            DeliveredReminder(identifier: "1249844/10", sessionId: "1249844", minutesBefore: 10, date: at),
            DeliveredReminder(identifier: "1249844/30", sessionId: "1249844", minutesBefore: 30, date: at),
        ]
        XCTAssertEqual(["1249844/30"], ReminderScheduler.deliveredToRemove(same, repo, lucy, [], 10, now))
        let newerFirst = [
            DeliveredReminder(identifier: "1249844/10", sessionId: "1249844", minutesBefore: 10, date: at),
            DeliveredReminder(identifier: "1249844/30", sessionId: "1249844", minutesBefore: 30, date: at.addingTimeInterval(1)),
        ]
        // Before the 10 minute one's moment (the debug fake time moved back), the later delivery stays.
        let early = gi.start.minusMinutes(11)
        XCTAssertEqual(["1249844/10"], ReminderScheduler.deliveredToRemove(newerFirst, repo, lucy, [], 10, early))
        XCTAssertEqual(["1249844/30"], ReminderScheduler.deliveredToRemove(same, repo, lucy, [], 10, early))
        // Once the 10 minute one is due, the 30 minute one is superseded however late it arrived
        // (Kotlin's receiver drops it as stale), and the 10 minute one is the session's notification.
        XCTAssertEqual(["1249844/30"], ReminderScheduler.deliveredToRemove(newerFirst, repo, lucy, [], 10, now))
    }

    func testRescheduleRemovesDeliveredRemindersThatNoLongerApply() async {
        let center = FakeReminderCenter()
        let gi = repo.session("1249844")!
        center.deliver(DeliveredReminder(identifier: "1249844/30", sessionId: "1249844", minutesBefore: 30, date: gi.start.minusMinutes(30)))
        center.deliver(DeliveredReminder(identifier: "1249844/10", sessionId: "1249844", minutesBefore: 10, date: gi.start.minusMinutes(10)))
        let f = fixture(iso(gi.start.minusMinutes(5)), me: lucy, center: center)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual(["1249844/30"], center.removedDeliveredIds)
        f.settings.setSpeakingAs(nil)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual(["1249844/30", "1249844/10"], center.removedDeliveredIds)
        XCTAssertEqual([], center.deliveredIds)
    }

    func testAnOlderReminderGoesOnceTheShorterOneIsDueEvenIfThatOneIsGone() {
        // Lucy's talk at 14:20: the 30 minute reminder was delivered at 13:50, the 10 minute one at
        // 14:10 and then tapped or swiped away (iOS removed it). Kotlin's 10 minute one replaced
        // the 30 minute one under the session's tag, so nothing of the session is left.
        let gi = repo.session("1249844")!
        let only30 = [DeliveredReminder(identifier: "1249844/30", sessionId: "1249844", minutesBefore: 30, date: gi.start.minusMinutes(30))]
        XCTAssertEqual(["1249844/30"], ReminderScheduler.deliveredToRemove(only30, repo, lucy, [], 10, gi.start.minusMinutes(9)))
        // Due at 14:10 sharp (the 10 minute one's moment).
        XCTAssertEqual(["1249844/30"], ReminderScheduler.deliveredToRemove(only30, repo, lucy, [], 10, gi.start.minusMinutes(10)))
        // Before then it is the session's notification and stays.
        XCTAssertEqual([], ReminderScheduler.deliveredToRemove(only30, repo, lucy, [], 10, gi.start.minusMinutes(10).addingTimeInterval(-1)))
        // The 10 minute one has no shorter one after it: it stays until the session ends.
        let only10 = [DeliveredReminder(identifier: "1249844/10", sessionId: "1249844", minutesBefore: 10, date: gi.start.minusMinutes(10))]
        XCTAssertEqual([], ReminderScheduler.deliveredToRemove(only10, repo, lucy, [], 10, gi.start.minusMinutes(1)))

        // "Going": the lead time lowered from 15 to 10 after the 15 minute one was delivered: the
        // 10 minute one replaces it when it comes due. Raised from 10 to 15: the 10 stays.
        let star = repo.session("1203350")!
        let star15 = [DeliveredReminder(identifier: "1203350/15", sessionId: "1203350", minutesBefore: 15, date: star.start.minusMinutes(15))]
        XCTAssertEqual([], ReminderScheduler.deliveredToRemove(star15, repo, nil, ["1203350"], 10, star.start.minusMinutes(12)))
        XCTAssertEqual(["1203350/15"], ReminderScheduler.deliveredToRemove(star15, repo, nil, ["1203350"], 10, star.start.minusMinutes(10)))
        let star10 = [DeliveredReminder(identifier: "1203350/10", sessionId: "1203350", minutesBefore: 10, date: star.start.minusMinutes(10))]
        XCTAssertEqual([], ReminderScheduler.deliveredToRemove(star10, repo, nil, ["1203350"], 15, star.start.minusMinutes(5)))
        XCTAssertFalse(ReminderScheduler.supersededBySchedule(star, 10, ReminderSpec(.going, [15]), star.start.minusMinutes(5)))
        XCTAssertTrue(ReminderScheduler.supersededBySchedule(gi, 30, ReminderSpec(.mine, [30, 10]), gi.start.minusMinutes(10)))
        XCTAssertFalse(ReminderScheduler.supersededBySchedule(gi, 30, ReminderSpec(.mine, [30, 10]), gi.start.minusMinutes(11)))
    }

    func testRescheduleRemovesTheOlderReminderAfterTheNewerOneWasTapped() async {
        let center = FakeReminderCenter()
        let gi = repo.session("1249844")!
        center.deliver(DeliveredReminder(identifier: "1249844/30", sessionId: "1249844", minutesBefore: 30, date: gi.start.minusMinutes(30)))
        // 14:11: the 10 minute one was tapped (iOS removed it); the app becomes active and re-plans.
        let f = fixture(iso(gi.start.minusMinutes(9)), me: lucy, center: center)
        await f.scheduler.rescheduleNow()
        XCTAssertEqual(["1249844/30"], center.removedDeliveredIds)
        XCTAssertEqual([], center.deliveredIds)
    }

    func testTheSessionsOtherDeliveredRemindersGoWhenOneIsShownOrTapped() async {
        let gi = repo.session("1249844")!
        let delivered = [
            DeliveredReminder(identifier: "1249844/30", sessionId: "1249844", minutesBefore: 30, date: gi.start.minusMinutes(30)),
            DeliveredReminder(identifier: "1249844/10", sessionId: "1249844", minutesBefore: 10, date: gi.start.minusMinutes(10)),
            DeliveredReminder(identifier: "1203350/10", sessionId: "1203350", minutesBefore: 10, date: gi.start.minusMinutes(10)),
            DeliveredReminder(identifier: "welcome-tip", sessionId: nil, minutesBefore: nil, date: gi.start),
        ]
        // Shown: the 10 minute one replaces the session's others (Kotlin's per-session tag).
        XCTAssertEqual(["1249844/30"], ReminderScheduler.deliveredOfSession(delivered, "1249844", keeping: 10))
        // Tapped: nothing of the session is left (Kotlin's autoCancel).
        XCTAssertEqual(["1249844/30", "1249844/10"], ReminderScheduler.deliveredOfSession(delivered, "1249844", keeping: nil))
        XCTAssertEqual([], ReminderScheduler.deliveredOfSession(delivered, "999999", keeping: nil))

        let center = FakeReminderCenter()
        for d in delivered { center.deliver(d) }
        let f = fixture(iso(gi.start.minusMinutes(10)), me: lucy, center: center)
        f.scheduler.tidyDelivered(of: "1249844", keeping: 10)
        await f.scheduler.settle()
        XCTAssertEqual(["1249844/30"], center.removedDeliveredIds)
        XCTAssertEqual(["1249844/10", "1203350/10", "welcome-tip"], center.deliveredIds)
        XCTAssertTrue(f.logs.value.contains("reminders: removed delivered 1249844/30 (1249844/10 shown)"))
        f.scheduler.tidyDelivered(of: "1249844")
        await f.scheduler.settle()
        XCTAssertEqual(["1203350/10", "welcome-tip"], center.deliveredIds)
        XCTAssertTrue(f.logs.value.contains("reminders: removed delivered 1249844/10 (1249844 tapped)"))
        // Nothing to remove: no call, no log.
        let removeCalls = center.removedDeliveredIds.count
        let removed = await f.scheduler.removeDelivered(of: "1249844")
        XCTAssertEqual([], removed)
        XCTAssertEqual(removeCalls, center.removedDeliveredIds.count)
        // No reschedule ran.
        XCTAssertEqual(0, f.scheduler.runs)
    }

    // MARK: - Content

    func testContentMirrorsTheNotifier() throws {
        let mine = try XCTUnwrap(ReminderPlanner.plan(repo.sessions, repo.rooms, lucy, TestData.instant("2026-11-10T12:00:00-07:00"))
            .first { $0.key == "1249844/10" })
        let c = ReminderContent(mine)
        XCTAssertEqual("1249844/10", c.identifier)
        XCTAssertEqual("1249844", c.sessionId)
        XCTAssertEqual(10, c.minutesBefore)
        XCTAssertEqual(.mine, c.kind)
        XCTAssertEqual("Kubernetes The Hard Way - Live", c.title)
        XCTAssertEqual("Your talk in 10 min · Grand Ballroom GI, Level 1", c.body)
        XCTAssertEqual("talk:1249844", c.threadIdentifier)
        XCTAssertEqual("directions:1249844", c.targetContentIdentifier)
        XCTAssertEqual("your_talks", c.channelId)
        XCTAssertEqual(
            [
                "action": "app.kcna26.action.OPEN_DIRECTIONS",
                "app.kcna26.extra.SESSION_ID": "1249844",
                "app.kcna26.extra.REMINDER_MINUTES_BEFORE": "10",
                "app.kcna26.extra.REMINDER_KIND": "MINE",
            ],
            c.userInfo
        )

        let star = try XCTUnwrap(ReminderPlanner.plan(repo.sessions, repo.rooms, nil, TestData.instant("2026-11-10T12:00:00-07:00"), ["1249844"], 15)
            .first)
        let g = ReminderContent(star)
        XCTAssertEqual("1249844/15", g.identifier)
        XCTAssertEqual("Starting in 15 min · Grand Ballroom GI, Level 1", g.body)
        XCTAssertEqual("going", g.channelId)
        XCTAssertEqual("GOING", g.userInfo[ReminderContent.EXTRA_KIND])

        XCTAssertEqual("Your talks", ReminderContent.CHANNEL_NAME)
        XCTAssertEqual("Sessions you’ve RSVP’d to", ReminderContent.GOING_CHANNEL_NAME)
        XCTAssertEqual("your_talks", ReminderContent.channelFor(.mine))
        XCTAssertEqual("going", ReminderContent.channelFor(.going))
    }

    func testKeyOfReadsUserInfoThenTheIdentifier() throws {
        let c = ReminderContent(identifier: "1249844/10", sessionId: "1249844", minutesBefore: 10, kind: .mine, title: "T", body: "B")
        let info: [AnyHashable: Any] = c.userInfo
        var k = try XCTUnwrap(ReminderContent.keyOf(identifier: "ignored", userInfo: info))
        XCTAssertEqual("1249844", k.sessionId)
        XCTAssertEqual(10, k.minutes)
        // An Int extra works too.
        k = try XCTUnwrap(ReminderContent.keyOf(identifier: "x", userInfo: [ReminderContent.EXTRA_SESSION_ID: "m1290687", ReminderContent.EXTRA_MINUTES_BEFORE: 30]))
        XCTAssertEqual("m1290687", k.sessionId)
        XCTAssertEqual(30, k.minutes)
        // Missing or non-positive extras: the identifier "<id>/<minutes>".
        k = try XCTUnwrap(ReminderContent.keyOf(identifier: "1203350/5", userInfo: [:]))
        XCTAssertEqual("1203350", k.sessionId)
        XCTAssertEqual(5, k.minutes)
        k = try XCTUnwrap(ReminderContent.keyOf(identifier: "1203350/5", userInfo: [ReminderContent.EXTRA_SESSION_ID: "1", ReminderContent.EXTRA_MINUTES_BEFORE: "0"]))
        XCTAssertEqual("1203350", k.sessionId)
        XCTAssertNil(ReminderContent.keyOf(identifier: "welcome-tip", userInfo: [:]))
        XCTAssertNil(ReminderContent.keyOf(identifier: "1203350/", userInfo: [ReminderContent.EXTRA_SESSION_ID: "1203350"]))

        let d = DeliveredReminder(identifier: c.identifier, userInfo: info, date: TestData.instant("2026-11-11T14:10:00-07:00"))
        XCTAssertEqual("1249844", d.sessionId)
        XCTAssertEqual(10, d.minutesBefore)
        let other = DeliveredReminder(identifier: "welcome-tip", userInfo: [:], date: TestData.instant("2026-11-11T14:10:00-07:00"))
        XCTAssertNil(other.sessionId)
        XCTAssertNil(other.minutesBefore)
    }

    func testATapOpensDirectionsForTheSession() {
        let c = ReminderContent(identifier: "m1290687/10", sessionId: "m1290687", minutesBefore: 10, kind: .going, title: "T", body: "B")
        XCTAssertEqual("m1290687", ReminderContent.directionsSessionId(c.userInfo))
        XCTAssertNil(ReminderContent.directionsSessionId([ReminderContent.EXTRA_SESSION_ID: "m1290687"]))
        XCTAssertNil(ReminderContent.directionsSessionId(["action": "something.else", ReminderContent.EXTRA_SESSION_ID: "m1290687"]))
        XCTAssertNil(ReminderContent.directionsSessionId(["action": ReminderContent.ACTION_OPEN_DIRECTIONS]))
    }

    // MARK: - Fire-time checks (Kotlin ReminderReceiver)

    func testAFiringReminderIsCheckedAgainstTheCurrentSettings() {
        let gi = repo.session("1249844")!
        let onTime = gi.start.minusMinutes(10)
        XCTAssertEqual(
            .show(title: "Kubernetes The Hard Way - Live", text: "Your talk in 10 min · Grand Ballroom GI, Level 1", channelId: "your_talks", expiresAt: gi.effectiveEnd),
            ReminderFiring.check("1249844", 10, repo, lucy, [], 10, onTime)
        )
        // Late (e.g. delivered after a time change): the real minutes left.
        XCTAssertEqual(
            .show(title: "Kubernetes The Hard Way - Live", text: "Your talk in 7 min · Grand Ballroom GI, Level 1", channelId: "your_talks", expiresAt: gi.effectiveEnd),
            ReminderFiring.check("1249844", 10, repo, lucy, [], 10, gi.start.minusMinutes(7))
        )
        // The 30 minute one running so late that the 10 minute one is due too: skipped.
        XCTAssertEqual(.stale, ReminderFiring.check("1249844", 30, repo, lucy, [], 10, gi.start.minusMinutes(9)))
        XCTAssertEqual(.stale, ReminderFiring.check("1249844", 10, repo, lucy, [], 10, gi.start))
        // Not mine any more; starred instead, with another lead time.
        XCTAssertEqual(.notWanted, ReminderFiring.check("1249844", 10, repo, nil, [], 10, onTime))
        XCTAssertEqual(.notWanted, ReminderFiring.check("1249844", 30, repo, nil, ["1249844"], 10, onTime))
        XCTAssertEqual(
            .show(title: "Kubernetes The Hard Way - Live", text: "Starting in 10 min · Grand Ballroom GI, Level 1", channelId: "going", expiresAt: gi.effectiveEnd),
            ReminderFiring.check("1249844", 10, repo, nil, ["1249844"], 10, onTime)
        )
        // A shorter one the planner kept after the lead time was raised late.
        XCTAssertTrue(ReminderFiring.check("1249844", 5, repo, nil, ["1249844"], 15, gi.start.minusMinutes(5)).shows)
        XCTAssertEqual(.unknownSession, ReminderFiring.check("999999", 10, repo, lucy, [], 10, onTime))
    }

    func testFiringLogLinesMatchKotlin() {
        let now = TestData.instant("2026-11-11T14:10:00-07:00")
        XCTAssertEqual(
            "reminders: 1249844/10 skipped, not mine or going any more",
            ReminderFiring.notWanted.logLine("1249844", 10, now: now, posted: false)
        )
        XCTAssertEqual(
            "reminders: 1249844/10 skipped as stale at \(now)",
            ReminderFiring.stale.logLine("1249844", 10, now: now, posted: false)
        )
        XCTAssertEqual(
            "reminders: 1249844/10 \"Your talk in 10 min · Grand Ballroom GI, Level 1\" posted=true",
            ReminderFiring.show(title: "T", text: "Your talk in 10 min · Grand Ballroom GI, Level 1", channelId: "your_talks", expiresAt: now)
                .logLine("1249844", 10, now: now, posted: true)
        )
        XCTAssertNil(ReminderFiring.unknownSession.logLine("1249844", 10, now: now, posted: false))
    }

    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
}

/// A fake `UNUserNotificationCenter` (shared with AppGraphTests): pending requests, delivered
/// notifications, and the calls made. Thread-safe.
final class FakeReminderCenter: ReminderScheduling, @unchecked Sendable {
    struct Refused: Error {}

    private struct State {
        var pending: [String: ReminderRequest] = [:]
        var pendingOrder: [String] = []
        var foreign: [String] = []
        var delivered: [DeliveredReminder] = []
        var added: [String] = []
        var removedPending: [String] = []
        var removedDelivered: [String] = []
        var fired: [String] = []
        var failing: Set<String> = []
        var calls = 0
        var inFlight = 0
        var maxInFlight = 0
        var onPendingQuery: (@Sendable () -> Void)?
    }

    private let state = Locked(State())
    private let delayNanos: UInt64

    init(delayNanos: UInt64 = 0) {
        self.delayNanos = delayNanos
    }

    var pendingIds: [String] { state.value.pendingOrder + state.value.foreign }
    var addedIds: [String] { state.value.added }
    var removedPendingIds: [String] { state.value.removedPending }
    var removedDeliveredIds: [String] { state.value.removedDelivered }
    var deliveredIds: [String] { state.value.delivered.map(\.identifier) }
    var fired: [String] { state.value.fired }
    var calls: Int { state.value.calls }
    var maxInFlight: Int { state.value.maxInFlight }
    var failing: Set<String> {
        get { state.value.failing }
        set { state.withLock { $0.failing = newValue } }
    }
    var onPendingQuery: (@Sendable () -> Void)? {
        get { state.value.onPendingQuery }
        set { state.withLock { $0.onPendingQuery = newValue } }
    }

    func request(_ id: String) -> ReminderRequest? { state.value.pending[id] }

    /// A pending request some other code scheduled.
    func addForeignPending(_ id: String) { state.withLock { $0.foreign.append(id) } }

    func deliver(_ d: DeliveredReminder) { state.withLock { $0.delivered.append(d) } }

    /// iOS fires every pending request due at `now`: it leaves pending and is delivered.
    func fireDue(at now: Date) {
        state.withLock { s in
            for id in s.pendingOrder {
                guard let r = s.pending[id], r.fireDate <= now else { continue }
                s.pending[id] = nil
                s.fired.append(id)
                s.delivered.append(DeliveredReminder(identifier: id, userInfo: r.content.userInfo, date: r.fireDate))
            }
            s.pendingOrder.removeAll { s.pending[$0] == nil }
        }
    }

    private func call<T>(_ body: (inout State) throws -> T) async rethrows -> T {
        state.withLock { s in
            s.calls += 1
            s.inFlight += 1
            s.maxInFlight = max(s.maxInFlight, s.inFlight)
        }
        if delayNanos > 0 { try? await Task.sleep(nanoseconds: delayNanos) }
        defer { state.withLock { $0.inFlight -= 1 } }
        return try state.withLock(body)
    }

    func pendingIdentifiers() async -> [String] {
        if let hook = state.value.onPendingQuery { hook() }
        return await call { s in s.pendingOrder + s.foreign }
    }

    func add(_ request: ReminderRequest) async throws {
        try await call { s in
            if s.failing.contains(request.identifier) { throw Refused() }
            if s.pending[request.identifier] == nil { s.pendingOrder.append(request.identifier) }
            s.pending[request.identifier] = request
            s.added.append(request.identifier)
        }
    }

    func removePending(_ identifiers: [String]) async {
        await call { s in
            for id in identifiers {
                s.removedPending.append(id)
                s.pending[id] = nil
                s.foreign.removeAll { $0 == id }
            }
            s.pendingOrder.removeAll { s.pending[$0] == nil }
        }
    }

    func delivered() async -> [DeliveredReminder] {
        await call { s in s.delivered }
    }

    func removeDelivered(_ identifiers: [String]) async {
        await call { s in
            s.removedDelivered.append(contentsOf: identifiers)
            s.delivered.removeAll { identifiers.contains($0.identifier) }
        }
    }
}
