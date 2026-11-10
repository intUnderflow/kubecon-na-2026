import XCTest
@testable import KCNA26Core

/// Tests of ScheduleScreenLogic+UI.swift: the saved screen state of the SwiftUI Schedule screen
/// (Kotlin `rememberSaveable`) and the agenda scroll-back measured from the card row's top.
final class ScheduleScreenLogicUITests: XCTestCase {
    private let idx = ScheduleIndex.of(TestData.repo)
    private let lucy = "Lucy Sweet"
    private func at(_ iso: String) -> Date { TestData.instant(iso) }

    func testSetsRoundTripThroughTheirSavedText() {
        XCTAssertEqual("", ScheduleScreenLogic.encodeSet([]))
        XCTAssertEqual([], ScheduleScreenLogic.decodeSet(""))
        let set: Set<String> = ["colo-fluxcon", "g-mnt-251", "a \"quoted\" key", "line\nbreak", "José", ""]
        let text = ScheduleScreenLogic.encodeSet(set)
        XCTAssertEqual(set, ScheduleScreenLogic.decodeSet(text))
        // Deterministic (sorted), so an unchanged set writes the same text.
        XCTAssertEqual(text, ScheduleScreenLogic.encodeSet(Set(Array(set).reversed())))
        XCTAssertEqual("[\"a\",\"b\"]", ScheduleScreenLogic.encodeSet(["b", "a"]))
    }

    func testMalformedSavedTextGivesAnEmptySetOrSkipsTheBadMembers() {
        XCTAssertEqual([], ScheduleScreenLogic.decodeSet("not json"))
        XCTAssertEqual([], ScheduleScreenLogic.decodeSet("{\"a\":1}"))
        XCTAssertEqual(["x"], ScheduleScreenLogic.decodeSet("[\"x\", 3, null, [\"y\"]]"))
    }

    func testUnstarredIsRememberedPerFilterStateAndDay() {
        let wedOn = ScheduleScreenLogic.unstarredKey(goingOnly: true, dayKey: "wed")
        let wedOff = ScheduleScreenLogic.unstarredKey(goingOnly: false, dayKey: "wed")
        let thuOn = ScheduleScreenLogic.unstarredKey(goingOnly: true, dayKey: "thu")
        let none = ScheduleScreenLogic.unstarredKey(goingOnly: true, dayKey: nil)
        XCTAssertEqual(4, Set([wedOn, wedOff, thuOn, none]).count)

        var saved = ScheduleScreenLogic.SavedUnstarred.decode("")
        XCTAssertEqual([], saved.ids(for: wedOn))
        // Unstarring with the filter on keeps the session listed (Kotlin onToggleGoing)...
        saved = saved.afterToggle("123", nowGoing: false, goingOnly: true, currentKey: wedOn)
        XCTAssertEqual(["123"], saved.ids(for: wedOn))
        // ...starring it again or toggling with the filter off adds nothing.
        XCTAssertEqual(["123"], saved.afterToggle("456", nowGoing: true, goingOnly: true, currentKey: wedOn).ids(for: wedOn))
        XCTAssertEqual([], saved.afterToggle("456", nowGoing: false, goingOnly: false, currentKey: wedOff).ids(for: wedOff))
        // Another day or filter state sees an empty set, and a toggle there starts afresh.
        XCTAssertEqual([], saved.ids(for: thuOn))
        XCTAssertEqual([], saved.ids(for: wedOff))
        XCTAssertEqual(["9"], saved.afterToggle("9", nowGoing: false, goingOnly: true, currentKey: thuOn).ids(for: thuOn))
        // Saved text round trip.
        let two = saved.afterToggle("456", nowGoing: false, goingOnly: true, currentKey: wedOn)
        XCTAssertEqual(two, ScheduleScreenLogic.SavedUnstarred.decode(two.encoded))
        XCTAssertEqual(["123", "456"], ScheduleScreenLogic.SavedUnstarred.decode(two.encoded).ids(for: wedOn))
        XCTAssertEqual(ScheduleScreenLogic.SavedUnstarred(key: "", ids: []), ScheduleScreenLogic.SavedUnstarred.decode("[1]"))
    }

    func testTheKeyedSetFeedsTheScreenStateLikeKotlinsKeptSessions() throws {
        // A starred Wednesday session unstarred with the filter on stays in the filtered day.
        let now = at("2026-11-11T08:00:00-07:00")
        let full = try XCTUnwrap(idx.dayView("wed", now, nil))
        let first = try XCTUnwrap(full.slots.flatMap(\.blocks).compactMap(\.sessionBlock).first { $0.category != "log" })
        let key = ScheduleScreenLogic.unstarredKey(goingOnly: true, dayKey: "wed")
        let saved = ScheduleScreenLogic.SavedUnstarred(key: "", ids: [])
            .afterToggle(first.session.id, nowGoing: false, goingOnly: true, currentKey: key)
        let kept = ScheduleScreenLogic.state(idx, now, nil, selectedDay: "wed", query: "", goingOnly: true,
                                             goingIds: [], unstarred: saved.ids(for: key), remindMinutes: 10)
        let ids = kept.view?.slots.flatMap(\.blocks).flatMap(\.sessions).map(\.id) ?? []
        XCTAssertTrue(ids.contains(first.session.id))
        // Saved under another day's key: not kept on Wednesday.
        let thuKey = ScheduleScreenLogic.unstarredKey(goingOnly: true, dayKey: "thu")
        let dropped = ScheduleScreenLogic.state(idx, now, nil, selectedDay: "wed", query: "", goingOnly: true,
                                                goingIds: [], unstarred: saved.ids(for: thuKey), remindMinutes: 10)
        XCTAssertFalse((dropped.view?.slots.flatMap(\.blocks).flatMap(\.sessions).map(\.id) ?? []).contains(first.session.id))
    }

    /// The screen's flow for `unstarred` (ScheduleScreen.swift), keyed as Core documents it: by
    /// `goingOnly` and the resolved day (the state's `dayKey`).
    private func keyed(_ now: Date, selectedDay: String?, query: String, _ saved: ScheduleScreenLogic.SavedUnstarred)
        -> (key: String, state: ScheduleScreenLogic.State) {
        let dayKey = ScheduleLogic.resolveDayKey(idx.days, ScheduleLogic.minuteOf(now), selectedDay)
        let key = ScheduleScreenLogic.unstarredKey(goingOnly: true, dayKey: dayKey)
        let st = ScheduleScreenLogic.state(idx, now, nil, selectedDay: selectedDay, query: query, goingOnly: true,
                                           goingIds: [], unstarred: saved.ids(for: key), remindMinutes: 10)
        XCTAssertEqual(dayKey, st.dayKey)
        return (key, st)
    }

    private func resultIds(_ st: ScheduleScreenLogic.State) -> [String] {
        (st.results?.days ?? []).flatMap(\.sessions).map(\.session.id)
    }

    func testUnstarredStartsAfreshWhenTheResolvedDayMovesOnAtMidnight() throws {
        // Kotlin rememberSaveable(goingOnly, dayKey) with dayKey = resolveDayKey(days, minute,
        // selectedDay): Sunday is selected; at midnight Sunday is no longer visible, the day shown
        // moves on to Monday while the stored selection stays "sun", and the set starts empty.
        let query = ScheduleScreenLogic.query("gateway")
        let before = at("2026-11-08T23:59:00-07:00")
        let after = at("2026-11-09T00:00:00-07:00")
        let all = try XCTUnwrap(idx.search(query, ScheduleLogic.minuteOf(before), nil))
        let thu = try XCTUnwrap(all.days.first { $0.day.key == "thu" }?.sessions.first?.session)

        // With the RSVP'd filter on, a Thursday search result unstarred just before midnight stays listed...
        let empty = ScheduleScreenLogic.SavedUnstarred(key: "", ids: [])
        let sun = keyed(before, selectedDay: "sun", query: query, empty)
        XCTAssertEqual("sun", sun.state.dayKey)
        XCTAssertFalse(resultIds(sun.state).contains(thu.id))
        let saved = empty.afterToggle(thu.id, nowGoing: false, goingOnly: true, currentKey: sun.key)
        XCTAssertTrue(resultIds(keyed(before, selectedDay: "sun", query: query, saved).state).contains(thu.id))

        // ...and drops out at midnight, though selectedDay is still "sun".
        let mon = keyed(after, selectedDay: "sun", query: query, saved)
        XCTAssertEqual("mon", mon.state.dayKey)
        XCTAssertNotEqual(sun.key, mon.key)
        XCTAssertEqual([], saved.ids(for: mon.key))
        XCTAssertFalse(resultIds(mon.state).contains(thu.id))
        // A key built from the stored selection would not change, keeping it listed indefinitely.
        XCTAssertEqual(sun.key, ScheduleScreenLogic.unstarredKey(goingOnly: true, dayKey: "sun"))

        // No selection: the default day (today) moves from Tuesday to Wednesday at midnight.
        let tueAt = at("2026-11-10T23:59:00-07:00")
        let tue = keyed(tueAt, selectedDay: nil, query: query, empty)
        XCTAssertEqual("tue", tue.state.dayKey)
        let onTue = empty.afterToggle(thu.id, nowGoing: false, goingOnly: true, currentKey: tue.key)
        XCTAssertTrue(resultIds(keyed(tueAt, selectedDay: nil, query: query, onTue).state).contains(thu.id))
        let wed = keyed(at("2026-11-11T00:00:00-07:00"), selectedDay: nil, query: query, onTue)
        XCTAssertEqual("wed", wed.state.dayKey)
        XCTAssertFalse(resultIds(wed.state).contains(thu.id))
        // A selection that stays visible keeps its set across midnight.
        let thuSel = keyed(tueAt, selectedDay: "thu", query: query, empty)
        let onThu = empty.afterToggle(thu.id, nowGoing: false, goingOnly: true, currentKey: thuSel.key)
        let nextMinute = keyed(at("2026-11-11T00:00:00-07:00"), selectedDay: "thu", query: query, onThu)
        XCTAssertEqual(thuSel.key, nextMinute.key)
        XCTAssertTrue(resultIds(nextMinute.state).contains(thu.id))
    }

    func testHidingAnAgendaScrollsBackOnlyWhenTheCardsTopIsAboveTheViewport() throws {
        let view = try XCTUnwrap(idx.dayView("mon", at("2026-11-09T08:00:00-07:00"), lucy))
        let rows = ScheduleRows.build(view, nil, nil, 1, ["colo-fluxcon"])
        let i = ScheduleRows.indexOfColoCard(rows, "colo-fluxcon")
        XCTAssertTrue(i > 0)
        XCTAssertEqual(i, ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", cardTop: -0.5))
        XCTAssertEqual(i, ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", cardTop: -2_000))
        XCTAssertNil(ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", cardTop: 0))
        XCTAssertNil(ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", cardTop: 140))
        // Never laid out (a jump went straight to the agenda): it is above.
        XCTAssertEqual(i, ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", cardTop: nil))
        XCTAssertNil(ScheduleScreenLogic.hideColoScrollTarget(rows, "nope", cardTop: nil))
        // The same answers as Kotlin's first-visible-row rule for the matching scroll states.
        XCTAssertEqual(ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", firstVisibleIndex: i, firstVisibleOffset: 12),
                       ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", cardTop: -12))
        XCTAssertEqual(ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", firstVisibleIndex: i, firstVisibleOffset: 0),
                       ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", cardTop: 0))
        XCTAssertEqual(ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", firstVisibleIndex: i + 3, firstVisibleOffset: 0),
                       ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", cardTop: -600))
        XCTAssertEqual(ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", firstVisibleIndex: i - 1, firstVisibleOffset: 30),
                       ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", cardTop: 20))
    }
}
