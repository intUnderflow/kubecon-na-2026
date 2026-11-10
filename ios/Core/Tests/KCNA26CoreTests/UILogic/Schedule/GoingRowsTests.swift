import XCTest
@testable import KCNA26Core

/// Port of ui/schedule/GoingRowsTest.kt: the "Going" rows: "Up next" beside the speaker banner,
/// the filtered list and its empty state.
final class GoingRowsTests: XCTestCase {
    private let idx = ScheduleIndex.of(TestData.repo)
    private let lucy = "Lucy Sweet"
    private func at(_ iso: String) -> Date { TestData.instant(iso) }
    private let going: Set<String> = ["1251049", "1251218"]

    func testUpNextSitsUnderTheSpeakerBannerOnDaysISpeak() throws {
        let now = at("2026-11-11T14:00")
        let next = GoingLogic.upNext(idx, "wed", going, lucy, now)
        let rows = ScheduleRows.build(idx.dayView("wed", now, lucy), idx.banner("wed", now, lucy), nil, goingNext: next)
        XCTAssertEqual(ScheduleRow.search, rows[0])
        XCTAssertTrue(rows[1].isBanner)
        XCTAssertEqual("1251049", try XCTUnwrap(rows[2].goingNextValue).session.id)
        XCTAssertTrue(rows[3].isDayHead)
        XCTAssertEqual(rows.count, Set(rows.map(\.key)).count)
        XCTAssertEqual(1, rows.count { $0.key == "goingnext" })
    }

    func testUpNextWithoutABannerAndNeverInSearch() {
        let now = at("2026-11-11T14:00")
        let next = GoingLogic.upNext(idx, "wed", going, nil, now)
        let rows = ScheduleRows.build(idx.dayView("wed", now, nil), idx.banner("wed", now, nil), nil, goingNext: next)
        XCTAssertTrue(rows[1].isGoingNext)
        XCTAssertTrue(rows[2].isDayHead)
        let q = ScheduleRows.build(nil, nil, idx.search("gateway", now, nil), goingNext: next)
        XCTAssertTrue(!q.contains { $0.isGoingNext })
    }

    func testTheFilteredDayKeepsStableKeysAndShowsTheGoingEmptyState() throws {
        let now = at("2026-11-11T08:00")
        let full = try XCTUnwrap(idx.dayView("wed", now, nil))
        let ids = going
        let filtered = GoingLogic.filterDay(full, now) { ids.contains($0.id) }
        let all = ScheduleRows.build(full, nil, nil)
        let some = ScheduleRows.build(filtered, nil, nil)
        // Every filtered row is a row of the full list, with the same key (the list keeps its place).
        let allKeys = Set(all.map(\.key))
        XCTAssertTrue(some.allSatisfy { allKeys.contains($0.key) })
        XCTAssertEqual(["s-1251049", "s-1251218"], some.filter { $0.isItem }.map(\.key))

        let none = GoingLogic.filterDay(full, now) { _ in false }
        let (title, text) = try XCTUnwrap(GoingLogic.emptyText(true, full, none, nil, nil, idx, [], now, 10))
        let rows = ScheduleRows.build(none, nil, nil, empty: ScheduleRow.Empty(title, text))
        let empty = try XCTUnwrap(try rows.singleMatch { $0.isEmptyRow }.emptyState)
        XCTAssertEqual("No RSVPs yet", empty.title)
        XCTAssertTrue(!rows.contains { $0.isItem })
    }

    func testTheHowToStarNoteFollowsMyOwnTalks() throws {
        // Lucy, nothing starred, filter on: her three Wednesday talks, then the note, then the footer.
        let now = at("2026-11-11T08:00")
        let full = try XCTUnwrap(idx.dayView("wed", now, lucy))
        let me = lucy
        let mine = GoingLogic.filterDay(full, now) { GoingLogic.keeps($0, [], me) }
        let (title, text) = try XCTUnwrap(GoingLogic.emptyText(true, full, mine, nil, nil, idx, [], now, 10))
        let rows = ScheduleRows.build(mine, idx.banner("wed", now, lucy), nil, empty: ScheduleRow.Empty(title, text))
        // The 9:45 keynote (in the keynotes card), 2:20 in GI and 5:00 in 251 A–C.
        let items = rows.enumerated().filter { $0.element.isItem }
        XCTAssertEqual(3, items.count)
        for id in ["1363905", "1249844", "1289660"] { XCTAssertTrue(ScheduleRows.indexOfSession(rows, id) >= 0, id) }
        let note = try XCTUnwrap(rows.firstIndex { $0.isEmptyRow })
        XCTAssertTrue(note > (try XCTUnwrap(items.last).offset))
        XCTAssertEqual(ScheduleRow.footer, rows[note + 1])
        XCTAssertEqual(rows.count, Set(rows.map(\.key)).count)
        // Search: the note follows the matching talks too.
        let q = ScheduleRows.build(nil, nil, idx.search("Lucy Sweet", now, lucy), empty: ScheduleRow.Empty(title, text))
        XCTAssertTrue((q.firstIndex { $0.isEmptyRow } ?? -1) > (q.lastIndex { $0.isItem } ?? -1))
    }

    func testWithoutAnOverrideTheUsualEmptyStatesStay() throws {
        let now = at("2026-11-08T08:00")
        let rows = ScheduleRows.build(nil, nil, idx.search("zzzzqqq", now, nil))
        XCTAssertEqual(ScheduleRows.NO_MATCHES_TITLE, try rows.singleMatch { $0.isEmptyRow }.emptyState?.title)
        let starred = ScheduleRows.build(nil, nil, idx.search("zzzzqqq", now, nil), empty: ScheduleRow.Empty("No starred matches", "x"))
        XCTAssertEqual("No starred matches", try starred.singleMatch { $0.isEmptyRow }.emptyState?.title)
    }
}
