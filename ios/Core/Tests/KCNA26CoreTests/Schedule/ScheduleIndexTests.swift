import XCTest
@testable import KCNA26Core

/// Port of schedule/ScheduleIndexTest.kt.
final class ScheduleIndexTests: XCTestCase {
    private let repo = TestData.repo
    private lazy var idx = ScheduleIndex.of(repo)
    private let lucy = "Lucy Sweet"

    private func at(_ iso: String) -> Date { TestData.instant(iso) }
    private func s(_ id: String) -> Session { repo.session(id)! }

    // MARK: - blocks

    func testBlockIsLabelledWithItsEarliestRealStart() throws {
        let sun = idx.dayView("sun", at("2026-11-08T08:00:00-07:00"), lucy)!
        let tenBlock = try sun.slots.singleMatch { $0.key == 600 } // 10:00–10:29
        XCTAssertEqual("10:15 AM", tenBlock.label)
        XCTAssertTrue(tenBlock.blocks.allSatisfy { (600...629).contains(TimeFormatMinute.of($0.start)) })
        // Every block's label is the earliest start in it, and blocks are in time order.
        for sl in sun.slots {
            XCTAssertEqual(sl.blocks.map(\.start).min(), sl.start)
            XCTAssertEqual(ScheduleLogic.slotKey(TimeFormatMinute.of(sl.start)), sl.key)
        }
        XCTAssertEqual(sun.slots.map(\.key).sorted(), sun.slots.map(\.key))
        XCTAssertEqual(sun.slots.count, Set(sun.slots.map(\.key)).count)
    }

    func testFinishedSessionsDisappear() {
        let now = at("2026-11-08T12:00:00-07:00")
        let sun = idx.dayView("sun", now, lucy)!
        let ids = Set(sun.allSessionIds())
        XCTAssertFalse(ids.contains("m1290687"), "10:15–11:00 talk is over")
        XCTAssertTrue(ids.contains("m1318414"), "12:20 lunch is still to come")
        XCTAssertTrue(ids.contains("m1318417"), "open-ended reception is listed")
        for id in ids { XCTAssertFalse(ScheduleLogic.isFinished(s(id), now), id) }
        // The reception (no end) is still listed at 6:59 PM, gone at 7:00 PM.
        XCTAssertTrue(idx.dayView("sun", at("2026-11-08T18:59:00-07:00"), lucy)!.allSessionIds().contains("m1318417"))
        XCTAssertFalse(idx.dayView("sun", at("2026-11-08T19:00:00-07:00"), lucy)!.allSessionIds().contains("m1318417"))
    }

    func testWrapWhenTheDayIsOver() {
        let sun = idx.dayView("sun", at("2026-11-08T23:00:00-07:00"), lucy)!
        XCTAssertTrue(sun.isEmpty)
        XCTAssertFalse(idx.dayView("thu", at("2026-11-08T23:00:00-07:00"), lucy)!.isEmpty)
    }

    func testGroupsBecomeOneCardWithUnfinishedKids() throws {
        let now = at("2026-11-11T09:46:00-07:00")
        let wed = idx.dayView("wed", now, lucy)!
        let keynotes = try wed.slots.flatMap(\.blocks).compactMap(\.groupBlock).singleMatch { $0.group.key == "wed-key" }
        XCTAssertEqual("Morning keynotes", keynotes.group.title)
        XCTAssertEqual("DE", keynotes.room)
        XCTAssertEqual("key", keynotes.category)
        XCTAssertEqual("1363905", keynotes.kids.first!.id) // 9:45 is still on; earlier keynotes are gone
        XCTAssertTrue(keynotes.kids.allSatisfy { !ScheduleLogic.isFinished($0, now) })
        XCTAssertEqual(13, idx.groups["wed-key"]!.kids.count)
        XCTAssertEqual("wed-key", idx.groupKeyOf("1363905"))
        // No grouped session is also shown on its own.
        let singles = wed.slots.flatMap(\.blocks).compactMap(\.sessionBlock).map(\.session.id)
        XCTAssertFalse(singles.contains("1363905"))
        // The group sits in the block of its earliest remaining kid (9:45 → the 9:30 block).
        let slot = try wed.slots.singleMatch { sl in sl.blocks.contains { $0 == .group(keynotes) } }
        XCTAssertEqual(570, slot.key)
    }

    func testMyTalksSortFirstThenTheNormalOrderInABlock() throws {
        let at2 = at("2026-11-11T14:00:00-07:00")
        let wed = idx.dayView("wed", at2, lucy)!
        let slot = try wed.slots.singleMatch { $0.key == 840 }
        let first = slot.blocks[0].sessionBlock!
        XCTAssertEqual("1249844", first.session.id) // Kubernetes The Hard Way - Live (mine)
        XCTAssertTrue(first.mine)
        // The rest: category, then room. An Anthropic talk gets no head start (Vinayak Goyal's
        // 1203350 keeps its badge but sits where its category and room put it).
        let rest = Array(slot.blocks.dropFirst())
        XCTAssertTrue(rest.allSatisfy { !$0.mine })
        XCTAssertTrue(rest.contains { $0.sessionBlock?.session.id == "1203350" && $0.anthropic })
        XCTAssertEqual(rest.stableSorted(with: normalOrder), rest)
        // With None, Lucy's talk is just an Anthropic talk: the whole block is in the normal order.
        let none = try idx.dayView("wed", at2, nil)!.slots.singleMatch { $0.key == 840 }
        XCTAssertTrue(none.blocks.allSatisfy { !$0.mine })
        XCTAssertEqual(none.blocks.stableSorted(with: normalOrder), none.blocks)
        XCTAssertTrue(try none.blocks.singleMatch { $0.sessionBlock?.session.id == "1249844" }.anthropic)
    }

    /// The block order without "mine": start, category, then room (rooms.json order).
    private lazy var normalOrder: KComparator<Block> = {
        let rooms: [String: Int] = Dictionary(uniqueKeysWithValues: TestData.repo.rooms.keys.enumerated().map { ($0.element, $0.offset) })
        return KComparator<Block>.by { $0.start }
            .thenBy { ScheduleIndex.CATEGORY_ORDER[$0.category] ?? ScheduleIndex.CATEGORY_ORDER.count }
            .thenBy { rooms[$0.room] ?? -1 }
    }()

    func testMondayLongsAreTheSponsorHostedOffSiteEvents() {
        // The CNCF co-located events are cards above the blocks now (ColocatedTests); their
        // All-Access placeholders are gone from the list, leaving the separate-registration events.
        let mon = idx.dayView("mon", at("2026-11-09T08:00:00-07:00"), lucy)!
        XCTAssertEqual("Sponsor-hosted · off-site", mon.longsTitle)
        XCTAssertFalse(mon.longsFirst)
        XCTAssertEqual(12, mon.longs.count)
        XCTAssertTrue(mon.longs.allSatisfy { $0.session.room == "OFF" })
        XCTAssertTrue(mon.longs.allSatisfy { $0.session.note != "All-Access pass" })
        XCTAssertEqual(11, mon.colo.count)
        let sun = idx.dayView("sun", at("2026-11-08T08:00:00-07:00"), lucy)!
        XCTAssertEqual("Off-site", sun.longsTitle)
        XCTAssertFalse(sun.longsFirst)
        XCTAssertEqual(["1344383"], sun.longs.map(\.session.id)) // the hackathon
    }

    func testTodayStatusAndUpNextLine() {
        let now = at("2026-11-08T10:05:00-07:00")
        let sun = idx.dayView("sun", now, lucy)!
        XCTAssertTrue(sun.isToday)
        let st = sun.status!
        XCTAssertEqual(0, st.onNow)
        XCTAssertEqual(at("2026-11-08T10:15:00-07:00"), st.nextStart)
        // Web: the line goes before the first block whose half-hour is after now (11:00), not the first block.
        XCTAssertEqual(1100, TimeFormatMinute.hhmm(sun.slots[sun.upNextBefore].start))
        XCTAssertTrue(sun.upNextBefore > 0)
        // Other days: no status, no line.
        let mon = idx.dayView("mon", now, lucy)!
        XCTAssertNil(mon.status)
        XCTAssertEqual(-1, mon.upNextBefore)
    }

    func testUnconferenceSessionsAreOrdinarySundaySessions() {
        // 3:10 PM on Sunday: the 3:05 unconference sessions are live cards in the normal blocks.
        let sun = idx.dayView("sun", at("2026-11-08T15:10:00-07:00"), lucy)!
        let shown = sun.slots.flatMap(\.blocks).compactMap(\.sessionBlock).map(\.session)
        let unconf = shown.filter { $0.note == "Unconference" }
        XCTAssertEqual(Set(["m1318482", "m1318481", "m1318480", "m1318486", "m1318484", "m1318483"]), Set(unconf.map(\.id)))
        XCTAssertTrue(unconf.allSatisfy { $0.title.kotlinStartsWith("Unconference: ") && !$0.speakers.isEmpty })
        XCTAssertTrue(unconf.allSatisfy { idx.category($0) == "com" })
    }

    // MARK: - mine / Anthropic

    func testMineAndAnthropicFollowTheSetting() {
        let keynote = s("1363905") // Lucy alone
        let kthw = s("1249844") // Lucy + Sandeep Kanabar
        let vinayak = s("1203350") // Anthropic colleague
        // Lucy Sweet
        XCTAssertTrue(idx.isMine(keynote, lucy))
        XCTAssertTrue(idx.isMine(kthw, lucy))
        XCTAssertFalse(idx.hasAnthropic(kthw, lucy))
        XCTAssertTrue(idx.hasAnthropic(vinayak, lucy))
        XCTAssertFalse(idx.isMine(vinayak, lucy))
        // Another speaker: their talk is mine; Lucy's other talks become Anthropic talks.
        let sandeep = "Sandeep Kanabar"
        XCTAssertTrue(idx.isMine(kthw, sandeep))
        XCTAssertFalse(idx.hasAnthropic(kthw, sandeep))
        XCTAssertFalse(idx.isMine(keynote, sandeep))
        XCTAssertTrue(idx.hasAnthropic(keynote, sandeep))
        // None
        XCTAssertFalse(idx.isMine(keynote, nil))
        XCTAssertTrue(idx.hasAnthropic(keynote, nil))
        XCTAssertTrue(idx.hasAnthropic(vinayak, nil))
        // The precomputed flags are never consulted: a speaker the JSON didn't flag.
        XCTAssertTrue(repo.sessions.allSatisfy { !idx.isMine($0, nil) })
    }

    func testDayTabsMarkDaysWithMyTalksStillToCome() {
        let tue = idx.dayTabs(at("2026-11-10T10:00:00-07:00"), lucy)
        XCTAssertEqual(["tue", "wed", "thu"], tue.map(\.key))
        XCTAssertEqual(["Today", "Wed", "Thu"], tue.map(\.label))
        XCTAssertEqual([10, 11, 12], tue.map(\.number))
        XCTAssertEqual([false, true, false], tue.map(\.hasMine))
        // After her last talk the Wednesday mark goes.
        XCTAssertTrue(idx.dayTabs(at("2026-11-11T17:29:00-07:00"), lucy).first { $0.key == "wed" }!.hasMine)
        XCTAssertFalse(idx.dayTabs(at("2026-11-11T17:30:00-07:00"), lucy).first { $0.key == "wed" }!.hasMine)
        // None: no marks. Someone else: their days.
        XCTAssertTrue(idx.dayTabs(at("2026-11-08T08:00:00-07:00"), nil).allSatisfy { !$0.hasMine })
        let decheng = idx.dayTabs(at("2026-11-08T08:00:00-07:00"), "Decheng Dai")
        XCTAssertEqual(["thu"], decheng.filter(\.hasMine).map(\.key))
        // Before the conference every day is a tab, none is "Today".
        let before = idx.dayTabs(at("2026-11-07T10:00:00-07:00"), lucy)
        XCTAssertEqual(5, before.count)
        XCTAssertTrue(before.allSatisfy { $0.label != "Today" })
    }

    // MARK: - banner

    func testWednesdayBannerShowsLucysThreeTalks() {
        let b = idx.banner("wed", at("2026-11-11T08:00:00-07:00"), lucy)!
        XCTAssertEqual("1363905", b.next.id) // 9:45 keynote, inside the Morning keynotes group
        XCTAssertEqual("wed-key", idx.groupKeyOf(b.next.id))
        XCTAssertEqual("9:45 AM", b.nextTime)
        XCTAssertEqual("In 1h 45m", b.countdown)
        XCTAssertFalse(b.soon)
        XCTAssertEqual("Hall DE · Salt Palace L1 · Keynote", b.nextWhere)
        XCTAssertEqual(["1249844", "1289660"], b.later.map(\.session.id))
        XCTAssertEqual(["2:20 PM", "5:00 PM"], b.later.map(\.time))
        XCTAssertEqual(["Grand Ballroom GI", "251 A–C"], b.later.map(\.roomName))
    }

    func testBannerCountsDownAndSaysHeadToWhenSoon() {
        let live = idx.banner("wed", at("2026-11-11T09:46:00-07:00"), lucy)!
        XCTAssertEqual("On now", live.countdown)
        XCTAssertTrue(live.soon)
        XCTAssertTrue(live.live)
        XCTAssertEqual("Head to Hall DE · Salt Palace L1 · Keynote", live.nextWhere)

        let gi = idx.banner("wed", at("2026-11-11T13:40:00-07:00"), lucy)!
        XCTAssertEqual("1249844", gi.next.id)
        XCTAssertEqual("In 40 min", gi.countdown)
        XCTAssertTrue(gi.soon)
        XCTAssertEqual("Head to Grand Ballroom GI · Salt Palace L1", gi.nextWhere)
        XCTAssertEqual(["1289660"], gi.later.map(\.session.id))

        let notYet = idx.banner("wed", at("2026-11-11T13:30:00-07:00"), lucy)!
        XCTAssertEqual("In 50 min", notYet.countdown)
        XCTAssertFalse(notYet.soon)
        XCTAssertEqual("Grand Ballroom GI · Salt Palace L1", notYet.nextWhere)

        let last = idx.banner("wed", at("2026-11-11T16:30:00-07:00"), lucy)!
        XCTAssertEqual("1289660", last.next.id)
        XCTAssertEqual("Head to 251 A–C · Salt Palace L2", last.nextWhere)
        XCTAssertTrue(last.later.isEmpty)

        XCTAssertNil(idx.banner("wed", at("2026-11-11T17:30:00-07:00"), lucy))
    }

    func testBannerForAnotherDaySaysTomorrowOrTheWeekday() {
        let tue = idx.banner("wed", at("2026-11-10T12:00:00-07:00"), lucy)!
        XCTAssertEqual("Tomorrow", tue.countdown)
        XCTAssertEqual("Wed 9:45 AM", tue.nextTime)
        XCTAssertFalse(tue.soon)
        XCTAssertEqual(["2:20 PM", "5:00 PM"], tue.later.map(\.time))
        let mon = idx.banner("wed", at("2026-11-09T12:00:00-07:00"), lucy)!
        XCTAssertEqual("Wednesday", mon.countdown)
    }

    func testNoBannerOnDaysWithoutMyTalksForNoneOrWhileSearching() {
        let now = at("2026-11-10T09:00:00-07:00")
        for d in ["sun", "mon", "tue", "thu"] { XCTAssertNil(idx.banner(d, now, lucy), d) }
        XCTAssertNil(idx.banner("wed", now, nil))
        XCTAssertNil(idx.banner("wed", now, lucy, searching: true))
        XCTAssertNil(idx.banner(nil, now, lucy))
        // Another speaker gets their own banner.
        let d = idx.banner("thu", now, "Decheng Dai")!
        XCTAssertEqual(["1250150", "1228453"], [d.next.id] + d.later.map(\.session.id))
    }

    // MARK: - search

    private func searchIds(_ q: String, now: String = "2026-11-08T08:00:00-07:00", me: String? = "Lucy Sweet") -> [String] {
        idx.search(q, at(now), me).days.flatMap(\.sessions).map(\.session.id)
    }

    func testSearchMatchesTitleSpeakerRoomAndCategoryIgnoringCaseAndAccents() {
        XCTAssertTrue(searchIds("EVICTION").contains("1289660"))
        XCTAssertTrue(searchIds("krepinsky").contains("1289660")) // Filip Křepinský
        XCTAssertTrue(searchIds("Křepinský").contains("1289660"))
        XCTAssertTrue(searchIds("rozacki").contains("1247612")) // Maciek Różacki
        let roomHits = searchIds("251 a–c")
        XCTAssertFalse(roomHits.isEmpty)
        XCTAssertTrue(roomHits.allSatisfy { id in
            let x = s(id)
            return x.room == "251AC" || x.title.kotlinContains("251") || x.speakers.contains { $0.kotlinContains("251") }
        })
        XCTAssertEqual(roomHits, searchIds("251 a-c")) // en dash or hyphen
        let maint = searchIds("maintainer")
        XCTAssertTrue(maint.contains { idx.category(s($0)) == "mnt" && !s($0).title.lowercased().kotlinContains("maintainer") })
        // All terms must match.
        XCTAssertEqual(["1289660"], searchIds("eviction lucy"))
        XCTAssertTrue(searchIds("eviction zzzz").isEmpty)
    }

    func testSearchCoversTheRestOfTheWeekWithoutBreaks() {
        let all = idx.search("kubernetes", at("2026-11-11T12:00:00-07:00"), lucy)
        let ids = all.days.flatMap(\.sessions).map(\.session.id)
        XCTAssertEqual(all.count, ids.count)
        XCTAssertEqual(["wed", "thu"], all.days.map(\.day.key))
        for id in ids { XCTAssertFalse(ScheduleLogic.isFinished(s(id), at("2026-11-11T12:00:00-07:00"))) }
        for d in all.days { XCTAssertEqual(d.sessions.stableSorted(on: { $0.start }), d.sessions) }
        XCTAssertTrue(searchIds("coffee").allSatisfy { !idx.isBreak(s($0)) })
        XCTAssertTrue(searchIds("lunch").allSatisfy { !idx.isBreak(s($0)) })
        // The misfiled "Breaking…" talks are searchable.
        XCTAssertTrue(searchIds("helm 4").contains("1289638"))
        XCTAssertEqual("1 match", SearchResults(1, []).heading)
        XCTAssertEqual("0 matches", idx.search("zzzz", at("2026-11-08T08:00:00-07:00"), lucy).heading)
        XCTAssertEqual(0, idx.search("   ", at("2026-11-08T08:00:00-07:00"), lucy).count)
    }

    func testAnthropicKeywordFollowsTheSetting() {
        let withLucy = Set(searchIds("anthropic"))
        XCTAssertTrue(withLucy.contains("1249844")) // mine
        XCTAssertTrue(withLucy.contains("1203350")) // colleague
        let withNone = Set(searchIds("anthropic", me: nil))
        XCTAssertTrue(withNone.contains("1249844")) // Lucy is a colleague under None
        let withOther = Set(searchIds("anthropic", me: "Graham Helton"))
        XCTAssertTrue(withOther.contains("1203350")) // his own talk counts as mine
    }

    func testCardStatusForLiveCards() {
        let eviction = s("1289660")
        let st = idx.cardStatus(eviction, at("2026-11-11T17:10:00-07:00"))
        XCTAssertTrue(st.live)
        XCTAssertEqual("Live · 20 min left", st.liveLabel)
        XCTAssertNotNil(st.progress)
        XCTAssertEqual(CardStatus.NotLive, idx.cardStatus(eviction, at("2026-11-11T16:00:00-07:00")))
        let hackathon = s("1344383") // off-site, long
        let h = idx.cardStatus(hackathon, at("2026-11-08T10:00:00-07:00"))
        XCTAssertEqual("On now", h.liveLabel)
        XCTAssertNil(h.progress)
    }
}

private extension DayView {
    func allSessionIds() -> [String] {
        slots.flatMap { sl in sl.blocks.flatMap { $0.sessions.map(\.id) } } + longs.map(\.session.id)
    }
}

private extension Array {
    /// Kotlin `single { }`: the one element matching; throws (failing the test) otherwise.
    func singleMatch(file: StaticString = #filePath, line: UInt = #line, _ predicate: (Element) -> Bool) throws -> Element {
        let xs = filter(predicate)
        return try XCTUnwrap(xs.count == 1 ? xs[0] : nil, "single: \(xs.count) matches", file: file, line: line)
    }
}

/// Small helpers for readable assertions.
private enum TimeFormatMinute {
    static func of(_ t: Date) -> Int { TimeFormat.minuteOfDay(t) }
    static func hhmm(_ t: Date) -> Int {
        let m = of(t)
        return (m / 60) * 100 + m % 60
    }
}
