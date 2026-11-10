import XCTest
@testable import KCNA26Core

/// Port of schedule/ScheduleLogicTest.kt.
final class ScheduleLogicTests: XCTestCase {
    private let repo = TestData.repo
    private var days: [Day] { repo.days }

    private func at(_ iso: String) -> Date { TestData.instant(iso) }
    private func s(_ id: String) -> Session { repo.session(id)! }

    // MARK: - finished / live

    func testFinishedUsesEndAndIsExclusiveAtTheEndMinute() {
        let eviction = s("1289660") // Wed 5:00–5:30 PM, 251 A–C
        XCTAssertFalse(ScheduleLogic.isFinished(eviction, at("2026-11-11T17:29:59-07:00")))
        XCTAssertTrue(ScheduleLogic.isFinished(eviction, at("2026-11-11T17:30:00-07:00")))
        XCTAssertTrue(ScheduleLogic.isFinished(eviction, at("2026-11-11T18:00:00-07:00")))
        XCTAssertFalse(ScheduleLogic.isFinished(eviction, at("2026-11-11T09:00:00-07:00")))
    }

    func testNullEndCountsAsNinetyMinutes() {
        let reception = s("m1318417") // Sun 5:30 PM, no end
        XCTAssertNil(reception.end)
        XCTAssertFalse(ScheduleLogic.isFinished(reception, at("2026-11-08T18:59:00-07:00")))
        XCTAssertTrue(ScheduleLogic.isLive(reception, at("2026-11-08T18:59:00-07:00")))
        XCTAssertTrue(ScheduleLogic.isFinished(reception, at("2026-11-08T19:00:00-07:00")))
        XCTAssertFalse(ScheduleLogic.isLive(reception, at("2026-11-08T19:00:00-07:00")))
        XCTAssertEqual(60, ScheduleLogic.minutesLeft(reception, at("2026-11-08T18:00:00-07:00")))
    }

    func testLiveWindowAndMinutesLeft() {
        let eviction = s("1289660")
        XCTAssertFalse(ScheduleLogic.isLive(eviction, at("2026-11-11T16:59:59-07:00")))
        XCTAssertTrue(ScheduleLogic.isLive(eviction, at("2026-11-11T17:00:00-07:00")))
        XCTAssertEqual(30, ScheduleLogic.minutesLeft(eviction, at("2026-11-11T17:00:00-07:00")))
        XCTAssertEqual(20, ScheduleLogic.minutesLeft(eviction, at("2026-11-11T17:10:00-07:00")))
        // Seconds are dropped like the web's minute arithmetic.
        XCTAssertEqual(20, ScheduleLogic.minutesLeft(eviction, at("2026-11-11T17:10:59-07:00")))
        XCTAssertEqual(1, ScheduleLogic.minutesLeft(eviction, at("2026-11-11T17:29:30-07:00")))
        XCTAssertEqual("Live · 20 min left", ScheduleLogic.liveLabel(eviction, at("2026-11-11T17:10:00-07:00"), long: false))
        XCTAssertEqual("On now", ScheduleLogic.liveLabel(eviction, at("2026-11-11T17:10:00-07:00"), long: true))
    }

    func testLiveProgressIsMinutePrecisePercent() {
        let eviction = s("1289660") // 30 min
        XCTAssertEqual(0, ScheduleLogic.liveProgress(eviction, at("2026-11-11T17:00:00-07:00")), accuracy: 0.001)
        XCTAssertEqual(0.5, ScheduleLogic.liveProgress(eviction, at("2026-11-11T17:15:40-07:00")), accuracy: 0.001)
        XCTAssertEqual(0.33, ScheduleLogic.liveProgress(eviction, at("2026-11-11T17:10:00-07:00")), accuracy: 0.001)
    }

    // MARK: - days

    private func keys(_ iso: String) -> [String] { ScheduleLogic.visibleDays(days, at(iso)).map(\.key) }

    func testVisibleDaysHidePastDays() {
        XCTAssertEqual(["sun", "mon", "tue", "wed", "thu"], keys("2026-11-07T12:00:00-07:00")) // before: all
        XCTAssertEqual(["sun", "mon", "tue", "wed", "thu"], keys("2026-11-08T08:00:00-07:00"))
        XCTAssertEqual(["mon", "tue", "wed", "thu"], keys("2026-11-09T00:00:00-07:00"))
        XCTAssertEqual(["tue", "wed", "thu"], keys("2026-11-10T23:59:00-07:00"))
        XCTAssertEqual(["wed", "thu"], keys("2026-11-11T09:00:00-07:00"))
        XCTAssertEqual(["thu"], keys("2026-11-12T20:00:00-07:00"))
        XCTAssertEqual(["sun", "mon", "tue", "wed", "thu"], keys("2026-11-13T09:00:00-07:00")) // after: web shows all
    }

    func testVisibleDaysUseDenverTime() {
        // 2026-11-11T05:30Z is still Tue Nov 10, 10:30 PM in Denver.
        XCTAssertEqual(["tue", "wed", "thu"], keys("2026-11-11T05:30:00Z"))
        XCTAssertEqual("tue", ScheduleLogic.todayKey(days, at("2026-11-11T05:30:00Z")))
    }

    func testTodayAndDefaultDay() {
        XCTAssertEqual("sun", ScheduleLogic.todayKey(days, at("2026-11-08T10:00:00-07:00")))
        XCTAssertEqual("wed", ScheduleLogic.todayKey(days, at("2026-11-11T10:00:00-07:00")))
        XCTAssertNil(ScheduleLogic.todayKey(days, at("2026-11-07T10:00:00-07:00")))
        XCTAssertNil(ScheduleLogic.todayKey(days, at("2026-11-13T10:00:00-07:00")))
        XCTAssertEqual("wed", ScheduleLogic.defaultDayKey(days, at("2026-11-11T10:00:00-07:00")))
        XCTAssertEqual("sun", ScheduleLogic.defaultDayKey(days, at("2026-11-07T10:00:00-07:00")))
        XCTAssertEqual("sun", ScheduleLogic.defaultDayKey(days, at("2026-11-13T10:00:00-07:00")))
    }

    func testResolveDayKeepsAVisibleSelectionAndDropsAStaleOne() {
        let tue = at("2026-11-10T10:00:00-07:00")
        XCTAssertEqual("tue", ScheduleLogic.resolveDayKey(days, tue, nil))
        XCTAssertEqual("thu", ScheduleLogic.resolveDayKey(days, tue, "thu"))
        XCTAssertEqual("tue", ScheduleLogic.resolveDayKey(days, tue, "mon")) // past day: back to today
        XCTAssertEqual("tue", ScheduleLogic.resolveDayKey(days, tue, "nope"))
        // Selected Monday, then midnight passes: the view moves on to the new today.
        XCTAssertEqual("mon", ScheduleLogic.resolveDayKey(days, at("2026-11-09T23:59:00-07:00"), "mon"))
        XCTAssertEqual("tue", ScheduleLogic.resolveDayKey(days, at("2026-11-10T00:00:00-07:00"), "mon"))
    }

    // MARK: - labels

    func testSlotKeysAreHalfHours() {
        XCTAssertEqual(600, ScheduleLogic.slotKey(600))
        XCTAssertEqual(600, ScheduleLogic.slotKey(615))
        XCTAssertEqual(600, ScheduleLogic.slotKey(629))
        XCTAssertEqual(630, ScheduleLogic.slotKey(630))
        XCTAssertEqual(0, ScheduleLogic.slotKey(29))
    }

    func testCountdownLabels() {
        XCTAssertEqual("In 0 min", ScheduleLogic.countdownLabel(0))
        XCTAssertEqual("In 25 min", ScheduleLogic.countdownLabel(25))
        XCTAssertEqual("In 59 min", ScheduleLogic.countdownLabel(59))
        XCTAssertEqual("In 1h", ScheduleLogic.countdownLabel(60))
        XCTAssertEqual("In 1h 45m", ScheduleLogic.countdownLabel(105))
        XCTAssertEqual("In 2h 5m", ScheduleLogic.countdownLabel(125))
    }

    func testClockLabel() {
        XCTAssertEqual("9:05 AM MST", ScheduleLogic.clockLabel(days, at("2026-11-11T09:05:00-07:00")))
        XCTAssertEqual("Times in MST", ScheduleLogic.clockLabel(days, at("2026-11-07T09:05:00-07:00")))
        XCTAssertEqual("Times in MST", ScheduleLogic.clockLabel(days, at("2026-11-13T09:05:00-07:00")))
    }

    func testSpanLabelLikeRange() {
        XCTAssertEqual("9:00–10:30 AM", ScheduleLogic.spanLabel(at("2026-11-11T09:00:00-07:00"), at("2026-11-11T10:30:00-07:00")))
        XCTAssertEqual("11:30 AM–1:00 PM", ScheduleLogic.spanLabel(at("2026-11-11T11:30:00-07:00"), at("2026-11-11T13:00:00-07:00")))
    }

    func testBreakTitleDropsTheEmoji() {
        XCTAssertEqual("Coffee Break", ScheduleLogic.breakTitle("☕ Coffee Break"))
        XCTAssertEqual("Lunch (on your own)", ScheduleLogic.breakTitle("🍲 Lunch (on your own)"))
        XCTAssertEqual("Break: donuts + cinnamon rolls", ScheduleLogic.breakTitle("Break: donuts + cinnamon rolls"))
    }
}
