import XCTest
@testable import KCNA26Core

/// Port of schedule/ColocatedTest.kt: the Monday "Co-located events" cards: lines, agendas,
/// hiding, de-duplication, search, mine/Anthropic.
final class ColocatedTests: XCTestCase {
    private let repo = TestData.repo
    private lazy var idx = ScheduleIndex.of(repo)
    private let lucy = "Lucy Sweet"

    private func at(_ iso: String) -> Date { TestData.instant(iso) }
    private func cards(_ iso: String, _ me: String? = "Lucy Sweet") -> [ColoCard] { idx.dayView("mon", at(iso), me)!.colo }
    private func card(_ key: String, _ iso: String, _ me: String? = "Lucy Sweet", file: StaticString = #filePath, line: UInt = #line) throws -> ColoCard {
        try cards(iso, me).singleMatch(file: file, line: line) { $0.key == key }
    }
    private func lines(_ key: String, _ iso: String, file: StaticString = #filePath, line: UInt = #line) throws -> [String] {
        let roomName = idx.roomName
        return try card(key, iso, file: file, line: line).lines.map { ColoText.text($0, roomName) }
    }

    // MARK: - cards

    func testOneCardPerEventAlphabeticalWithHoursAndMainRoom() throws {
        let all = cards("2026-11-09T08:00:00-07:00")
        XCTAssertEqual(
            [
                "Agentics Day: MCP + Agents", "ArgoCon", "BackstageCon", "CiliumCon", "Cloud Native AI + Inference Day",
                "FluxCon", "Kubernetes on Edge Day", "Observability Day", "Open Source SecurityCon", "OpenTofu Day",
                "Platform Engineering Day",
            ],
            all.map(\.event.name)
        )
        let argo = try all.singleMatch { $0.key == "colo-argocon" }
        XCTAssertEqual("9:00 AM–5:45 PM", argo.hours)
        XCTAssertEqual("Room 151", idx.roomName(argo.event.mainRoom))
        XCTAssertEqual("Salt Palace L1", idx.building(argo.event.mainRoom))
        XCTAssertEqual("Half day · 9:00 AM–12:30 PM", try all.singleMatch { $0.key == "colo-ciliumcon" }.hours)
        XCTAssertEqual("Half day · 1:20–5:30 PM", try all.singleMatch { $0.key == "colo-kubernetes-on-edge-day" }.hours)
        XCTAssertEqual(["Half day", "9:00 AM–12:30 PM"], ColoText.hoursParts(repo.coloEvent("colo-ciliumcon")!))
        XCTAssertEqual(["9:00 AM–5:45 PM"], ColoText.hoursParts(argo.event))
        // Other days have no co-located section.
        for d in ["sun", "tue", "wed", "thu"] { XCTAssertTrue(idx.dayView(d, at("2026-11-08T08:00:00-07:00"), lucy)!.colo.isEmpty, d) }
    }

    func testBeforeTheEventItSaysWhenItStartsAndTheFirstRealTalk() throws {
        // The opening remarks (9:00) are skipped: the first talk is the 9:10 project update, and the
        // line says so rather than pairing 9:00 with a talk that starts at 9:10.
        let first = "Starts 9:00 AM · First talk 9:10 · ArgoCon Project Update"
        XCTAssertEqual([first], try lines("colo-argocon", "2026-11-09T08:00:00-07:00"))
        // The day before, too.
        XCTAssertEqual([first], try lines("colo-argocon", "2026-11-08T20:00:00-07:00"))
        // An afternoon half day during the morning.
        let edge = try card("colo-kubernetes-on-edge-day", "2026-11-09T11:00:00-07:00")
        XCTAssertEqual(1, edge.lines.count)
        let st = try XCTUnwrap(edge.lines.first?.asStarts)
        XCTAssertEqual(at("2026-11-09T13:20:00-07:00"), st.at)
        XCTAssertFalse(ColoText.isRemarks(try XCTUnwrap(st.session)))
        XCTAssertTrue(ColoText.label(.starts(st), idx.roomName).kotlinStartsWith("Starts 1:20 PM · First talk "))
        XCTAssertFalse(edge.live)
        // Every event opens with remarks, so every card names its first real talk with that talk's time.
        for c in cards("2026-11-09T08:00:00-07:00") {
            XCTAssertEqual(1, c.lines.count, c.key)
            let line = try XCTUnwrap(c.lines.first?.asStarts, c.key)
            let talk = try XCTUnwrap(line.session, c.key)
            let label = ColoText.label(.starts(line), idx.roomName)
            if talk.start.isAfter(line.at) {
                XCTAssertTrue(label.kotlinEndsWith("· First talk " + TimeFormat.hm(talk.start)), c.key)
            } else {
                XCTAssertEqual("Starts " + TimeFormat.hma(line.at), label, c.key)
            }
        }
    }

    func testDuringATalkItSaysNowWithMinutesLeftThenNext() throws {
        let c = try card("colo-argocon", "2026-11-09T09:20:00-07:00")
        XCTAssertTrue(c.live)
        XCTAssertEqual(
            [
                "Now · 15 min left · ArgoCon Project Update",
                "Next 9:45 · Pets, Cattle, and Herds: Fleet-Scale Continuous Delivery the GitOps Way",
            ],
            c.lines.map { ColoText.text($0, idx.roomName) }
        )
        let now = try XCTUnwrap(c.lines[0].asNow)
        XCTAssertEqual("1311951", now.session.id)
        XCTAssertEqual(15, now.minutesLeft)
        XCTAssertNil(now.room) // main room
        // The welcome remarks are "Now" while they're on.
        XCTAssertEqual("Now · 5 min left · Welcome + Opening Remarks", try lines("colo-argocon", "2026-11-09T09:00:00-07:00")[0])
    }

    func testTwoTracksGiveOneNowLineMainRoomFirstThenNext() throws {
        // A collapsed card stays compact: one "Now" line (the main room's talk) and "Next"; the
        // second room's talk is in the agenda.
        let c = try card("colo-argocon", "2026-11-09T10:50:00-07:00")
        XCTAssertEqual(
            [
                "Now · 15 min left · Beating the Final Boss: GitOps Promoter in Production",
                "Next 11:15 · Securing the Repo Server: A Practical Guide to Argo CD’s New Native mTLS",
            ],
            c.lines.map { ColoText.text($0, idx.roomName) }
        )
        XCTAssertTrue(c.agenda.contains { $0.room == "251AC" && $0.live })
        // Only the second room has a talk on (Observability Day, 5:10 PM): the Now line names that room.
        let obs = try card("colo-observability-day", "2026-11-09T17:10:00-07:00")
        let now = try XCTUnwrap(obs.lines.first?.asNow)
        XCTAssertEqual("1239971", now.session.id)
        XCTAssertEqual("250DF", now.room)
        // All day long, on every card: at most two lines, at most one of them "Now".
        var t = at("2026-11-08T20:00:00-07:00")
        while t.isBefore(at("2026-11-09T18:00:00-07:00")) {
            for k in idx.dayView("mon", t, lucy)!.colo {
                XCTAssertTrue(k.lines.count <= 2, "\(k.key) \(t)")
                XCTAssertTrue(k.lines.filter { $0.asNow != nil }.count <= 1, "\(k.key) \(t)")
            }
            t = t.plusSeconds(5 * 60)
        }
    }

    func testInAGapItSaysWhatsNextAndNamesTheBreakIfOneIsOn() throws {
        // 9:37: the project update ended at 9:35; nothing on until 9:45.
        XCTAssertEqual(
            ["Next 9:45 · Pets, Cattle, and Herds: Fleet-Scale Continuous Delivery the GitOps Way"],
            try lines("colo-argocon", "2026-11-09T09:37:00-07:00")
        )
        // ArgoCon's coffee break (10:15–10:40) and lunch (11:40–12:45). At equal starts the main room comes first.
        XCTAssertEqual(
            ["Coffee Break · Next 10:40 · Beating the Final Boss: GitOps Promoter in Production"],
            try lines("colo-argocon", "2026-11-09T10:20:00-07:00")
        )
        let lunch = try card("colo-argocon", "2026-11-09T12:00:00-07:00")
        XCTAssertFalse(lunch.live)
        XCTAssertEqual(1, lunch.lines.count)
        let next = try XCTUnwrap(lunch.lines.first?.asNext)
        XCTAssertEqual("Lunch", next.during)
        XCTAssertEqual("12:55", TimeFormat.hm(next.session.start))
    }

    func testCardsDisappearWhenTheirEventEnds() throws {
        // CiliumCon (half day) ends at 12:30 with its closing remarks; its lunch starts then.
        let cilium = try card("colo-ciliumcon", "2026-11-09T12:29:00-07:00")
        XCTAssertEqual(1, cilium.lines.count)
        XCTAssertEqual("Now · 1 min left · Closing Remarks", ColoText.text(cilium.lines[0], idx.roomName))
        XCTAssertEqual(["Closing Remarks", "🍲 Lunch"], cilium.agenda.map(\.session.title))
        XCTAssertTrue(cards("2026-11-09T12:30:00-07:00").allSatisfy { $0.key != "colo-ciliumcon" })
        // ArgoCon is the last to end (5:45 PM); then the section is empty and the day goes on with the blocks.
        XCTAssertEqual(["colo-argocon"], cards("2026-11-09T17:30:00-07:00").map(\.key))
        XCTAssertEqual(1, cards("2026-11-09T17:44:00-07:00").count)
        XCTAssertTrue(cards("2026-11-09T17:45:00-07:00").isEmpty)
        let evening = idx.dayView("mon", at("2026-11-09T17:45:00-07:00"), lucy)!
        XCTAssertFalse(evening.isEmpty) // the reception and the documentary are still to come
        XCTAssertTrue(idx.dayView("mon", at("2026-11-09T23:00:00-07:00"), lucy)!.isEmpty)
    }

    func testABreakThatOutlivesItsEventJoinsTheTimeBlocks() throws {
        // CiliumCon ends at 12:30 as its lunch (12:30–1:30, LCH4) starts; FluxCon's lunch starts at its 12:55 end.
        // While the event is on, its break is only in its card; once the card has gone it's a quiet block row.
        let before = idx.dayView("mon", at("2026-11-09T12:29:00-07:00"), lucy)!
        XCTAssertTrue(try before.colo.singleMatch { $0.key == "colo-ciliumcon" }.holds("1309414"))
        XCTAssertTrue(before.blockSessions().allSatisfy { !($0.isColocated && idx.isBreak($0)) })
        let at1230 = idx.dayView("mon", at("2026-11-09T12:30:00-07:00"), lucy)!
        XCTAssertTrue(at1230.colo.allSatisfy { $0.key != "colo-ciliumcon" })
        XCTAssertEqual(["1309414"], at1230.blockSessions().filter { $0.isColocated && idx.isBreak($0) }.map(\.id))
        let row = try at1230.slots.flatMap(\.blocks).compactMap(\.sessionBlock).singleMatch { $0.session.id == "1309414" }
        XCTAssertEqual("log", row.category)
        let at1255 = idx.dayView("mon", at("2026-11-09T12:55:00-07:00"), lucy)!
        XCTAssertTrue(at1255.colo.allSatisfy { $0.key != "colo-fluxcon" })
        XCTAssertEqual(["1309414", "1309427"], at1255.blockSessions().filter { $0.isColocated && idx.isBreak($0) }.map(\.id))
        // The shared lunch that's on (12:25–1:30) serves events that are still on: it stays in their cards.
        XCTAssertTrue(at1255.blockSessions().allSatisfy { $0.id != "1309413" })
        let shared = repo.session("1309413")!.coloEvents
        XCTAssertEqual(3, at1255.colo.filter { shared.contains($0.key) && $0.holds("1309413") }.count)
        // Finished breaks go, as usual.
        XCTAssertTrue(idx.dayView("mon", at("2026-11-09T13:30:00-07:00"), lucy)!.blockSessions().allSatisfy { !($0.isColocated && idx.isBreak($0)) })
        // No co-located talk ever falls into the blocks: an unfinished talk's event is always on.
        var t = at("2026-11-09T08:00:00-07:00")
        while t.isBefore(at("2026-11-09T18:00:00-07:00")) {
            let blocks = idx.dayView("mon", t, lucy)!.blockSessions()
            XCTAssertTrue(blocks.allSatisfy { !($0.isColocated && idx.category($0) == "colo") }, "\(t)")
            t = t.plusSeconds(5 * 60)
        }
    }

    func testAgendaHidesFinishedTalksKeepsBreaksQuietAndNamesOtherRooms() throws {
        let c = try card("colo-argocon", "2026-11-09T10:50:00-07:00")
        let now = at("2026-11-09T10:50:00-07:00")
        XCTAssertTrue(c.agenda.allSatisfy { !ScheduleLogic.isFinished($0.session, now) })
        XCTAssertEqual(c.agenda.map(\.session.start).sorted(), c.agenda.map(\.session.start))
        XCTAssertEqual("1269659", c.agenda[0].session.id) // 151 before 251 A–C at 10:40
        XCTAssertNil(c.agenda[0].room)
        XCTAssertEqual("251AC", c.agenda[1].room)
        XCTAssertTrue(c.agenda[0].live && c.agenda[1].live)
        let breaks = c.agenda.filter(\.isBreak)
        XCTAssertEqual(["🍲 Lunch", "☕ Coffee Break"], breaks.map(\.session.title))
        XCTAssertEqual(["LCH4", "FOY"], breaks.map(\.room)) // breaks always say where
        // Every agenda row is a real session the details can open; ArgoCon's talks are all there at 8 AM.
        let morning = try card("colo-argocon", "2026-11-09T08:00:00-07:00")
        XCTAssertEqual(29, morning.agenda.filter { !$0.isBreak }.count)
        XCTAssertTrue(morning.agenda.allSatisfy { repo.session($0.session.id) != nil })
    }

    // MARK: - time blocks and hiding

    func testPlaceholdersAreNeverShown() {
        let placeholders = repo.supersededIds
        XCTAssertEqual(11, placeholders.count)
        for iso in ["2026-11-08T12:00:00-07:00", "2026-11-09T08:00:00-07:00", "2026-11-09T13:00:00-07:00"] {
            let mon = idx.dayView("mon", at(iso), lucy)!
            let shown = (mon.blockSessions() + mon.longs.map(\.session)).map(\.id)
            XCTAssertTrue(shown.allSatisfy { !placeholders.contains($0) }, iso)
        }
        XCTAssertTrue(idx.search("argocon", at("2026-11-09T08:00:00-07:00"), lucy).days.flatMap(\.sessions).allSatisfy { !placeholders.contains($0.session.id) })
        XCTAssertTrue(idx.search("all-access", at("2026-11-09T08:00:00-07:00"), lucy).days.flatMap(\.sessions).allSatisfy { !placeholders.contains($0.session.id) })
        XCTAssertTrue(placeholders.allSatisfy { idx.isHidden(repo.session($0)!) })
        // Still loadable by id (an old saved selection opens rather than vanishing).
        XCTAssertNotNil(repo.session("1289755"))
    }

    func testCoLocatedTalksAndBreaksStayOutOfTheTimeBlocks() {
        let mon = idx.dayView("mon", at("2026-11-09T08:00:00-07:00"), lucy)!
        let inBlocks = mon.blockSessions()
        // Only the Evening Reception (an ordinary social session) comes from colocated.json.
        XCTAssertEqual(["1309453"], inBlocks.filter(\.isColocated).map(\.id))
        XCTAssertEqual("soc", idx.category(repo.session("1309453")!))
        // No group card for an event: they're the cards above.
        XCTAssertTrue(mon.slots.flatMap(\.blocks).compactMap(\.groupBlock).allSatisfy { !$0.group.key.kotlinStartsWith("colo-") })
        XCTAssertTrue(idx.groups.keys.allSatisfy { !$0.kotlinStartsWith("colo-") })
        // Status line still counts the co-located talks on now.
        let ten = idx.dayView("mon", at("2026-11-09T10:50:00-07:00"), lucy)!
        XCTAssertTrue(ten.status!.onNow > 10)
    }

    func testBreaksAreDeDuplicated() throws {
        // Real data: Monday's own break rows (the Project Lightning Talks') show once each and the
        // co-located breaks only inside their events' cards: in every card of an event they serve.
        let mon = idx.dayView("mon", at("2026-11-09T08:00:00-07:00"), lucy)!
        let blockBreaks = mon.blockSessions().filter { idx.isBreak($0) }
        XCTAssertEqual(["1352094", "1339249", "1368701"], blockBreaks.map(\.id))
        let coloBreaks = repo.sessions.filter { $0.isColocated && idx.isBreak($0) }
        XCTAssertEqual(10, coloBreaks.count)
        for b in coloBreaks {
            for key in b.coloEvents {
                XCTAssertEqual(1, try mon.colo.singleMatch { $0.key == key }.agenda.filter { $0.session.id == b.id }.count, "\(b.id) in \(key)")
            }
            let others = mon.colo.filter { !b.coloEvents.contains($0.key) }
            XCTAssertTrue(others.allSatisfy { c in !c.agenda.contains { $0.session.id == b.id } }, b.id)
        }

        // A co-located break that is the same break as a day's own row (same start, end and title,
        // emoji aside) shows once, as that quiet row; one that isn't joins the blocks.
        let root = try XCTUnwrap(JSON.parse(TestData.text(Repository.COLOCATED)).objectValue)
        let sessions = try XCTUnwrap(root["sessions"]?.arrayValue)
        let template = try XCTUnwrap(sessions.first { $0["id"] == .string("1309409") }?.objectValue)
        func brk(_ id: String, _ start: String, _ end: String, _ title: String) -> JSONValue {
            let o = template
                .with("id", .string(id))
                .with("start", .string(start))
                .with("end", .string(end))
                .with("title", .string(title))
                .with("coloEvent", .null)
                .with("coloEvents", .array([]))
            return .object(o)
        }
        let same = brk("9000001", "2026-11-09T10:48:00-07:00", "2026-11-09T11:03:00-07:00", "Coffee Break")
        let other = brk("9000002", "2026-11-09T16:00:00-07:00", "2026-11-09T16:15:00-07:00", "☕ Coffee Break")
        let text = JSON.serialize(.object(root.with("sessions", .array(sessions + [same, other]))))
        let synthetic = try Repository.load { name in
            if name == Repository.COLOCATED { return Data(text.utf8) }
            return try Data(contentsOf: TestData.assetsDir.appendingPathComponent(name))
        }
        let sIdx = ScheduleIndex(synthetic)
        let day = sIdx.dayView("mon", at("2026-11-09T08:00:00-07:00"), lucy)!
        let rows = day.blockSessions().filter { sIdx.isBreak($0) }.map(\.id)
        XCTAssertEqual(["1352094", "1339249", "1368701", "9000002"], rows) // 10:48 once; 4:00 PM joins
        XCTAssertNotNil(synthetic.session("9000001")) // loaded, just not shown twice
    }

    // MARK: - search

    func testSearchFindsEveryTalkOfAnEventByItsName() {
        func hits(_ q: String, _ iso: String = "2026-11-09T08:00:00-07:00") -> [Session] {
            idx.search(q, at(iso), lucy).days.flatMap(\.sessions).map(\.session)
        }
        let argo = hits("argocon")
        let argoTalks = repo.sessions.filter { $0.coloEvent == "colo-argocon" && $0.category == "colo" }
        XCTAssertEqual(29, argoTalks.count)
        XCTAssertTrue(argoTalks.allSatisfy { argo.contains($0) })
        XCTAssertTrue(argo.allSatisfy { !idx.isBreak($0) })
        XCTAssertTrue(argoTalks.allSatisfy { idx.coloEventOf($0)?.name == "ArgoCon" }) // the result rows' eyebrow
        // Case, accents and several terms: "ARGOCON 251" = ArgoCon's second-track talks.
        let track2 = hits("ARGOCON 251")
        XCTAssertFalse(track2.isEmpty)
        XCTAssertTrue(track2.allSatisfy { $0.coloEvent == "colo-argocon" && $0.room == "251AC" })
        XCTAssertEqual(argoTalks.filter { $0.room == "251AC" }.count, track2.count)
        // Every event, by name; finished talks drop out as the day goes.
        for e in repo.coloEvents {
            let n = hits(e.name).filter { $0.coloEvent == e.key }.count
            XCTAssertEqual(e.talkCount, n, e.name)
        }
        XCTAssertTrue(hits("argocon", "2026-11-09T12:00:00-07:00").count < argo.count)
        XCTAssertTrue(hits("argocon", "2026-11-09T18:00:00-07:00").allSatisfy { $0.coloEvent != "colo-argocon" })
        // Topic, format and speakers work as usual.
        let lightning = hits("lightning argocon")
        XCTAssertEqual(argoTalks.filter { $0.format == "Lightning talk" }.count, lightning.filter { $0.format == "Lightning talk" }.count)
        XCTAssertTrue(hits("lamkin").contains { $0.id == "1312032" })
        let withTopic = repo.sessions.first { $0.isColocated && $0.topic != nil }!
        XCTAssertTrue(hits(withTopic.topic!).contains { $0.id == withTopic.id })
    }

    // MARK: - mine and Anthropic

    func testAnthropicColleagueInsideACard() throws {
        // Jiazhou Gao (Anthropic) on Cloud Native AI + Inference Day, 2:05 PM in 254.
        let ai = try card("colo-cloud-native-ai-inference-day", "2026-11-09T08:00:00-07:00")
        XCTAssertTrue(ai.anthropic)
        XCTAssertFalse(ai.mine)
        let row = try ai.agenda.singleMatch { $0.session.id == "1245135" }
        XCTAssertTrue(row.anthropic)
        XCTAssertFalse(row.mine)
        XCTAssertTrue(ai.agenda.filter { $0.session.id != "1245135" }.allSatisfy { !$0.anthropic })
        // Once the talk is over the card no longer carries the mark.
        XCTAssertFalse(try card("colo-cloud-native-ai-inference-day", "2026-11-09T14:30:00-07:00").anthropic)
        // Only that card has it; "anthropic" search finds the talk.
        XCTAssertEqual(["colo-cloud-native-ai-inference-day"], cards("2026-11-09T08:00:00-07:00").filter(\.anthropic).map(\.key))
        XCTAssertTrue(idx.search("anthropic", at("2026-11-09T08:00:00-07:00"), lucy).days.flatMap(\.sessions).contains { $0.session.id == "1245135" && $0.anthropic })
    }

    func testMyCoLocatedTalksAreMineEverywhere() throws {
        let katie = "Katie Lamkin-Fulsher" // ArgoCon: opening remarks 9:00, a keynote 9:55, closing remarks 5:40
        let argo = try card("colo-argocon", "2026-11-09T08:00:00-07:00", katie)
        XCTAssertTrue(argo.mine)
        XCTAssertEqual(["1312032", "1311947", "1312052"], argo.agenda.filter(\.mine).map(\.session.id))
        XCTAssertTrue(argo.agenda.filter(\.mine).allSatisfy { !$0.anthropic })
        XCTAssertEqual(["colo-argocon"], cards("2026-11-09T08:00:00-07:00", katie).filter(\.mine).map(\.key))
        // Still mine at noon (the closing remarks are to come); the YOU badge on Monday's tab and the banner follow.
        XCTAssertTrue(try card("colo-argocon", "2026-11-09T12:00:00-07:00", katie).mine)
        XCTAssertTrue(try idx.dayTabs(at("2026-11-09T08:00:00-07:00"), katie).singleMatch { $0.key == "mon" }.hasMine)
        let b = idx.banner("mon", at("2026-11-09T08:00:00-07:00"), katie)!
        XCTAssertEqual("1312032", b.next.id)
        XCTAssertEqual("Room 151 · Salt Palace L1", b.nextWhere)
        XCTAssertEqual(["1311947", "1312052"], b.later.map(\.session.id))
        XCTAssertEqual(["9:55 AM", "5:40 PM"], b.later.map(\.time))
        // Reminders cover any session that's mine.
        let plan = ReminderPlanner.plan(repo.sessions, repo.rooms, katie, at("2026-11-09T08:00:00-07:00"))
        XCTAssertEqual(Set(["1312032", "1311947", "1312052"]), Set(plan.map(\.sessionId)))
        XCTAssertEqual(6, plan.count) // 30 and 10 min before each
        XCTAssertEqual("Your talk in 10 min · Room 151, Level 1", plan.first { $0.minutesBefore == 10 }!.text)
        // The default speaker (Lucy) has nothing on Monday.
        XCTAssertTrue(cards("2026-11-09T08:00:00-07:00").allSatisfy { !$0.mine })
        XCTAssertNil(idx.banner("mon", at("2026-11-09T08:00:00-07:00"), lucy))
        // As Jiazhou Gao: the talk is mine, not an Anthropic colleague's.
        let gao = try card("colo-cloud-native-ai-inference-day", "2026-11-09T08:00:00-07:00", "Jiazhou Gao")
        XCTAssertTrue(gao.mine)
        XCTAssertFalse(gao.anthropic)
    }

    func testLineTextsAndLabels() {
        let s = repo.session("1311951")!
        let roomName: (String) -> String = idx.roomName
        XCTAssertEqual("Now · 3 min left · 251 A–C", ColoText.label(.now(ColoLine.Now(s, 3, "251AC")), roomName))
        XCTAssertEqual("Lunch · Next 9:10", ColoText.label(.next(ColoLine.Next(s, nil, "Lunch")), roomName))
        XCTAssertEqual("Next 9:10 · 251 A–C · ArgoCon Project Update", ColoText.text(.next(ColoLine.Next(s, "251AC", nil)), roomName))
        // A first talk that starts with the event needs no "First talk" time.
        XCTAssertEqual("Starts 9:10 AM", ColoText.label(.starts(ColoLine.Starts(at("2026-11-09T09:10:00-07:00"), s)), roomName))
        XCTAssertEqual("Starts 9:00 AM · First talk 9:10", ColoText.label(.starts(ColoLine.Starts(at("2026-11-09T09:00:00-07:00"), s)), roomName))
        // An agenda break row: its time column has the start, so the text gives the end and the place.
        XCTAssertEqual(
            "Coffee Break · until 10:40 · Meeting room foyers",
            ColoText.breakParts(repo.session("1309409")!, "FOY", roomName).joined(separator: " · ")
        )
        XCTAssertEqual(["Lunch", "until 1:30"], ColoText.breakParts(repo.session("1309414")!, nil, roomName))
        XCTAssertTrue(ColoText.isRemarks(repo.session("1312032")!))
        XCTAssertTrue(ColoText.isRemarks(repo.session("1312052")!))
        XCTAssertFalse(ColoText.isRemarks(s))
        XCTAssertEqual("Co-located events", ColoText.SECTION)
    }
}

private extension DayView {
    func blockSessions() -> [Session] { slots.flatMap { sl in sl.blocks.flatMap(\.sessions) } }
}
