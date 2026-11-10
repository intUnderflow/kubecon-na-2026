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
