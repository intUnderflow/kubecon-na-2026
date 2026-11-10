import XCTest
@testable import KCNA26Core

/// Port of going/GoingLogicTest.kt.
final class GoingLogicTests: XCTestCase {
    private let repo = TestData.repo
    private let idx = ScheduleIndex.of(TestData.repo)
    private let lucy = "Lucy Sweet"
    private func at(_ iso: String) -> Date { TestData.instant(iso) }
    private func s(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> Session {
        try XCTUnwrap(repo.session(id), "no session \(id)", file: file, line: line)
    }

    // Wednesday: Lucy speaks at 9:45 (1363905, keynote group), 2:20 (1249844, GI) and 5:00 (1289660, 251 A–C).
    private let rb220 = "1251049" // Regency Ballroom B, 2:20–2:50 PM
    private let ra220 = "1240105" // Regency Ballroom A, 2:20–3:40 PM (hands-on)
    private let rb500 = "1251218" // Regency Ballroom B, 5:00–5:30 PM
    private let cc250 = "1336094" // CC, 2:50–3:05 PM
    private let show120 = "1204401" // SHOW, 1:20–2:20 PM

    /// Kotlin `clashes.map { it.session.id to it.mine }`.
    private func pairs(_ cs: [Clash]) -> [String] { cs.map { "\($0.session.id) \($0.mine)" } }

    // MARK: - clashes

    func testOverlapIsStrictSoBackToBackIsNoClash() throws {
        XCTAssertTrue(GoingLogic.overlaps(try s(rb220), try s(ra220)))
        XCTAssertTrue(GoingLogic.overlaps(try s(ra220), try s(rb220)))
        XCTAssertFalse(GoingLogic.overlaps(try s(show120), try s(rb220))) // ends 2:20, the other starts 2:20
        XCTAssertFalse(GoingLogic.overlaps(try s(rb220), try s(cc250))) // ends 2:50, the other starts 2:50
        XCTAssertTrue(GoingLogic.overlaps(try s(ra220), try s(cc250)))
        XCTAssertFalse(GoingLogic.overlaps(try s(rb220), try s(rb500)))
    }

    func testStarredSessionsClashWithEachOtherAndWithMyTalks() throws {
        let going: Set<String> = [rb220, ra220, rb500, show120]
        let c = GoingLogic.clashes(idx, going, lucy)
        XCTAssertEqual(Set([rb220, ra220, rb500]), Set(c.keys))
        // Sorted by start, then id; my own talk is flagged.
        XCTAssertEqual(["\(ra220) false", "1249844 true"], pairs(try XCTUnwrap(c[rb220])))
        XCTAssertEqual(["1249844 true", "\(rb220) false"], pairs(try XCTUnwrap(c[ra220])))
        XCTAssertEqual(["1289660 true"], pairs(try XCTUnwrap(c[rb500])))
        // show120 ends as the others start: no clash, no tag.
        XCTAssertFalse(c.keys.contains(show120))
    }

    func testMyTalksOnlyCountWhileIAmSpeakingAsThem() throws {
        let c = GoingLogic.clashes(idx, [rb500], nil)
        XCTAssertTrue(c.isEmpty)
        XCTAssertEqual(["1289660"], try XCTUnwrap(GoingLogic.clashes(idx, [rb500], lucy)[rb500]).map { $0.session.id })
    }

    func testLucysOwnTalksStarredToo() throws {
        // Lucy stars her own three talks as well as two sessions against them.
        let going: Set<String> = ["1363905", "1249844", "1289660", rb220, rb500]
        let c = GoingLogic.clashes(idx, going, lucy)
        // Her keynote slot clashes with nothing starred; the 2:20 and 5:00 talks do (each listed once).
        XCTAssertFalse(c.keys.contains("1363905"))
        XCTAssertEqual([rb220], try XCTUnwrap(c["1249844"]).map { $0.session.id })
        XCTAssertEqual(["1249844"], try XCTUnwrap(c[rb220]).map { $0.session.id })
        XCTAssertEqual([rb500], try XCTUnwrap(c["1289660"]).map { $0.session.id })
    }

    func testFinishedSessionsNoLongerClash() throws {
        let going: Set<String> = [rb220, ra220, cc250]
        // 2:30: everything is still on or to come.
        let mid = GoingLogic.clashes(idx, going, nil, at("2026-11-11T14:30"))
        XCTAssertEqual(Set([rb220, ra220, cc250]), Set(mid.keys))
        XCTAssertEqual([rb220, cc250], try XCTUnwrap(mid[ra220]).map { $0.session.id })
        // 2:55: RB's 2:20 talk is over; RA still overlaps CC.
        let later = GoingLogic.clashes(idx, going, nil, at("2026-11-11T14:55"))
        XCTAssertEqual(Set([ra220, cc250]), Set(later.keys))
        XCTAssertEqual([cc250], try XCTUnwrap(later[ra220]).map { $0.session.id })
        // Nothing left after 3:40.
        XCTAssertTrue(GoingLogic.clashes(idx, going, nil, at("2026-11-11T15:45")).isEmpty)
    }

    func testUnknownIdsAndNoStarsGiveNoClashes() throws {
        XCTAssertTrue(GoingLogic.clashes(idx, [], lucy).isEmpty)
        XCTAssertTrue(GoingLogic.clashes(idx, ["gone"], lucy).isEmpty)
        XCTAssertEqual(["1249844"], GoingLogic.clashesFor(idx, try s(rb220), [rb220, "gone"], lucy).map { $0.session.id })
        // Not starred: no clash list, even though it overlaps my talk.
        XCTAssertTrue(GoingLogic.clashesFor(idx, try s(ra220), [rb220], lucy).isEmpty)
    }

    func testSessionsInTheSameRoomNeverClash() throws {
        // Wednesday's posters: all ten in SHOW, 1:20–2:20 PM, one group card. Starring two is one visit.
        let posters = try XCTUnwrap(idx.groups["wed-posters"]).kids.map { $0.id }
        XCTAssertEqual(10, posters.count)
        guard posters.count == 10 else { return }
        let two: Set<String> = [posters[0], posters[1]]
        XCTAssertTrue(GoingLogic.overlaps(try s(posters[0]), try s(posters[1])))
        XCTAssertTrue(GoingLogic.clashes(idx, two, nil).isEmpty)
        XCTAssertTrue(GoingLogic.clashes(idx, Set(posters), lucy).isEmpty)
        // Tuesday's keynotes: "From Pod to Actuator" (10:41–10:46) overlaps "Closing Remarks" (10:44–10:45) in DE.
        let keynotes = Set(try XCTUnwrap(idx.groups["tue-key"]).kids.map { $0.id })
        XCTAssertTrue(GoingLogic.overlaps(try s("1380168"), try s("1302802")))
        XCTAssertTrue(GoingLogic.clashes(idx, keynotes, nil).isEmpty)
        // A poster still clashes with a starred talk elsewhere at the same time.
        let withTalk = GoingLogic.clashes(idx, [posters[0], "1336094", "1240105"], nil) // CC 2:50, RA 2:20–3:40
        XCTAssertFalse(withTalk.keys.contains(posters[0]))
        XCTAssertEqual(["1240105"], try XCTUnwrap(withTalk["1336094"]).map { $0.session.id })
    }

    func testLongRowsNeverClash() throws {
        // Monday: ArgoCon (all day, 151) with Project Lightning Talks and Peer Group Mentoring.
        let argo = "1289755"
        let talks: Set<String> = ["1289828", "1289870", "1345969"]
        XCTAssertTrue(idx.isLong(try s(argo)))
        let argoSession = try s(argo)
        let talkSessions = try talks.map { try s($0) }
        XCTAssertTrue(talkSessions.allSatisfy { GoingLogic.overlaps(argoSession, $0) })
        XCTAssertTrue(GoingLogic.clashes(idx, talks.union([argo]), nil).isEmpty)
        // Off-site, too: Microsoft Azure Day (8 AM–6 PM, off-site) against a lightning talk.
        XCTAssertTrue(idx.isLong(try s("1341814")))
        XCTAssertTrue(GoingLogic.overlaps(try s("1341814"), try s("1289828")))
        XCTAssertTrue(GoingLogic.clashes(idx, ["1341814", "1289828"], nil).isEmpty)
        // Two ordinary talks still clash (with an all-day event starred too): RA 2:20 and CC 2:50 on Wednesday.
        XCTAssertEqual(Set([ra220, cc250]), Set(GoingLogic.clashes(idx, [ra220, cc250, "1289755"], nil).keys))
    }

    // MARK: - up next

    func testUpNextIsTheNextStarredSessionToday() throws {
        let n = GoingLogic.upNext(idx, "wed", [rb220, rb500], lucy, at("2026-11-11T14:08"))
        XCTAssertNotNil(n)
        let next = try XCTUnwrap(n)
        XCTAssertEqual(rb220, next.session.id)
        XCTAssertFalse(next.live)
        XCTAssertEqual("Your next", next.label)
        XCTAssertEqual("in 12 min", next.countdown)
        XCTAssertEqual("2:20–2:50 PM", next.time)
        XCTAssertEqual("Regency Ballroom B", next.roomName)
        XCTAssertEqual("Level 4", next.level)
        XCTAssertTrue(next.canRoute)
    }

    func testALiveStarredSessionIsShownUntilTheNextIsSoon() throws {
        let going: Set<String> = [rb220, rb500]
        let live = try XCTUnwrap(GoingLogic.upNext(idx, "wed", going, lucy, at("2026-11-11T14:30")))
        XCTAssertEqual(rb220, live.session.id)
        XCTAssertTrue(live.live)
        // Never "Up next · Live": a session on now is labelled as such.
        XCTAssertEqual("On now", live.label)
        XCTAssertEqual("20 min left", live.countdown)
        // RB 2:20 is over: the 5:00 talk, hours away.
        let after = try XCTUnwrap(GoingLogic.upNext(idx, "wed", going, lucy, at("2026-11-11T14:50")))
        XCTAssertEqual(rb500, after.session.id)
        XCTAssertEqual("Your next", after.label)
        XCTAssertEqual("in 2h 10m", after.countdown)
        // RA's hands-on runs to 3:40; CC starts at 2:50. From 2:35 the soon one wins.
        let both: Set<String> = [ra220, cc250]
        XCTAssertEqual(ra220, try XCTUnwrap(GoingLogic.upNext(idx, "wed", both, nil, at("2026-11-11T14:30"))).session.id)
        let soon = try XCTUnwrap(GoingLogic.upNext(idx, "wed", both, nil, at("2026-11-11T14:35")))
        XCTAssertEqual(cc250, soon.session.id)
        XCTAssertEqual("in 15 min", soon.countdown)
        XCTAssertEqual(ra220, try XCTUnwrap(GoingLogic.upNext(idx, "wed", both, nil, at("2026-11-11T15:05"))).session.id)
    }

    func testUpNextLeavesOutMyTalksOtherDaysAndFinishedSessions() throws {
        // Lucy's own 2:20 talk, starred: the speaker banner has it, so not "Up next"...
        XCTAssertNil(GoingLogic.upNext(idx, "wed", ["1249844"], lucy, at("2026-11-11T14:00")))
        // ...unless she isn't speaking as herself.
        XCTAssertEqual("1249844", try XCTUnwrap(GoingLogic.upNext(idx, "wed", ["1249844"], nil, at("2026-11-11T14:00"))).session.id)
        // Only on today's list.
        XCTAssertNil(GoingLogic.upNext(idx, "thu", [rb220], lucy, at("2026-11-11T14:00")))
        XCTAssertNil(GoingLogic.upNext(idx, "wed", [rb220], lucy, at("2026-11-10T14:00")))
        XCTAssertNil(GoingLogic.upNext(idx, nil, [rb220], lucy, at("2026-11-11T14:00")))
        // Before the conference there is no today.
        XCTAssertNil(GoingLogic.upNext(idx, "wed", [rb220], lucy, at("2026-11-07T14:00")))
        // Over.
        XCTAssertNil(GoingLogic.upNext(idx, "wed", [rb220], lucy, at("2026-11-11T14:50")))
        XCTAssertNil(GoingLogic.upNext(idx, "wed", [], lucy, at("2026-11-11T14:00")))
        XCTAssertNil(GoingLogic.upNext(idx, "wed", ["gone"], lucy, at("2026-11-11T14:00")))
    }

    func testAnAllDayEventOnNowDoesNotHideTheTalksInBetween() throws {
        let going: Set<String> = ["1289755", "1289870", "1345969"] // ArgoCon all day; 11:03 lightning talk; 3:00 mentoring
        // 10:30: ArgoCon is on, but the 11:03 talk is the one to plan for.
        let n = try XCTUnwrap(GoingLogic.upNext(idx, "mon", going, nil, at("2026-11-09T10:30")))
        XCTAssertEqual("1289870", n.session.id)
        XCTAssertEqual("Your next", n.label)
        XCTAssertEqual("in 33 min", n.countdown)
        // 11:05: the lightning talk is on now.
        XCTAssertEqual("1289870", try XCTUnwrap(GoingLogic.upNext(idx, "mon", going, nil, at("2026-11-09T11:05"))).session.id)
        // 1 PM: nothing on but ArgoCon; the 3:00 mentoring is next.
        XCTAssertEqual("1345969", try XCTUnwrap(GoingLogic.upNext(idx, "mon", going, nil, at("2026-11-09T13:00"))).session.id)
        // 4:10 PM: only ArgoCon is left, so it's shown, until its end.
        let argo = try XCTUnwrap(GoingLogic.upNext(idx, "mon", going, nil, at("2026-11-09T16:10")))
        XCTAssertEqual("1289755", argo.session.id)
        XCTAssertTrue(argo.live)
        XCTAssertEqual("On now", argo.label)
        XCTAssertEqual("until 5:30 PM", argo.countdown)
        // Starred on its own, it's shown while it runs.
        XCTAssertEqual("1289755", try XCTUnwrap(GoingLogic.upNext(idx, "mon", ["1289755"], nil, at("2026-11-09T10:30"))).session.id)
    }

    func testCountdownLabels() {
        XCTAssertEqual("in 1 min", GoingLogic.countdown(0))
        XCTAssertEqual("in 12 min", GoingLogic.countdown(12))
        XCTAssertEqual("in 1h", GoingLogic.countdown(60))
        XCTAssertEqual("in 1h 5m", GoingLogic.countdown(65))
    }

    // MARK: - filter

    private func ids(_ view: DayView) -> [String] {
        let fromSlots: [String] = view.slots.flatMap { sl in
            sl.blocks.flatMap { b -> [String] in
                switch b {
                case .session(let sb): return [sb.session.id]
                case .group(let gb): return gb.kids.map { $0.id }
                }
            }
        }
        return fromSlots + view.longs.map { $0.session.id }
    }

    func testTheFilterKeepsStarredSessionsAndMyTalks() throws {
        let now = at("2026-11-11T08:00")
        let full = try XCTUnwrap(idx.dayView("wed", now, lucy))
        let going: Set<String> = [rb220, "1372841"] // a talk and the 9:00 keynote
        let v = GoingLogic.filterDay(full, now) { GoingLogic.keeps($0, going, lucy) }
        XCTAssertEqual(["1372841", "1363905", rb220, "1249844", "1289660"].sorted(), ids(v).sorted())
        // Keynotes stay one group card, with just the kept kids.
        let g = try v.slots.flatMap { $0.blocks }.compactMap { $0.groupBlock }.singleMatch { _ in true }
        XCTAssertEqual(["1372841", "1363905"], g.kids.map { $0.id })
        // No breaks, no empty blocks.
        XCTAssertTrue(v.slots.allSatisfy { !$0.blocks.isEmpty })
        XCTAssertTrue(v.slots.flatMap { $0.blocks }.allSatisfy { $0.category != "log" })
        XCTAssertEqual(full.day, v.day)
        // The status line counts what is shown: nothing on yet, the 9:00 keynote next.
        XCTAssertEqual(DayStatus(0, at("2026-11-11T09:00")), v.status)
    }

    func testTheFilteredStatusLineCountsOnlyTheShownSessions() throws {
        let now = at("2026-11-11T14:30")
        let full = try XCTUnwrap(idx.dayView("wed", now, nil))
        XCTAssertGreaterThan(try XCTUnwrap(full.status).onNow, 5)
        let going: Set<String> = [rb220, rb500]
        let v = GoingLogic.filterDay(full, now) { GoingLogic.keeps($0, going, nil) }
        // RB 2:20 is on; next is RB 5:00 (not the whole day's 2:50 or 3:00 starts).
        XCTAssertEqual(DayStatus(1, at("2026-11-11T17:00")), v.status)
        // Not today: no status line, filtered or not.
        XCTAssertNil(GoingLogic.filterDay(try XCTUnwrap(idx.dayView("thu", now, nil)), now) { _ in true }.status)
    }

    func testAGroupMovesToTheBlockOfItsFirstKeptKid() throws {
        let now = at("2026-11-11T08:00")
        let full = try XCTUnwrap(idx.dayView("wed", now, nil))
        let v = GoingLogic.filterDay(full, now) { $0.id == "1363905" } // 9:45 keynote only
        let slot = try v.slots.singleMatch { _ in true }
        XCTAssertEqual(9 * 60 + 30, slot.key)
        XCTAssertEqual("9:45 AM", slot.label)
        let group = try XCTUnwrap(try slot.blocks.singleMatch { _ in true }.groupBlock)
        XCTAssertEqual(["1363905"], group.kids.map { $0.id })
    }

    func testTheUpNextLineIsPlacedInTheFilteredBlocks() throws {
        let going: Set<String> = [rb220, rb500, cc250]
        let now = at("2026-11-11T14:25")
        let full = try XCTUnwrap(idx.dayView("wed", now, lucy))
        let v = GoingLogic.filterDay(full, now) { GoingLogic.keeps($0, going, lucy) }
        // 2:20 (RB, Lucy's GI talk) is on; then 2:50 CC, then 5:00 (RB, Lucy's 251 A–C).
        XCTAssertEqual([14 * 60, 14 * 60 + 30, 17 * 60], v.slots.map { $0.key })
        XCTAssertEqual(1, v.upNextBefore)
        // Not today: no line.
        let thu = try XCTUnwrap(idx.dayView("thu", now, lucy))
        XCTAssertEqual(-1, GoingLogic.filterDay(thu, now) { _ in true }.upNextBefore)
        // Nothing on yet: the first block gets no line (web rule).
        let early = at("2026-11-11T08:00")
        let e = GoingLogic.filterDay(try XCTUnwrap(idx.dayView("wed", early, lucy)), early) { GoingLogic.keeps($0, going, lucy) }
        XCTAssertEqual(-1, e.upNextBefore)
    }

    func testTheFilterWithNothingKeptIsEmpty() throws {
        let now = at("2026-11-11T08:00")
        let v = GoingLogic.filterDay(try XCTUnwrap(idx.dayView("wed", now, nil)), now) { _ in false }
        XCTAssertTrue(v.isEmpty)
        XCTAssertEqual(-1, v.upNextBefore)
    }

    func testCoLocatedCardsKeepOnlyStarredTalksAndGoWhenNoneIsLeft() throws {
        let now = at("2026-11-09T08:00") // Monday, before the co-located events start
        let full = try XCTUnwrap(idx.dayView("mon", now, nil))
        XCTAssertGreaterThanOrEqual(full.colo.count, 2)
        guard full.colo.count >= 2 else { return }
        let a = full.colo[0]
        let b = full.colo[1]
        let talks = a.agenda.filter { !$0.isBreak }
        XCTAssertTrue(talks.count >= 3 && a.agenda.contains { $0.isBreak })
        guard talks.count >= 3 else { return }
        // Kotlin setOf(...).toList(): insertion order.
        let starredList = [talks[1].session.id, talks[2].session.id]
        let starred = Set(starredList)

        let v = GoingLogic.filterDay(full, now) { GoingLogic.keeps($0, starred, nil) }
        // Only the card with starred talks is left, holding just those talks (no breaks).
        XCTAssertEqual([a.key], v.colo.map { $0.key })
        let card = try v.colo.singleMatch { _ in true }
        XCTAssertEqual(starredList, card.agenda.map { $0.session.id })
        XCTAssertTrue(card.agenda.allSatisfy { !$0.isBreak })
        XCTAssertFalse(v.colo.map { $0.key }.contains(b.key))
        // Its "Starts …" line names the first starred talk, not the event's opening talk.
        let line = try XCTUnwrap(try card.lines.singleMatch { _ in true }.asStarts)
        XCTAssertEqual(talks[1].session.id, line.session?.id)
        XCTAssertFalse(v.isEmpty)

        // Nothing starred there: no co-located section at all.
        XCTAssertTrue(GoingLogic.filterDay(full, now) { _ in false }.colo.isEmpty)
        // Everything kept: every card stays, with all its talks.
        let all = GoingLogic.filterDay(full, now) { _ in true }
        XCTAssertEqual(full.colo.map { $0.key }, all.colo.map { $0.key })
        XCTAssertEqual(full.colo.map { c in c.agenda.count { !$0.isBreak } }, all.colo.map { $0.agenda.count })
    }

    func testSearchResultsAreFilteredToo() throws {
        let now = at("2026-11-08T08:00")
        let all = idx.search("kubernetes", now, lucy)
        XCTAssertGreaterThan(all.count, 10)
        let going: Set<String> = ["1249844", "gone"]
        let r = GoingLogic.filterSearch(all) { GoingLogic.keeps($0, going, nil) }
        XCTAssertEqual(1, r.count)
        XCTAssertEqual("1 match", r.heading)
        XCTAssertEqual("wed", try r.days.singleMatch { _ in true }.day.key)
        XCTAssertEqual(0, GoingLogic.filterSearch(all) { _ in false }.count)
        XCTAssertTrue(GoingLogic.filterSearch(all) { _ in false }.days.isEmpty)
    }

    // MARK: - empty states

    private func empty(
        _ goingOnly: Bool,
        _ full: DayView?,
        _ view: DayView?,
        _ going: Set<String>,
        _ now: Date,
        remindMinutes: Int = 10
    ) -> (title: String, text: String)? {
        GoingLogic.emptyText(goingOnly, full, view, nil, nil, idx, going, now, remindMinutes)
    }

    func testEmptyStatesExplainHowToStar() throws {
        let now = at("2026-11-11T08:00")
        let full = try XCTUnwrap(idx.dayView("wed", now, nil))
        let emptyView = GoingLogic.filterDay(full, now) { _ in false }
        // Filter off: the usual states.
        XCTAssertNil(empty(false, full, emptyView, [], now))
        // Nothing starred at all (unknown ids don't count).
        let none = try XCTUnwrap(empty(true, full, emptyView, ["gone"], now))
        XCTAssertEqual("No RSVPs yet", none.title)
        XCTAssertTrue(none.text.hasPrefix("Turn off RSVP’d above, then tap the star on any session to RSVP"))
        XCTAssertTrue(none.text.contains("with a reminder 10 min before it starts."))
        XCTAssertFalse(try XCTUnwrap(empty(true, full, emptyView, [], now, remindMinutes: 0)).text.contains("reminder"))
        // Stars on other days only: those days are named.
        let thu = "1247970" // Thursday 11:00
        let other = try XCTUnwrap(empty(true, full, emptyView, [thu], now))
        XCTAssertEqual("No RSVPs for Wednesday", other.title)
        XCTAssertEqual("You have 1 on Thursday. " + GoingText.DAY_TEXT, other.text)
        // The filtered day has something: no note.
        let some = GoingLogic.filterDay(full, now) { $0.id == rb220 }
        XCTAssertNil(empty(true, full, some, [rb220], now))
        // A day that is over keeps "That’s a wrap" (the off-site escape room runs to midnight).
        let late = at("2026-11-12T00:30")
        let over = try XCTUnwrap(idx.dayView("wed", late, nil))
        XCTAssertTrue(over.isEmpty)
        XCTAssertNil(empty(true, over, GoingLogic.filterDay(over, late) { _ in false }, [thu], late))
    }

    func testWhenTodaysStarsAreOverTheNoteSaysSo() throws {
        // Wednesday 3 PM: RB 2:20 (starred) is over; Thursday has two stars.
        let now = at("2026-11-11T15:00")
        let going: Set<String> = [rb220, "1247970", "1230488"]
        let full = try XCTUnwrap(idx.dayView("wed", now, nil))
        let view = GoingLogic.filterDay(full, now) { GoingLogic.keeps($0, going, nil) }
        XCTAssertTrue(view.isEmpty)
        let (title, text) = try XCTUnwrap(empty(true, full, view, going, now))
        XCTAssertEqual("No RSVPs left today", title)
        XCTAssertEqual(
            "Your RSVP’d sessions for today are over. You have 2 on Thursday. Turn off RSVP’d above to see what’s still on.",
            text
        )
        // Nothing elsewhere: no "You have" part.
        XCTAssertEqual(
            "Your RSVP’d sessions for today are over. Turn off RSVP’d above to see what’s still on.",
            try XCTUnwrap(empty(true, full, view, [rb220], now)).text
        )
        // Several days are listed in day order.
        XCTAssertEqual(
            "You have 1 on Wednesday and 2 on Thursday.",
            GoingText.othersText([(1, "Wednesday"), (2, "Thursday")])
        )
        XCTAssertEqual(
            "You have 1 on Tuesday, 1 on Wednesday and 2 on Thursday.",
            GoingText.othersText([(1, "Tuesday"), (1, "Wednesday"), (2, "Thursday")])
        )
        // Kotlin listOf("wed" to 1, "thu" to 2).
        XCTAssertEqual(["wed 1", "thu 2"], GoingLogic.starredLeftByDay(idx, going.union([rb500]), now).map { "\($0.dayKey) \($0.count)" })
    }

    func testASpeakerWithNoStarsIsToldHowToStarUnderTheirTalks() throws {
        // Lucy, Wednesday, nothing starred, filter on: her own talks are left, with the how-to note.
        let now = at("2026-11-11T08:00")
        let full = try XCTUnwrap(idx.dayView("wed", now, lucy))
        let view = GoingLogic.filterDay(full, now) { GoingLogic.keeps($0, [], lucy) }
        XCTAssertFalse(view.isEmpty)
        XCTAssertEqual("No RSVPs yet", try XCTUnwrap(empty(true, full, view, [], now)).title)
        // Once something is starred, the list speaks for itself.
        XCTAssertNil(empty(true, full, view, [rb220], now))
        // Search: my talks match, nothing starred.
        let all = idx.search("Lucy Sweet", now, lucy)
        let mine = GoingLogic.filterSearch(all) { GoingLogic.keeps($0, [], lucy) }
        XCTAssertGreaterThan(mine.count, 0)
        XCTAssertEqual("No RSVPs yet", try XCTUnwrap(GoingLogic.emptyText(true, nil, nil, all, mine, idx, [], now, 10)).title)
        XCTAssertNil(GoingLogic.emptyText(true, nil, nil, all, mine, idx, [rb220], now, 10))
    }

    func testSearchEmptyStates() throws {
        let now = at("2026-11-08T08:00")
        let all = idx.search("kubernetes", now, nil)
        let none = GoingLogic.filterSearch(all) { _ in false }
        let note = try XCTUnwrap(GoingLogic.emptyText(true, nil, nil, all, none, idx, [rb220], now, 10))
        XCTAssertEqual("No RSVP’d matches", note.title)
        XCTAssertEqual("Turn off RSVP’d to search every session.", note.text)
        XCTAssertEqual("No RSVPs yet", try XCTUnwrap(GoingLogic.emptyText(true, nil, nil, all, none, idx, [], now, 10)).title)
        // No matches at all: the usual "No matches".
        let nothing = idx.search("zzzzqqq", now, nil)
        XCTAssertNil(GoingLogic.emptyText(true, nil, nil, nothing, GoingLogic.filterSearch(nothing) { _ in false }, idx, [rb220], now, 10))
    }
}
