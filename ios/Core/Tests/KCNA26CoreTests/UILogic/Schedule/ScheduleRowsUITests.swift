import XCTest
@testable import KCNA26Core

/// Tests of ScheduleRows+UI.swift: the flat Kotlin LazyColumn rows grouped into the pinned
/// sections of the SwiftUI list.
final class ScheduleRowsUITests: XCTestCase {
    private let idx = ScheduleIndex.of(TestData.repo)
    private let lucy = "Lucy Sweet"
    private func at(_ iso: String) -> Date { TestData.instant(iso) }

    /// Header + rows of every section, in order: the input again.
    private func flatten(_ sections: [ScheduleRowSection]) -> [ScheduleRow] {
        sections.flatMap { s -> [ScheduleRow] in (s.header.map { [$0] } ?? []) + s.rows }
    }

    private func checkInvariants(_ rows: [ScheduleRow], _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let sections = ScheduleRows.sections(rows)
        XCTAssertEqual(rows, flatten(sections), label, file: file, line: line)
        // Only the first section may lack a heading; headings are the sticky rows, rows never are.
        for (i, s) in sections.enumerated() {
            if i > 0 { XCTAssertNotNil(s.header, label, file: file, line: line) }
            if let h = s.header { XCTAssertTrue(h.sticky, label, file: file, line: line) }
            XCTAssertFalse(s.rows.contains { $0.sticky }, label, file: file, line: line)
        }
        // Section ids are unique and never a row key (ScrollViewReader ids share one namespace).
        let ids = sections.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, label, file: file, line: line)
        let rowKeys = Set(sections.flatMap(\.rows).map(\.key))
        XCTAssertTrue(Set(ids).isDisjoint(with: rowKeys), label, file: file, line: line)
    }

    func testEveryDayAndSearchSplitsBackIntoTheSameRows() {
        for d in idx.days {
            for iso in ["2026-11-07T12:00:00-07:00", "2026-11-09T10:20:00-07:00", "2026-11-11T10:20:00-07:00", "2026-11-13T23:00:00-07:00"] {
                let now = at(iso)
                let rows = ScheduleRows.build(idx.dayView(d.key, now, lucy), idx.banner(d.key, now, lucy), nil, 1, ["colo-fluxcon"])
                checkInvariants(rows, "\(d.key) \(iso)")
                let two = ScheduleRows.build(idx.dayView(d.key, now, lucy), nil, nil, 2, ["colo-fluxcon", "colo-argocon"])
                checkInvariants(two, "\(d.key) \(iso) two-up")
            }
        }
        let now = at("2026-11-07T12:00:00-07:00")
        for q in ["kubernetes", "argo", "zzzz-no-match"] {
            checkInvariants(ScheduleRows.build(nil, nil, idx.search(q, now, lucy)), q)
        }
        XCTAssertEqual([], ScheduleRows.sections([]))
    }

    func testTheTopRowsFormAHeaderlessSectionAndEachHeadingKeepsTheRowsUpToTheNext() throws {
        let view = try XCTUnwrap(idx.dayView("wed", at("2026-11-11T10:20:00-07:00"), lucy))
        let rows = ScheduleRows.build(view, nil, nil)
        let sections = ScheduleRows.sections(rows)
        let top = try XCTUnwrap(sections.first)
        XCTAssertNil(top.header)
        XCTAssertEqual(ScheduleRows.TOP_SECTION_ID, top.id)
        XCTAssertEqual(ScheduleRow.search, top.rows.first)
        XCTAssertTrue(top.rows.contains { $0.isDayHead })
        // Mid-morning on the day: the "Up next" line closes the block above it (pinned under
        // that block's heading), and the footer is in the last section.
        let up = try XCTUnwrap(sections.firstIndex { $0.rows.contains(.upNext) })
        XCTAssertEqual(ScheduleRow.upNext, sections[up].rows.last)
        XCTAssertTrue(sections[up].header?.isSlotHead == true)
        XCTAssertTrue(sections[up + 1].header?.isSlotHead == true)
        XCTAssertEqual(ScheduleRow.footer, sections.last?.rows.last)
        // Headings are the slot heads and the named sections, in list order.
        XCTAssertEqual(rows.filter { $0.sticky }.map(\.key), sections.compactMap { $0.header?.key })
        XCTAssertEqual(sections[1].id, sections[1].header?.key)
    }

    func testRowsThatStartWithAHeadingOrHaveEmptySectionsStillRoundTrip() throws {
        let view = try XCTUnwrap(idx.dayView("wed", at("2026-11-11T10:20:00-07:00"), lucy))
        let slots = view.slots.prefix(2).map { ScheduleRow.slotHead($0) }
        XCTAssertEqual(2, slots.count)
        // A heading first: no header-less section.
        let rows: [ScheduleRow] = [slots[0], .footer]
        let s = ScheduleRows.sections(rows)
        XCTAssertEqual(1, s.count)
        XCTAssertEqual(slots[0], s[0].header)
        XCTAssertEqual([ScheduleRow.footer], s[0].rows)
        // Two headings in a row: the first one's section is empty but kept.
        let twice: [ScheduleRow] = [.search, slots[0], slots[1], .upNext]
        let t = ScheduleRows.sections(twice)
        XCTAssertEqual(3, t.count)
        XCTAssertEqual([], t[1].rows)
        XCTAssertEqual(twice, flatten(t))
        // No heading at all: one header-less section.
        let plain = ScheduleRows.sections([.search, .footer])
        XCTAssertEqual(1, plain.count)
        XCTAssertNil(plain[0].header)
        XCTAssertEqual([ScheduleRow.search, .footer], plain[0].rows)
    }
}
