import XCTest
@testable import KCNA26Core

/// Port of ui/schedule/ScheduleRowsTest.kt.
final class ScheduleRowsTests: XCTestCase {
    private let idx = ScheduleIndex.of(TestData.repo)
    private let lucy = "Lucy Sweet"
    private func at(_ iso: String) -> Date { TestData.instant(iso) }

    private func dayRows(_ day: String, _ iso: String, _ me: String? = "Lucy Sweet") -> [ScheduleRow] {
        let now = at(iso)
        return ScheduleRows.build(idx.dayView(day, now, me), idx.banner(day, now, me), nil)
    }

    private func keySet(_ rows: [ScheduleRow]) -> Set<String> { Set(rows.map(\.key)) }

    func testKeysAreUniqueOnEveryDayAndInSearch() {
        for d in idx.days {
            let rows = dayRows(d.key, "2026-11-07T12:00:00-07:00")
            XCTAssertEqual(rows.count, keySet(rows).count, d.key)
        }
        let now = at("2026-11-07T12:00:00-07:00")
        let q = ScheduleRows.build(nil, nil, idx.search("kubernetes", now, lucy))
        XCTAssertEqual(q.count, keySet(q).count)
    }

    func testWednesdayOrder() {
        let rows = dayRows("wed", "2026-11-11T08:00:00-07:00")
        XCTAssertEqual(ScheduleRow.search, rows[0])
        XCTAssertTrue(rows[1].isBanner)
        XCTAssertTrue(rows[2].isDayHead)
        XCTAssertTrue(rows[3].isSlotHead)
        XCTAssertEqual(ScheduleRow.footer, rows.last)
        // Today before the first block: no "Up next" line ahead of the first block.
        XCTAssertFalse(rows[0..<4].contains(.upNext))
        XCTAssertTrue(!rows.contains { $0.isEmptyRow })
        // Off-site section comes after the blocks (not Monday).
        if let sect = rows.firstIndex(where: { $0.isSection }) {
            XCTAssertTrue(sect > (rows.lastIndex { $0.isSlotHead } ?? -1))
        }
    }

    func testMondayListsCoLocatedFirstAndSundayGoesStraightToTheBlocks() throws {
        let mon = dayRows("mon", "2026-11-09T08:00:00-07:00")
        // Day heading, then the "Co-located events" cards, then the blocks, then the off-site list.
        let head = try XCTUnwrap(mon.firstIndex { $0.isDayHead })
        let sect = try XCTUnwrap(mon.firstIndex { $0.isSection })
        XCTAssertEqual(head + 1, sect)
        XCTAssertEqual("Co-located events", mon[sect].sectionTitle)
        XCTAssertTrue(mon[sect + 1].isColo)
        XCTAssertTrue(try XCTUnwrap(mon.lastIndex { $0.isColo }) < (try XCTUnwrap(mon.firstIndex { $0.isSlotHead })))
        let offSite = try XCTUnwrap(mon.lastIndex { $0.isSection })
        XCTAssertEqual("Sponsor-hosted · off-site", mon[offSite].sectionTitle)
        XCTAssertTrue(offSite > (try XCTUnwrap(mon.lastIndex { $0.isSlotHead })))
        // Sunday (the Summit): no Unconference entry card any more (voting is over); the day
        // heading is followed directly by the first half-hour block, unconference sessions included.
        for at in ["2026-11-08T08:00:00-07:00", "2026-11-08T15:10:00-07:00"] {
            let sun = dayRows("sun", at)
            let head = try XCTUnwrap(sun.firstIndex { $0.isDayHead })
            XCTAssertTrue(sun[head + 1].isSlotHead || sun[head + 1] == .upNext, at)
            XCTAssertTrue(!sun.contains { $0.key == "unconf" }, at)
            XCTAssertEqual(sun.count, sun.map(\.key).distinct().count, at)
        }
    }

    func testUpNextLineSitsBeforeTheBlockAfterNow() throws {
        let rows = dayRows("sun", "2026-11-08T10:05:00-07:00")
        let i = try XCTUnwrap(rows.firstIndex(of: .upNext))
        XCTAssertTrue(i > 0)
        let next = try XCTUnwrap(rows[i + 1].slot)
        XCTAssertEqual("11:00 AM", next.label)
        XCTAssertEqual(1, rows.count { $0 == .upNext })
    }

    func testBreakRowsAndGroupsGetTheirOwnContentTypes() throws {
        let rows = dayRows("wed", "2026-11-11T08:00:00-07:00")
        let items = rows.filter { $0.isItem }
        let group = try XCTUnwrap(items.first { $0.itemBlock?.groupBlock != nil })
        let brk = try XCTUnwrap(items.first { $0.itemBlock?.sessionBlock?.category == "log" })
        let card = try XCTUnwrap(items.first { $0.itemBlock?.sessionBlock?.category == "talk" })
        XCTAssertEqual(Set([7, 8, 9]), Set([group.type, brk.type, card.type]))
    }

    func testWrapAndNoMatches() {
        let wrap = dayRows("sun", "2026-11-08T23:30:00-07:00")
        XCTAssertEqual(["Search", "DayHead", "Empty", "Footer"], wrap.map(\.kind))
        XCTAssertEqual(ScheduleRows.WRAP_TITLE, wrap[2].emptyState?.title)
        let none = ScheduleRows.build(nil, nil, idx.search("zzzz", at("2026-11-08T08:00:00-07:00"), lucy))
        XCTAssertEqual("0 matches", none[1].searchHeading)
        XCTAssertEqual(ScheduleRows.NO_MATCHES_TEXT, none[2].emptyState?.text)
    }

    func testSearchRowsAreGroupedByDayWithIndividualCards() {
        let res = idx.search("lucy", at("2026-11-08T08:00:00-07:00"), lucy)
        let rows = ScheduleRows.build(nil, nil, res)
        XCTAssertEqual(["Wednesday, Nov 11"], rows.compactMap(\.sectionTitle))
        let ids = rows.filter { $0.isItem }.map { $0.itemBlock?.sessionBlock?.session.id }
        XCTAssertEqual(["1363905", "1249844", "1289660"], ids) // keynote shown as its own card in search
        XCTAssertTrue(!rows.contains { $0.isBanner })
    }

    func testCoLocatedCardsOnePerRowOrTwoWithOpenAgendas() throws {
        let now = at("2026-11-09T08:00:00-07:00")
        let view = try XCTUnwrap(idx.dayView("mon", now, lucy))
        let all = Set(view.colo.map(\.key))
        XCTAssertEqual(11, all.count)
        for columns in [1, 2] {
            for open in [Set<String>(), ["colo-argocon"], all] {
                let rows = ScheduleRows.build(view, nil, nil, columns, open)
                // Keys stay unique with ~230 more sessions and every card open.
                XCTAssertEqual(rows.count, keySet(rows).count, "\(columns) \(open)")
                let colo = rows.compactMap(\.coloCards)
                XCTAssertEqual(columns == 1 ? 11 : 6, colo.count)
                XCTAssertTrue(colo.allSatisfy { $0.count <= columns })
                // A row is keyed by its leading card, so the key survives a re-chunk (a card leaving, fold/unfold).
                XCTAssertTrue(rows.filter { $0.isColo }.allSatisfy { $0.key == "colo-" + ($0.coloCards?.first?.key ?? "?") })
                XCTAssertEqual(view.colo.map(\.key), colo.flatMap { $0.map(\.key) }) // alphabetical, in reading order
                let agendas = rows.filter { $0.isColoAgenda }
                XCTAssertEqual(open, Set(agendas.compactMap { $0.agenda?.card.key }))
                XCTAssertTrue(agendas.allSatisfy { $0.agenda?.attached == (columns == 1) })
                // Each open agenda sits right after its card's row (or its pair's other agenda).
                for a in agendas {
                    let i = try XCTUnwrap(rows.firstIndex(of: a))
                    let key = try XCTUnwrap(a.agenda?.card.key)
                    let owner = try XCTUnwrap(rows.firstIndex { $0.coloCards?.contains { c in c.key == key } == true })
                    XCTAssertTrue(i > owner)
                    XCTAssertTrue(rows[(owner + 1)..<i].allSatisfy { $0.isColoAgenda })
                }
            }
        }
        // Search shows co-located talks as ordinary cards (with the event name as eyebrow), no event cards.
        let q = ScheduleRows.build(nil, nil, idx.search("argocon", now, lucy), 2, all)
        XCTAssertTrue(!q.contains { $0.isColo || $0.isColoAgenda })
        XCTAssertEqual(q.count, keySet(q).count)
    }

    func testJumpTargetsFindCoLocatedTalks() throws {
        let now = at("2026-11-09T08:00:00-07:00")
        let view = try XCTUnwrap(idx.dayView("mon", now, "Katie Lamkin-Fulsher"))
        // Collapsed: the event's card. Open: the agenda row holding it.
        let closed = ScheduleRows.build(view, nil, nil, 1, [])
        let i = ScheduleRows.indexOfSession(closed, "1312052")
        let cards = try XCTUnwrap(closed[i].coloCards)
        XCTAssertEqual(1, cards.count)
        XCTAssertEqual("colo-argocon", cards.first?.key)
        let opened = ScheduleRows.build(view, nil, nil, 2, ["colo-argocon"])
        let j = ScheduleRows.indexOfSession(opened, "1312052")
        XCTAssertEqual("colo-argocon", try XCTUnwrap(opened[j].agenda).card.key)
    }

    func testABannerJumpToACoLocatedTalkWaitsForItsOpenAgenda() throws {
        // The banner tap opens the card and sends the jump in the same frame, so the jump's first look
        // is at the old rows, where the card is still collapsed. Settling on the card there (as
        // indexOfSession would) lands on the card head and never reveals the talk further down.
        let katie = "Katie Lamkin-Fulsher"
        let now = at("2026-11-09T08:00:00-07:00")
        let view = try XCTUnwrap(idx.dayView("mon", now, katie))
        let banner = try XCTUnwrap(idx.banner("mon", now, katie))
        let closing = "1312052" // ArgoCon closing remarks, 5:40 PM: far down a ~30-row agenda
        for columns in 1...2 {
            let closed = ScheduleRows.build(view, banner, nil, columns, [])
            XCTAssertTrue(closed[ScheduleRows.indexOfSession(closed, closing)].isColo) // the old, wrong target
            XCTAssertEqual(-1, ScheduleRows.jumpIndex(closed, closing, "colo-argocon")) // keep waiting
            let open: Set<String> = ["colo-argocon"]
            let opened = ScheduleRows.build(view, banner, nil, columns, open)
            let j = ScheduleRows.jumpIndex(opened, closing, "colo-argocon")
            XCTAssertEqual("colo-argocon", try XCTUnwrap(opened[j].agenda).card.key)
            XCTAssertTrue(ScheduleRows.revealsAfterJump(opened[j], closing, open))
            // The timeout fallback (the card head) still reveals the talk once its agenda is composed.
            let card = ScheduleRows.indexOfColoCard(opened, "colo-argocon")
            XCTAssertTrue(ScheduleRows.revealsAfterJump(opened[card], closing, open))
            XCTAssertFalse(ScheduleRows.revealsAfterJump(opened[card], closing, []))
        }
        // Anything else jumps as before: no agenda to wait for.
        let wed = dayRows("wed", "2026-11-11T08:00:00-07:00")
        XCTAssertEqual(ScheduleRows.indexOfSession(wed, "1249844"), ScheduleRows.jumpIndex(wed, "1249844", nil))
        let keynote = ScheduleRows.jumpIndex(wed, "1363905", nil)
        XCTAssertTrue(ScheduleRows.revealsAfterJump(wed[keynote], "1363905", [])) // inside a group card
        let own = ScheduleRows.jumpIndex(wed, "1249844", nil)
        XCTAssertFalse(ScheduleRows.revealsAfterJump(wed[own], "1249844", [])) // its own card
    }

    func testCoLocatedRowKeysSurviveACardLeaving() {
        // CiliumCon's card goes at 12:30. Every row that still starts with the same card keeps its key.
        for columns in 1...2 {
            func keys(_ iso: String) -> OrderedMap<String, String> {
                ScheduleRows.build(idx.dayView("mon", at(iso), lucy), nil, nil, columns)
                    .filter { $0.isColo }
                    .associate { ($0.coloCards?.first?.key ?? "", $0.key) }
            }
            let before = keys("2026-11-09T12:29:00-07:00")
            let after = keys("2026-11-09T12:30:00-07:00")
            XCTAssertEqual(before.count - 1, after.count) // 11 → 10 rows, or 6 → 5 pairs
            for (lead, key) in after where before.containsKey(lead) {
                XCTAssertEqual(before[lead], key)
            }
        }
    }

    func testCoLocatedCardsGoTwoUpOnlyInAWideListColumn() {
        // The cover screen's list (443 dp, 411 dp of content) and the unfolded list–detail pane
        // (852 dp × 0.47 = 400 dp, 368 dp of content) both get one card per row.
        XCTAssertEqual(1, ScheduleRows.coloColumns(411))
        XCTAssertEqual(1, ScheduleRows.coloColumns(368))
        XCTAssertEqual(1, ScheduleRows.coloColumns(559))
        XCTAssertEqual(2, ScheduleRows.coloColumns(560))
        XCTAssertEqual(2, ScheduleRows.coloColumns(728))
    }

    func testHidingAnAgendaFindsItsCard() throws {
        let view = try XCTUnwrap(idx.dayView("mon", at("2026-11-09T08:00:00-07:00"), lucy))
        for columns in 1...2 {
            let rows = ScheduleRows.build(view, nil, nil, columns, ["colo-fluxcon"])
            let i = ScheduleRows.indexOfColoCard(rows, "colo-fluxcon")
            XCTAssertTrue(try XCTUnwrap(rows[i].coloCards).contains { $0.key == "colo-fluxcon" })
            XCTAssertTrue(rows[i + 1].isColoAgenda) // the agenda right under it
            // Collapsing doesn't move the card: same index without the agenda.
            XCTAssertEqual(i, ScheduleRows.indexOfColoCard(ScheduleRows.build(view, nil, nil, columns), "colo-fluxcon"))
        }
        XCTAssertEqual(-1, ScheduleRows.indexOfColoCard(ScheduleRows.build(view, nil, nil), "nope"))
    }

    func testJumpTargetsFindCardsAndGroups() throws {
        let rows = dayRows("wed", "2026-11-11T08:00:00-07:00")
        let keynote = ScheduleRows.indexOfSession(rows, "1363905")
        XCTAssertNotNil(try XCTUnwrap(rows[keynote].itemBlock).groupBlock)
        let gi = ScheduleRows.indexOfSession(rows, "1249844")
        XCTAssertEqual("1249844", try XCTUnwrap(rows[gi].itemBlock?.sessionBlock).session.id)
        XCTAssertEqual(-1, ScheduleRows.indexOfSession(rows, "nope"))
    }
}
