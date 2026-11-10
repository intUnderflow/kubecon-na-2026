import XCTest
@testable import KCNA26Core

/// Tests of the helpers extracted from the Kotlin schedule / Going composables (no Kotlin test of
/// their own: ScheduleScreen.kt, ScheduleCards.kt, ColocatedCards.kt, ScheduleHeader.kt,
/// GoingUi.kt, WidthClass.kt), checked against the Kotlin expressions they replace.
final class ScheduleUiLogicTests: XCTestCase {
    private let repo = TestData.repo
    private let idx = ScheduleIndex.of(TestData.repo)
    private let lucy = "Lucy Sweet"
    private let katie = "Katie Lamkin-Fulsher"
    private func at(_ iso: String) -> Date { TestData.instant(iso) }
    private func s(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> Session {
        try XCTUnwrap(repo.session(id), "no session \(id)", file: file, line: line)
    }

    /// The session block for `id` in `view`'s half-hour blocks.
    private func block(_ id: String, _ view: DayView, file: StaticString = #filePath, line: UInt = #line) throws -> SessionBlock {
        let b = view.slots.flatMap(\.blocks).compactMap(\.sessionBlock).first { $0.session.id == id }
        return try XCTUnwrap(b, "no block \(id)", file: file, line: line)
    }

    private func groupBlock(_ key: String, _ view: DayView, file: StaticString = #filePath, line: UInt = #line) throws -> GroupBlock {
        let g = view.slots.flatMap(\.blocks).compactMap(\.groupBlock).first { $0.group.key == key }
        return try XCTUnwrap(g, "no group \(key)", file: file, line: line)
    }

    // MARK: - ScheduleScreenLogic

    func testScreenStateIsTheKotlinRememberChain() throws {
        let going: Set<String> = ["1251049", "1251218"]
        let now = at("2026-11-11T14:00:30-07:00")
        let st = ScheduleScreenLogic.state(idx, now, lucy, selectedDay: nil, query: "", goingOnly: false, goingIds: going, unstarred: [], remindMinutes: 10)
        let minute = at("2026-11-11T14:00:00-07:00")
        XCTAssertEqual(minute, st.minute)
        XCTAssertFalse(st.searching)
        XCTAssertEqual("wed", st.dayKey)
        XCTAssertEqual("2:00 PM MST", st.clock)
        XCTAssertEqual(idx.dayTabs(minute, lucy), st.tabs)
        XCTAssertEqual(idx.dayView("wed", minute, lucy), st.fullView)
        XCTAssertEqual(st.fullView, st.view)
        XCTAssertEqual(idx.banner("wed", minute, lucy), st.banner)
        XCTAssertNil(st.allResults)
        XCTAssertEqual("1251049", st.goingNext?.session.id)
        // Both starred sessions overlap one of Lucy's talks.
        XCTAssertEqual(Set(GoingLogic.clashes(idx, going, lucy, minute).keys), st.clashIds)
        XCTAssertTrue(st.clashIds.isSuperset(of: going))
        XCTAssertNil(st.goingEmpty)
        let rows = st.rows(1, [])
        XCTAssertEqual(ScheduleRows.build(st.view, st.banner, nil, 1, [], goingNext: st.goingNext), rows)
        XCTAssertTrue(rows[2].isGoingNext)

        // Searching: no day, banner or "Up next"; the results instead.
        let q = ScheduleScreenLogic.state(idx, now, lucy, selectedDay: "thu", query: ScheduleScreenLogic.query("  gateway "), goingOnly: false, goingIds: going, unstarred: [], remindMinutes: 10)
        XCTAssertTrue(q.searching)
        XCTAssertEqual("thu", q.dayKey)
        XCTAssertNil(q.fullView)
        XCTAssertNil(q.banner)
        XCTAssertNil(q.goingNext)
        XCTAssertEqual(idx.search("gateway", minute, lucy), q.results)
        XCTAssertEqual(q.allResults, q.results)

        // The RSVP'd filter with nothing starred: the "No RSVPs yet" note replaces the day.
        let none = ScheduleScreenLogic.state(idx, now, nil, selectedDay: nil, query: "", goingOnly: true, goingIds: [], unstarred: [], remindMinutes: 10)
        XCTAssertEqual(GoingText.NONE_TITLE, none.goingEmpty?.title)
        XCTAssertTrue(none.view?.slots.isEmpty == true)
        XCTAssertTrue(!none.rows(1, []).contains { $0.isItem })
    }

    func testTheFilterKeepsAnUnstarredSessionUntilItChanges() throws {
        let keep = ScheduleScreenLogic.keepGoing(["1251049"], lucy, ["1251218"])
        XCTAssertTrue(keep(try s("1251049"))) // starred
        XCTAssertTrue(keep(try s("1251218"))) // just unstarred: stays listed
        XCTAssertTrue(keep(try s("1289660"))) // mine
        XCTAssertFalse(keep(try s("1240105")))
        // GoingStore.toggle returned false (unstarred) with the filter on: remembered; otherwise not.
        XCTAssertEqual(["a", "b"], ScheduleScreenLogic.unstarredAfterToggle(["a"], "b", nowGoing: false, goingOnly: true))
        XCTAssertEqual(["a"], ScheduleScreenLogic.unstarredAfterToggle(["a"], "b", nowGoing: true, goingOnly: true))
        XCTAssertEqual(["a"], ScheduleScreenLogic.unstarredAfterToggle(["a"], "b", nowGoing: false, goingOnly: false))
        let st = ScheduleScreenLogic.state(idx, at("2026-11-11T08:00:00-07:00"), nil, selectedDay: nil, query: "", goingOnly: true, goingIds: ["1251049"], unstarred: ["1251218"], remindMinutes: 10)
        XCTAssertEqual(["s-1251049", "s-1251218"], st.rows(1, []).filter { $0.isItem }.map(\.key))
    }

    func testATalkTapOpensItsCoLocatedCardAndSendsTheJump() throws {
        let closing = try s("1312052") // ArgoCon closing remarks
        let tap = ScheduleScreenLogic.onTalk(idx, closing, ["colo-fluxcon"])
        XCTAssertEqual("mon", tap.selectedDay)
        XCTAssertEqual(["colo-fluxcon", "colo-argocon"], tap.coloOpen)
        XCTAssertEqual(ScheduleScreenLogic.Jump("1312052", "colo-argocon"), tap.jump)
        let own = ScheduleScreenLogic.onTalk(idx, try s("1249844"), [])
        XCTAssertEqual("wed", own.selectedDay)
        XCTAssertEqual([], own.coloOpen)
        XCTAssertNil(own.jump.agenda)

        // The jump waits for the agenda (nil on the old rows), else falls back to the card.
        let now = at("2026-11-09T08:00:00-07:00")
        let view = try XCTUnwrap(idx.dayView("mon", now, katie))
        let closed = ScheduleRows.build(view, nil, nil, 1, [])
        XCTAssertNil(ScheduleScreenLogic.jumpTarget(closed, tap.jump))
        let fallback = try XCTUnwrap(ScheduleScreenLogic.jumpFallback(closed, tap.jump))
        XCTAssertTrue(closed[fallback].isColo)
        let opened = ScheduleRows.build(view, nil, nil, 1, tap.coloOpen)
        let target = try XCTUnwrap(ScheduleScreenLogic.jumpTarget(opened, tap.jump))
        XCTAssertTrue(opened[target].isColoAgenda)
        XCTAssertNil(ScheduleScreenLogic.jumpFallback(opened, ScheduleScreenLogic.Jump("nope", nil)))
    }

    func testColoTogglesAndHidingScrollsBackToTheCardOnlyWhenItsHeadIsAbove() throws {
        XCTAssertEqual(["a", "b"], ScheduleScreenLogic.toggleColo(["a"], "b"))
        XCTAssertEqual([], ScheduleScreenLogic.toggleColo(["b"], "b"))
        let view = try XCTUnwrap(idx.dayView("mon", at("2026-11-09T08:00:00-07:00"), lucy))
        let rows = ScheduleRows.build(view, nil, nil, 1, ["colo-fluxcon"])
        let i = ScheduleRows.indexOfColoCard(rows, "colo-fluxcon")
        XCTAssertEqual(i, ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", firstVisibleIndex: i + 5, firstVisibleOffset: 0))
        XCTAssertEqual(i, ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", firstVisibleIndex: i, firstVisibleOffset: 12))
        XCTAssertNil(ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", firstVisibleIndex: i, firstVisibleOffset: 0))
        XCTAssertNil(ScheduleScreenLogic.hideColoScrollTarget(rows, "colo-fluxcon", firstVisibleIndex: i - 1, firstVisibleOffset: 30))
        XCTAssertNil(ScheduleScreenLogic.hideColoScrollTarget(rows, "nope", firstVisibleIndex: 50, firstVisibleOffset: 0))
    }

    func testListLayoutFollowsTheBoxWithConstraintsRules() {
        // An iPhone in portrait: 16 pt margins, one co-located card per row.
        XCTAssertEqual(
            ScheduleScreenLogic.ListLayout(side: 16, roomy: false, large: false, coloColumns: 1),
            ScheduleScreenLogic.listLayout(393, twoPane: false, wideWindow: false)
        )
        // A landscape iPad: one centred 760 pt column, wide cards, large headings, two cards per row.
        XCTAssertEqual(
            ScheduleScreenLogic.ListLayout(side: 132, roomy: true, large: true, coloColumns: 2),
            ScheduleScreenLogic.listLayout(1024, twoPane: false, wideWindow: true)
        )
        // The list pane of the list–detail layout is never roomy.
        XCTAssertEqual(
            ScheduleScreenLogic.ListLayout(side: 16, roomy: false, large: false, coloColumns: 1),
            ScheduleScreenLogic.listLayout(400, twoPane: true, wideWindow: true)
        )
        // 640 pt, compact window: roomy, not large; 608 pt of content: two cards.
        XCTAssertEqual(
            ScheduleScreenLogic.ListLayout(side: 16, roomy: true, large: false, coloColumns: 2),
            ScheduleScreenLogic.listLayout(640, twoPane: false, wideWindow: false)
        )
        XCTAssertEqual("x", ScheduleScreenLogic.highlight(twoPane: true, "x"))
        XCTAssertNil(ScheduleScreenLogic.highlight(twoPane: false, "x"))
    }

    func testTheUpNextRowShowsTheHintOnlyBeforeAnRsvpReminder() throws {
        let next = try XCTUnwrap(GoingLogic.upNext(idx, "wed", ["1251049"], nil, at("2026-11-11T14:00:00-07:00")))
        XCTAssertFalse(next.live)
        XCTAssertTrue(ScheduleScreenLogic.goingNextShowsHint(next, 10))
        XCTAssertFalse(ScheduleScreenLogic.goingNextShowsHint(next, 0))
        let live = try XCTUnwrap(GoingLogic.upNext(idx, "wed", ["1251049"], nil, at("2026-11-11T14:25:00-07:00")))
        XCTAssertTrue(live.live)
        XCTAssertFalse(ScheduleScreenLogic.goingNextShowsHint(live, 10))
    }

    // MARK: - ScheduleCardsLogic

    func testSessionCardColoursFollowTheKotlinPrecedence() {
        typealias L = ScheduleCardsLogic
        let mine = L.sessionCardColors("talk", mine: true, anthropic: false, going: true, live: true)
        XCTAssertEqual([PaletteRole.you, .you, .you, .onYou, .onYou, .onYou, .onYou], [mine.fill, mine.border, mine.stripe, mine.ink, mine.muted, mine.label, mine.progress])
        XCTAssertEqual(0.6, mine.tagBorderAlpha)
        XCTAssertEqual([PaletteRole.onYou, .you], [mine.livePill, mine.livePillText])
        let ant = L.sessionCardColors("talk", mine: false, anthropic: true, going: false, live: true)
        XCTAssertEqual([PaletteRole.anthropicCardBg, .anthropicCardBorder, .anthropic], [ant.fill, ant.border, ant.stripe])
        XCTAssertEqual(.goingCardBorder, L.sessionCardColors("talk", mine: false, anthropic: true, going: true, live: false).border)
        let going = L.sessionCardColors("mnt", mine: false, anthropic: false, going: true, live: false)
        XCTAssertEqual([PaletteRole.goingCardBg, .goingCardBorder, .category("mnt")], [going.fill, going.border, going.stripe])
        XCTAssertEqual(.liveBorder, L.sessionCardColors("mnt", mine: false, anthropic: false, going: true, live: true).border)
        let live = L.sessionCardColors("mnt", mine: false, anthropic: false, going: false, live: true)
        XCTAssertEqual([PaletteRole.surface, .liveBorder, .category("mnt"), .ink, .muted, .category("mnt"), .you], [live.fill, live.border, live.stripe, live.ink, live.muted, live.label, live.progress])
        let plain = L.sessionCardColors("mnt", mine: false, anthropic: false, going: false, live: false)
        XCTAssertEqual([PaletteRole.surface, .line, .line, .note], [plain.fill, plain.border, plain.tagBorder, plain.note])
    }

    func testSessionCardModels() throws {
        let now = at("2026-11-11T14:25:00-07:00")
        let view = try XCTUnwrap(idx.dayView("wed", now, lucy))
        let mineBlock = try block("1249844", view) // Lucy's 2:20 in GI
        let mine = ScheduleCardsLogic.sessionCard(mineBlock, idx.cardStatus(mineBlock.session, now), idx)
        XCTAssertTrue(mine.mine)
        XCTAssertEqual("Live · 25 min left", mine.livePill)
        XCTAssertEqual("2:20–2:50 PM", mine.time)
        XCTAssertEqual("30 min", mine.duration)
        XCTAssertEqual("Grand Ballroom GI", mine.roomName)
        XCTAssertEqual("Salt Palace L1", mine.building)
        XCTAssertEqual(idx.categoryLabel(mineBlock.category), mine.label)
        XCTAssertEqual(.you, mine.colors.fill)
        let rb = try block("1251049", view)
        let starred = ScheduleCardsLogic.sessionCard(rb, idx.cardStatus(rb.session, now), idx, going: true, clash: true)
        XCTAssertTrue(starred.going && starred.clash)
        XCTAssertEqual(.liveBorder, starred.colors.border)
        XCTAssertEqual(.goingCardBg, starred.colors.fill)
        XCTAssertNotNil(starred.progress)
        let later = ScheduleCardsLogic.sessionCard(rb, .NotLive, idx)
        XCTAssertNil(later.livePill)
        XCTAssertNil(later.progress)
        XCTAssertEqual(.line, later.colors.border)

        // Co-located talks in search results: the event's name as the eyebrow.
        let res = idx.search("argocon", at("2026-11-09T08:00:00-07:00"), lucy)
        let colo = try XCTUnwrap(res.days.flatMap(\.sessions).first { $0.session.isColocated && $0.category != "log" })
        XCTAssertEqual(idx.coloEventOf(colo.session)?.name, ScheduleCardsLogic.sessionCardLabel(idx, colo))
        // Summit tags (not "Keynote") and KubeCon notes.
        XCTAssertEqual("Main Track", ScheduleCardsLogic.sessionCardTag(try s("m1290687")))
        XCTAssertNil(ScheduleCardsLogic.sessionCardTag(try s("m1318410")))
        XCTAssertNil(ScheduleCardsLogic.whereLineNote(try s("m1290687")))
        XCTAssertEqual("Sold out", ScheduleCardsLogic.whereLineNote(try s("1344383")))
        // Break rows: no emoji.
        let brk = ScheduleCardsLogic.breakRow(try s("1289742"), idx)
        XCTAssertEqual("Coffee Break", brk.title)
        XCTAssertEqual(idx.roomName("SHOW"), brk.room)
        XCTAssertEqual("10:30–11:00 AM", brk.time)
    }

    func testGroupCardsCollapseOverTwelveUnlessMineRevealedOrSelected() throws {
        let now = at("2026-11-11T08:00:00-07:00")
        let view = try XCTUnwrap(idx.dayView("wed", now, nil))
        let keynotes = try groupBlock("wed-key", view)
        XCTAssertEqual(13, keynotes.kids.count)
        let collapsed = ScheduleCardsLogic.groupCard(keynotes, now, nil, idx, expanded: false, selectedId: nil, revealId: nil)
        XCTAssertFalse(collapsed.showAll)
        XCTAssertEqual(6, collapsed.kids.count)
        XCTAssertEqual("Show all 13", collapsed.showAllLabel)
        XCTAssertEqual("13 sessions", collapsed.count)
        XCTAssertEqual(ScheduleLogic.spanLabel(keynotes.start, try XCTUnwrap(keynotes.kids.map(\.effectiveEnd).max())), collapsed.span)
        XCTAssertNil(collapsed.starred)
        XCTAssertFalse(collapsed.anyLive)
        XCTAssertEqual(.line, collapsed.border)
        // The last shown row has no divider; every other (not mine) has one.
        XCTAssertEqual(Array(repeating: true, count: 5) + [false], collapsed.kids.map(\.divider))
        let last = try XCTUnwrap(keynotes.kids.last).id
        for open in [
            ScheduleCardsLogic.groupCard(keynotes, now, nil, idx, expanded: true, selectedId: nil, revealId: nil),
            ScheduleCardsLogic.groupCard(keynotes, now, lucy, idx, expanded: false, selectedId: nil, revealId: nil), // her keynote
            ScheduleCardsLogic.groupCard(keynotes, now, nil, idx, expanded: false, selectedId: last, revealId: nil),
            ScheduleCardsLogic.groupCard(keynotes, now, nil, idx, expanded: false, selectedId: nil, revealId: last),
        ] {
            XCTAssertTrue(open.showAll)
            XCTAssertEqual(13, open.kids.count)
            XCTAssertNil(open.showAllLabel)
        }
        // Lucy's own keynote row: pink, "You" pill, no divider; the starred one gets the rule.
        let starredId = try XCTUnwrap(keynotes.kids.first { !isMine($0, lucy) }).id
        let asLucy = ScheduleCardsLogic.groupCard(keynotes, now, lucy, idx, expanded: false, selectedId: "1363905", revealId: nil, goingIds: [starredId], clashIds: [starredId])
        let lucyRow = try asLucy.kids.singleMatch { $0.session.id == "1363905" }
        XCTAssertTrue(lucyRow.mine && lucyRow.selected && !lucyRow.anthropic && !lucyRow.divider)
        XCTAssertEqual(.you, lucyRow.pill)
        XCTAssertEqual(.you, lucyRow.background)
        XCTAssertEqual(.onYou, lucyRow.timeColor)
        let starredRow = try asLucy.kids.singleMatch { $0.session.id == starredId }
        XCTAssertTrue(starredRow.going && starredRow.clash && starredRow.goingRule)
        XCTAssertEqual("RSVP’d to 1 of these", asLucy.starred)
        // With me = None, Lucy's keynote is an Anthropic row.
        let asNone = ScheduleCardsLogic.groupCard(keynotes, now, nil, idx, expanded: true, selectedId: nil, revealId: nil)
        let ant = try asNone.kids.singleMatch { $0.session.id == "1363905" }
        XCTAssertTrue(ant.anthropic && !ant.mine)
        XCTAssertEqual(.ant, ant.pill)
        XCTAssertEqual(.anthropicRowBg, ant.background)
        XCTAssertEqual(TimeFormat.hm(ant.session.start), ant.time)
    }

    func testKidPillsAndDividers() {
        typealias L = ScheduleCardsLogic
        XCTAssertEqual(.you, L.kidRowPill(mine: true, anthropic: true, live: true))
        XCTAssertEqual(.ant, L.kidRowPill(mine: false, anthropic: true, live: true))
        XCTAssertEqual(.live, L.kidRowPill(mine: false, anthropic: false, live: true))
        XCTAssertNil(L.kidRowPill(mine: false, anthropic: false, live: false))
        XCTAssertEqual(["You", "Anthropic", "Live", "Clash"], L.KidPill.allCases.map(\.label))
        XCTAssertTrue(L.kidRowDivider(mine: false, 0, 2))
        XCTAssertFalse(L.kidRowDivider(mine: false, 1, 2))
        XCTAssertFalse(L.kidRowDivider(mine: true, 0, 2))
        XCTAssertEqual("1 session", L.sessionsCount(1))
        XCTAssertEqual("2 sessions", L.sessionsCount(2))
        XCTAssertTrue(L.groupCardShowsAll(Array(repeating: TestData.repo.sessions[0], count: 12), expanded: false, anyMine: false, revealId: nil, selectedId: nil))
        XCTAssertFalse(L.groupCardShowsAll(Array(repeating: TestData.repo.sessions[0], count: 13), expanded: false, anyMine: false, revealId: "x", selectedId: "y"))
    }

    // MARK: - ColocatedCardsLogic

    func testColoCardRowsAndTheirTiles() throws {
        let view = try XCTUnwrap(idx.dayView("mon", at("2026-11-09T08:00:00-07:00"), lucy))
        let a = view.colo[0]
        let b = view.colo[1]
        let one = ColocatedCardsLogic.cardRow([a], 1, [a.key])
        XCTAssertEqual(0, one.spacers)
        let t = try one.tiles.singleMatch { _ in true }
        XCTAssertTrue(t.open && !t.tile && t.attachedBelow)
        XCTAssertNil(t.ring)
        XCTAssertEqual(0, t.bottomGap)
        XCTAssertEqual(Dimens.cardGap, ColocatedCardsLogic.cardRow([a], 1, []).tiles[0].bottomGap)
        let two = ColocatedCardsLogic.cardRow([a, b], 2, [b.key])
        XCTAssertEqual(0, two.spacers)
        XCTAssertEqual([false, true], two.tiles.map(\.open))
        XCTAssertTrue(two.tiles.allSatisfy { $0.tile && !$0.attachedBelow })
        XCTAssertEqual([nil, PaletteRole.category("colo")], two.tiles.map(\.ring))
        XCTAssertEqual(1, ColocatedCardsLogic.cardRow([a], 2, []).spacers)
        XCTAssertEqual(.line, ColocatedCardsLogic.border(a))
        XCTAssertEqual("Hide the ArgoCon agenda", ColocatedCardsLogic.hideAgendaLabel("ArgoCon"))
        XCTAssertEqual(["Agenda shown", "Agenda hidden"], [ColocatedCardsLogic.agendaState(true), ColocatedCardsLogic.agendaState(false)])
        XCTAssertEqual(["Hide agenda", "Show agenda"], [ColocatedCardsLogic.toggleHint(true), ColocatedCardsLogic.toggleHint(false)])
    }

    func testColoCardTexts() throws {
        let argo = try XCTUnwrap(repo.coloEvent("colo-argocon"))
        XCTAssertEqual(
            [TextRun("Room 151", bold: true, role: .ink), TextRun("  Salt\u{00A0}Palace\u{00A0}L1")],
            ColocatedCardsLogic.roomLine(idx, argo)
        )
        let cilium = try XCTUnwrap(repo.coloEvent("colo-ciliumcon"))
        let pieces = ColocatedCardsLogic.hoursPieces(cilium)
        XCTAssertEqual(2, pieces.count)
        XCTAssertTrue(pieces[0].hasSuffix(" ·"))
        XCTAssertEqual(ColoText.hours(cilium), pieces.joined(separator: " "))
        XCTAssertEqual([ColoText.hours(argo)], ColocatedCardsLogic.hoursPieces(argo))

        let s0 = repo.sessions[0]
        XCTAssertEqual(2, ColocatedCardsLogic.lineMaxLines(0, .now(ColoLine.Now(s0, 3, nil)), tile: false))
        XCTAssertEqual(1, ColocatedCardsLogic.lineMaxLines(1, .next(ColoLine.Next(s0, nil, nil)), tile: false))
        XCTAssertEqual(2, ColocatedCardsLogic.lineMaxLines(1, .next(ColoLine.Next(s0, nil, nil)), tile: true))
        XCTAssertEqual(2, ColocatedCardsLogic.lineMaxLines(0, .next(ColoLine.Next(s0, nil, nil)), tile: false))
        XCTAssertEqual(3, ColocatedCardsLogic.lineMaxLines(1, .now(ColoLine.Now(s0, 3, nil)), tile: true))

        // Before the day starts every card says "Starts …": muted label, ink title.
        let card = idx.coloCard(argo, at("2026-11-09T08:00:00-07:00"), lucy)
        let line = try XCTUnwrap(card.lines.first)
        let runs = ColocatedCardsLogic.lineText(line, idx)
        XCTAssertEqual(ColoText.label(line, idx.roomName).caps(), runs[0].text)
        XCTAssertEqual(.muted, runs[0].role)
        XCTAssertFalse(runs[0].bold)
        if let talk = line.session {
            XCTAssertEqual(ColoText.label(line, idx.roomName).caps() + " · " + talk.title, runs.plainText)
            XCTAssertEqual(.ink, runs.last?.role)
        }
        XCTAssertEqual(.muted, ColocatedCardsLogic.lineColor(line))
        // During a talk: pink "NOW · …".
        let live = idx.coloCard(argo, at("2026-11-09T10:05:00-07:00"), lucy)
        if let now = live.lines.first(where: { $0.asNow != nil }) {
            let nowRuns = ColocatedCardsLogic.lineText(now, idx)
            XCTAssertTrue(nowRuns[0].bold)
            XCTAssertEqual(.you, nowRuns[0].role)
            XCTAssertEqual(.you, ColocatedCardsLogic.lineColor(now))
        } else {
            XCTFail("ArgoCon has a talk on at 10:05")
        }

        let footer = try XCTUnwrap(ColocatedCardsLogic.footer(argo))
        XCTAssertEqual("All-Access pass", footer.passNote)
        XCTAssertEqual(
            [ColocatedCardsLogic.Link(text: "Event page ↗", url: try XCTUnwrap(argo.pageUrl)), ColocatedCardsLogic.Link(text: "Official listing ↗", url: try XCTUnwrap(argo.infoUrl))],
            footer.links
        )
    }

    func testColoAgendaRows() throws {
        let now = at("2026-11-09T08:00:00-07:00")
        let argo = try XCTUnwrap(repo.coloEvent("colo-argocon"))
        let card = idx.coloCard(argo, now, katie)
        let rows = ColocatedCardsLogic.agendaRows(card, idx, selectedId: "1312052", revealId: nil, goingIds: [], clashIds: [])
        XCTAssertEqual(card.agenda.map(\.session.id), rows.map(\.kid.session.id))
        XCTAssertFalse(try XCTUnwrap(rows.last).kid.divider)
        XCTAssertTrue(try rows.singleMatch { $0.kid.session.id == "1312052" }.kid.selected)
        XCTAssertTrue(rows.contains { $0.kid.mine })
        for r in rows {
            XCTAssertEqual(r.item.isBreak, r.breakText != nil)
            XCTAssertEqual(r.item.room.map { idx.roomName($0) }, r.kid.place)
            if !r.kid.mine && r.kid.session.id != rows.last?.kid.session.id { XCTAssertTrue(r.kid.divider) }
        }
        let brk = try XCTUnwrap(rows.first { $0.item.isBreak })
        let text = try XCTUnwrap(brk.breakText)
        XCTAssertTrue(text[0].bold)
        XCTAssertEqual(ColoText.breakParts(brk.item.session, brk.item.room, idx.roomName).joined(separator: " · "), text.plainText)
        XCTAssertEqual(.muted, ColocatedCardsLogic.breakTimeColor(brk.item))
    }

    // MARK: - ScheduleHeaderLogic

    func testHeaderTexts() throws {
        XCTAssertEqual("KUBECON NA 2026", ScheduleHeaderLogic.BRAND.plainText)
        XCTAssertEqual([nil, PaletteRole.you, nil], ScheduleHeaderLogic.BRAND.map(\.role))
        XCTAssertEqual(4, ScheduleHeaderLogic.headerTrailingPadding(16))
        XCTAssertEqual(0, ScheduleHeaderLogic.headerTrailingPadding(5))
        XCTAssertNil(ScheduleHeaderLogic.dayTabsCurrent("wed", searching: true))
        XCTAssertEqual("wed", ScheduleHeaderLogic.dayTabsCurrent("wed", searching: false))
        let tabs = idx.dayTabs(at("2026-11-11T08:00:00-07:00"), lucy)
        XCTAssertEqual("Today, Wednesday, Nov 11, you’re speaking", ScheduleHeaderLogic.dayTabDescription(try tabs.singleMatch { $0.key == "wed" }))
        XCTAssertEqual("Thursday, Nov 12", ScheduleHeaderLogic.dayTabDescription(try tabs.singleMatch { $0.key == "thu" }))
        let next = at("2026-11-11T10:15:00-07:00")
        XCTAssertEqual("3 ON NOW · NEXT AT 10:15 AM", ScheduleHeaderLogic.dayStatusLine(DayStatus(3, next)).plainText)
        XCTAssertEqual([PaletteRole.you, nil, nil, .ink], ScheduleHeaderLogic.dayStatusLine(DayStatus(3, next)).map(\.role))
        XCTAssertEqual("0 ON NOW", ScheduleHeaderLogic.dayStatusLine(DayStatus(0, nil)).plainText)
        let banner = try XCTUnwrap(idx.banner("wed", at("2026-11-11T08:00:00-07:00"), lucy))
        let later = try XCTUnwrap(banner.later.first)
        XCTAssertEqual(later.session.title + " ", ScheduleHeaderLogic.bannerLaterText(later).title)
        XCTAssertEqual(later.roomName, ScheduleHeaderLogic.bannerLaterText(later).room)
    }

    // MARK: - GoingUiLogic

    func testStarChipAndToggleLooks() throws {
        XCTAssertEqual(.ink, GoingUiLogic.starTint(going: true, onCard: false))
        XCTAssertEqual(.muted, GoingUiLogic.starTint(going: false, onCard: false))
        XCTAssertEqual(.onYou, GoingUiLogic.starTint(going: true, onCard: true))
        XCTAssertEqual(.onYouFaded, GoingUiLogic.starTint(going: false, onCard: true))
        XCTAssertTrue(GoingUiLogic.chipColors(on: true) == (PaletteRole.ink, PaletteRole.ink, PaletteRole.bg))
        XCTAssertTrue(GoingUiLogic.chipColors(on: false) == (PaletteRole.surface, PaletteRole.line, PaletteRole.ink))
        XCTAssertEqual("RSVP’d", GoingUiLogic.toggleLabel(true))
        XCTAssertEqual("RSVP", GoingUiLogic.toggleLabel(false))
        XCTAssertTrue(GoingUiLogic.toggleColors(true) == (PaletteRole.goingButtonBg, PaletteRole.ink, 2))
        XCTAssertTrue(GoingUiLogic.toggleColors(false) == (PaletteRole.surface, PaletteRole.line, 1))
        XCTAssertFalse(GoingUiLogic.showsToggle(idx, try s("1289742"))) // a break
        XCTAssertTrue(GoingUiLogic.showsToggle(idx, try s("1251049")))
    }

    func testUpNextCardTexts() throws {
        let next = try XCTUnwrap(GoingLogic.upNext(idx, "wed", ["1251049"], nil, at("2026-11-11T14:00:00-07:00")))
        let level = next.level.map { " · \($0)" } ?? ""
        XCTAssertEqual("\(next.time) · \(next.roomName)\(level)", GoingUiLogic.goingNextWhere(next).plainText)
        XCTAssertEqual("Directions to Regency Ballroom B", GoingUiLogic.goingNextDirectionsLabel(next))
        XCTAssertEqual(.muted, GoingUiLogic.goingNextCountdownColor(next))
        let off = GoingNext(session: next.session, live: true, label: GoingText.ON_NOW, countdown: "8 min left", time: "9:00–9:30 AM", roomName: "Off-site", level: nil, canRoute: false)
        XCTAssertEqual("9:00–9:30 AM · Off-site", GoingUiLogic.goingNextWhere(off).plainText)
        XCTAssertEqual(.you, GoingUiLogic.goingNextCountdownColor(off))
    }

    func testClashNoteLines() throws {
        let now = at("2026-11-11T08:00:00-07:00")
        let rb = try s("1251049")
        let lines = try XCTUnwrap(GoingUiLogic.clashNote(idx, rb, ["1251049"], lucy, now))
        let line = try lines.singleMatch { _ in true }
        XCTAssertEqual("1249844", line.session.id)
        XCTAssertTrue(line.mine)
        XCTAssertEqual("2:20–2:50 PM · Your talk: \(line.session.title) · Grand Ballroom GI", line.runs.plainText)
        XCTAssertNil(GoingUiLogic.clashNote(idx, rb, [], lucy, now)) // not starred
        XCTAssertNil(GoingUiLogic.clashNote(idx, rb, ["1251049"], nil, now)) // nothing to clash with
        // A clash on another day names it.
        let other = GoingUiLogic.clashLines([Clash(try s("1250150"), mine: false)], idx, "wed")
        XCTAssertTrue(try XCTUnwrap(other.first).when.hasPrefix("Thu "))
        XCTAssertFalse(try XCTUnwrap(other.first).runs.plainText.contains("Your talk"))
    }

    func testReminderHintsAndTheNotificationsOffText() throws {
        let before = at("2026-11-11T08:00:00-07:00")
        XCTAssertEqual(.mine, GoingUiLogic.reminderHint(try s("1289660"), lucy, [], 10, before))
        XCTAssertNil(GoingUiLogic.reminderHint(try s("1289660"), lucy, [], 10, at("2026-11-11T17:00:00-07:00"))) // started
        XCTAssertEqual(.going, GoingUiLogic.reminderHint(try s("1251218"), nil, ["1251218"], 10, before))
        XCTAssertNil(GoingUiLogic.reminderHint(try s("1251218"), nil, ["1251218"], 0, before)) // RSVP reminders off
        XCTAssertNil(GoingUiLogic.reminderHint(try s("1251218"), nil, [], 10, before))

        XCTAssertEqual(GoingText.NOTIFICATIONS_OFF, GoingUiLogic.notificationsOffText(.app, .going))
        XCTAssertNil(GoingUiLogic.notificationsOffText(.channel, .going))
        XCTAssertEqual(GoingText.GOING_CHANNEL_OFF, GoingUiLogic.notificationsOffText(.channel, .going, channelLevel: true))
        XCTAssertEqual(GoingText.TALKS_CHANNEL_OFF, GoingUiLogic.notificationsOffText(.channel, .mine, channelLevel: true))
        XCTAssertNil(GoingUiLogic.notificationsOffText(.nothing, .mine, channelLevel: true))

        XCTAssertEqual(.going, GoingUiLogic.reminderSettingChannel(10, nil))
        XCTAssertEqual(.going, GoingUiLogic.reminderSettingChannel(5, lucy))
        XCTAssertEqual(.mine, GoingUiLogic.reminderSettingChannel(0, lucy))
        XCTAssertNil(GoingUiLogic.reminderSettingChannel(0, nil))
    }

    // MARK: - PaletteRole, WidthClass

    func testPaletteRolesComputeTheKotlinColours() {
        for p in [AppPalette.light, AppPalette.dark] {
            XCTAssertEqual(p.you, PaletteRole.you.argb(in: p))
            XCTAssertEqual(p.muted, PaletteRole.category("nope").argb(in: p))
            XCTAssertEqual(p.category("colo"), PaletteRole.category("colo").argb(in: p))
            XCTAssertEqual(p.note, PaletteRole.clash.argb(in: p))
            XCTAssertEqual(0xCC, PaletteRole.onYouFaded.argb(in: p) >> 24) // alpha 0.8
            XCTAssertEqual(mixARGB(p.ink, p.line, 0.60), PaletteRole.goingRule.argb(in: p))
            XCTAssertEqual(mixARGB(p.note, p.surface, 0.08), PaletteRole.clashBg.argb(in: p))
            XCTAssertEqual(mixARGB(p.note, p.line, 0.45), PaletteRole.clashBorder.argb(in: p))
            XCTAssertEqual(mixARGB(p.ink, p.surface, 0.09), PaletteRole.goingButtonBg.argb(in: p))
        }
        // Light: plain surface, a 60% border, a transparent kid row; dark: a faint lift.
        XCTAssertEqual(AppPalette.light.surface, PaletteRole.goingCardBg.argb(in: .light))
        XCTAssertNotEqual(AppPalette.dark.surface, PaletteRole.goingCardBg.argb(in: .dark))
        XCTAssertEqual(mixARGB(AppPalette.light.ink, AppPalette.light.line, 0.60), PaletteRole.goingCardBorder.argb(in: .light))
        XCTAssertEqual(mixARGB(AppPalette.dark.ink, AppPalette.dark.line, 0.40), PaletteRole.goingCardBorder.argb(in: .dark))
        XCTAssertEqual(0, PaletteRole.goingRowBg.argb(in: .light))
        XCTAssertEqual(argbWithAlpha(AppPalette.dark.ink, 0.055), PaletteRole.goingRowBg.argb(in: .dark))
    }

    func testWidthClassBreakpoints() {
        XCTAssertEqual(.compact, WidthClass.fromWidth(393))
        XCTAssertEqual(.compact, WidthClass.fromWidth(599.9))
        XCTAssertEqual(.medium, WidthClass.fromWidth(600))
        XCTAssertEqual(.medium, WidthClass.fromWidth(839))
        XCTAssertEqual(.expanded, WidthClass.fromWidth(840))
        XCTAssertEqual(.expanded, WidthClass.fromWidth(1366))
        XCTAssertEqual([false, true, true], WidthClass.allCases.map(\.isWide))
    }
}
