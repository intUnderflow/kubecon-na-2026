import XCTest
@testable import KCNA26Core

/// Port of data/ColocatedRepositoryTest.kt: colocated.json merged into the Repository
/// (sessions, events, rooms, Anthropic speakers, details).
final class ColocatedRepositoryTests: XCTestCase {
    private let repo = TestData.repo
    private var colo: [Session] { repo.sessions.filter(\.isColocated) }

    private func instant(_ iso: String) -> Date { try! parseOffsetDateTime(iso) }

    /// A file under the repository's data/ folder.
    private func dataFile(_ name: String) -> URL? {
        let u = TestData.publishedDataDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// The real data, with colocated.json replaced by `colocated` and colocated_details.json by
    /// `details` (nil: the file is missing). Internal: the Schedule tests use it too.
    static func loadWith(_ colocated: String?, details: String? = TestData.text(Repository.COLOCATED_DETAILS)) throws -> Repository {
        try Repository.load { name in
            switch name {
            case Repository.COLOCATED:
                guard let colocated else { throw CocoaError(.fileReadNoSuchFile) }
                return Data(colocated.utf8)
            case Repository.COLOCATED_DETAILS:
                guard let details else { throw CocoaError(.fileReadNoSuchFile) }
                return Data(details.utf8)
            default:
                return try Data(contentsOf: TestData.dataDir.appendingPathComponent(name))
            }
        }
    }

    private func loadWith(_ colocated: String?, details: String? = TestData.text(Repository.COLOCATED_DETAILS)) throws -> Repository {
        try Self.loadWith(colocated, details: details)
    }

    /// The three broken colocated.json inputs of `theScheduleStillLoadsWithoutColocatedJson`:
    /// missing, not JSON, and a bad date (which drops the whole co-located merge).
    static func colocatedJsonFailures() -> [String?] {
        let original = TestData.text(Repository.COLOCATED)
        let badDate = original.replaceFirst("\"start\": \"2026-11-09T09:00:00-07:00\"", "\"start\": \"9 AM Monday\"")
        precondition(badDate != original)
        return [nil, "{ not json", badDate]
    }

    private func coloJson() -> OrderedMap<String, JSONValue> {
        TestData.json(Repository.COLOCATED).objectValue!
    }

    func testMergeCounts() throws {
        XCTAssertEqual(615 + 223, repo.sessions.count)
        XCTAssertEqual(223, colo.count)
        XCTAssertEqual(212, colo.filter { $0.category == "colo" }.count) // talks
        XCTAssertEqual(10, colo.filter { $0.category == "log" }.count) // breaks
        XCTAssertEqual(1, colo.filter { $0.category == "soc" }.count) // the Evening Reception
        XCTAssertTrue(colo.allSatisfy { $0.day == "mon" && $0.event == Session.EVENT_COLOCATED })
        // Events, the placeholders they replace, rooms.
        XCTAssertEqual(11, repo.coloEvents.count)
        XCTAssertEqual(repo.coloEvents.map(\.name).stableSorted(with: .caseInsensitiveOrder), repo.coloEvents.map(\.name))
        XCTAssertEqual(212, repo.coloEvents.reduce(0) { $0 + $1.talkCount })
        XCTAssertEqual(11, repo.supersededIds.count)
        XCTAssertEqual(40, repo.rooms.count) // rooms.json only: the walking graph's rooms are unchanged
        XCTAssertEqual(Set(["FOY", "LCH4"]), Set(repo.extraRooms.keys))
        XCTAssertTrue(repo.extraRooms.values.allSatisfy { !$0.hasPosition })
        // Details: every co-located session is bundled.
        let details = try repo.details
        XCTAssertEqual(562 + 223, details.count)
        XCTAssertTrue(colo.allSatisfy { details.containsKey($0.id) })
    }

    func testIdsAreUniqueAcrossTheMergedList() throws {
        XCTAssertEqual(repo.sessions.count, Set(repo.sessions.map(\.id)).count)
        XCTAssertEqual(repo.sessions.count, repo.sessionsById.count)
        // A co-located id that collides with schedule.json is dropped, keeping schedule.json's session.
        let root = coloJson()
        let sessions = try XCTUnwrap(root["sessions"]?.arrayValue)
        let first = try XCTUnwrap(sessions[0].objectValue)
        let clash = JSONValue.object(first.with("id", .string("1289955"))) // a Project Lightning Talk
        let loaded = try loadWith(JSONValue.object(root.with("sessions", .array([clash] + sessions.dropFirst()))).compactString)
        XCTAssertEqual(838 - 1, loaded.sessions.count)
        XCTAssertEqual(loaded.sessions.count, loaded.sessionsById.count)
        XCTAssertEqual("kubecon", try XCTUnwrap(loaded.session("1289955")).event)
    }

    func testSessionsKeepTheirCoLocatedFields() throws {
        let talk = try XCTUnwrap(repo.session("1311951")) // ArgoCon Project Update, 9:10 in Room 151
        XCTAssertEqual("colo-argocon", talk.coloEvent)
        XCTAssertEqual(["colo-argocon"], talk.coloEvents)
        XCTAssertEqual(SessionGroup("colo-argocon", "ArgoCon"), talk.group)
        XCTAssertEqual("151", talk.room)
        XCTAssertEqual(instant("2026-11-09T09:10:00-07:00"), talk.start)
        XCTAssertEqual("Breakout", talk.format)
        XCTAssertTrue(talk.isColocated)
        XCTAssertFalse(talk.isMaintainerSummit)
        XCTAssertNil(talk.note)
        XCTAssertTrue(talk.officialUrl.hasSuffix("cncf-hosted-co-located-schedule/?id=1311951"))
        let keynote = try XCTUnwrap(repo.session("1311945"))
        XCTAssertEqual("Keynote", keynote.format)
        XCTAssertTrue(keynote.sponsored)
        XCTAssertTrue(colo.filter { $0.slidesUrl != nil }.count > 0)
        XCTAssertTrue(colo.filter { $0.topic != nil }.count > 0)
        // A shared break serves several events; one event's own break names it.
        let lunch = try XCTUnwrap(repo.session("1309415"))
        XCTAssertEqual("log", lunch.category)
        XCTAssertNil(lunch.coloEvent)
        XCTAssertEqual(4, lunch.coloEvents.count)
        XCTAssertEqual("colo-ciliumcon", try XCTUnwrap(repo.session("1309414")).coloEvent)
        // The reception is an ordinary session.
        let reception = try XCTUnwrap(repo.session("1309453"))
        XCTAssertEqual("soc", reception.category)
        XCTAssertTrue(reception.coloEvents.isEmpty)
        XCTAssertEqual("UM", reception.room)
        // schedule.json sessions have none of it.
        XCTAssertTrue(repo.sessions.filter { !$0.isColocated }.allSatisfy { $0.coloEvent == nil && $0.coloEvents.isEmpty && $0.format == nil })
    }

    func testEventsAndThePlaceholdersTheyReplace() throws {
        let argo = try XCTUnwrap(repo.coloEvent("colo-argocon"))
        XCTAssertEqual("ArgoCon", argo.name)
        XCTAssertEqual("mon", argo.day)
        XCTAssertEqual("151", argo.mainRoom)
        XCTAssertEqual(["151", "251AC"], argo.rooms)
        XCTAssertEqual(instant("2026-11-09T09:00:00-07:00"), argo.start)
        XCTAssertEqual(instant("2026-11-09T17:45:00-07:00"), argo.end) // the agenda, not the placeholder's 5:30
        XCTAssertFalse(argo.halfDay)
        XCTAssertEqual("All-Access pass", argo.passNote)
        XCTAssertEqual("1289755", argo.supersedes)
        let placeholder = try XCTUnwrap(repo.session("1289755"))
        XCTAssertEqual("All-Access pass", placeholder.note)
        XCTAssertEqual(placeholder.officialUrl, argo.infoUrl)
        XCTAssertTrue(try XCTUnwrap(argo.pageUrl).hasSuffix("/co-located-events/argocon/"))
        XCTAssertTrue(try XCTUnwrap(repo.coloEvent("colo-ciliumcon")).halfDay)
        for e in repo.coloEvents {
            // Every placeholder still exists (an old saved id still opens) and sits in the event's main room.
            let p = try XCTUnwrap(repo.session(try XCTUnwrap(e.supersedes)))
            XCTAssertEqual("All-Access pass", p.note, e.name)
            XCTAssertEqual(e.mainRoom, p.room, e.name)
            // The card's hours are its talks' (first start to last end).
            let talks = colo.filter { $0.coloEvent == e.key && $0.category == "colo" }
            XCTAssertEqual(e.talkCount, talks.count, e.name)
            XCTAssertEqual(talks.map(\.start).min(), e.start, e.name)
            XCTAssertEqual(talks.map(\.effectiveEnd).max(), e.end, e.name)
            XCTAssertTrue(talks.allSatisfy { $0.group == SessionGroup(e.key, e.name) }, e.name)
        }
    }

    func testEveryRoomResolvesAndNewPlacesHaveNoPosition() throws {
        XCTAssertTrue(repo.sessions.allSatisfy { repo.room($0.room) != nil && repo.roomOf($0) != nil })
        let foy = try XCTUnwrap(repo.room("FOY"))
        XCTAssertEqual("Meeting room foyers", foy.name)
        XCTAssertFalse(foy.hasPosition)
        XCTAssertNotNil(foy.whereText)
        XCTAssertEqual(1, try XCTUnwrap(repo.room("LCH4")).level)
        // Co-located talks are all in rooms.json rooms with a position (Directions work).
        XCTAssertTrue(colo.filter { $0.category == "colo" }.allSatisfy { repo.rooms.containsKey($0.room) && repo.room($0.room)!.hasPosition })
    }

    func testAnthropicSpeakersAndMineAtRuntime() throws {
        XCTAssertTrue(repo.anthropicSpeakers.contains("Jiazhou Gao"))
        XCTAssertTrue(repo.anthropicSpeakers.contains("Lucy Sweet"))
        let gao = try XCTUnwrap(repo.session("1245135"))
        XCTAssertTrue(repo.hasAnthropic(gao, "Lucy Sweet"))
        XCTAssertTrue(isMine(gao, "Jiazhou Gao"))
        XCTAssertFalse(repo.hasAnthropic(gao, "Jiazhou Gao"))
        // The precomputed flags agree with the runtime rule for the default setting.
        for s in colo {
            XCTAssertEqual(s.precomputedIsMine, isMine(s, "Lucy Sweet"), s.id)
            XCTAssertEqual(s.precomputedHasAnthropic, repo.hasAnthropic(s, "Lucy Sweet"), s.id)
        }
        // The details carry the tagline.
        XCTAssertEqual("Member of Technical Staff at Anthropic", try XCTUnwrap(try repo.details["1245135"]).speakers[0].tagline)
        // Co-located speakers are pickable.
        XCTAssertTrue(repo.allSpeakers.contains("Katie Lamkin-Fulsher"))
        XCTAssertEqual(3, repo.mySessions("Katie Lamkin-Fulsher").count)
    }

    func testAssetsMatchTheDataFolder() throws {
        for name in [Repository.COLOCATED, Repository.COLOCATED_DETAILS] {
            let data = try XCTUnwrap(dataFile(name), "data/\(name) not found")
            XCTAssertEqual(try String(contentsOf: data, encoding: .utf8), TestData.text(name), name)
        }
    }

    func testTheDetailsAreAFileOfTheirOwnReadOnlyWhenNeeded() throws {
        // colocated.json, which the splash waits for, carries no descriptions: they're in
        // colocated_details.json, read lazily with details.json.
        let main = coloJson()
        XCTAssertFalse(main.containsKey("details"))
        let details = try XCTUnwrap(TestData.json(Repository.COLOCATED_DETAILS)["details"]?.objectValue)
        XCTAssertEqual(try XCTUnwrap(main["sessions"]?.arrayValue).map { $0["id"]?.primitiveContent }, details.keys)
        // Loading opens colocated_details.json only when the details are first used.
        let opened = Locked<[String]>([])
        let r = try Repository.load { name in
            opened.withLock { $0.append(name) }
            return try Data(contentsOf: TestData.dataDir.appendingPathComponent(name))
        }
        XCTAssertFalse(opened.value.contains(Repository.COLOCATED_DETAILS))
        XCTAssertFalse(opened.value.contains(Repository.DETAILS))
        XCTAssertEqual(615 + 223, r.sessions.count)
        XCTAssertEqual(562 + 223, try r.details.count)
        XCTAssertTrue(opened.value.contains(Repository.COLOCATED_DETAILS))
        XCTAssertEqual(1, opened.value.filter { $0 == Repository.COLOCATED }.count)
        // Without it (or unreadable), the co-located sessions still load; they just have no descriptions.
        for text in [nil, "{ not json"] as [String?] {
            let bare = try loadWith(TestData.text(Repository.COLOCATED), details: text)
            XCTAssertEqual(615 + 223, bare.sessions.count)
            XCTAssertEqual(11, bare.coloEvents.count)
            XCTAssertEqual(562, try bare.details.count)
            XCTAssertNil(try bare.details["1245135"])
        }
    }

    func testTheScheduleStillLoadsWithoutColocatedJson() throws {
        let original = TestData.text(Repository.COLOCATED)
        let badDate = original.replaceFirst("\"start\": \"2026-11-09T09:00:00-07:00\"", "\"start\": \"9 AM Monday\"")
        XCTAssertNotEqual(badDate, original)
        XCTAssertEqual(Self.colocatedJsonFailures(), [nil, "{ not json", badDate])
        for text in [nil, "{ not json", badDate] as [String?] {
            let r = try loadWith(text)
            XCTAssertEqual(615, r.sessions.count)
            XCTAssertTrue(r.coloEvents.isEmpty)
            XCTAssertTrue(r.supersededIds.isEmpty)
            XCTAssertTrue(r.extraRooms.isEmpty)
            XCTAssertEqual(562, try r.details.count)
            XCTAssertFalse(r.anthropicSpeakers.contains("Jiazhou Gao"))
            // HAND-OFF (CONVENTIONS.md, Tests): the Kotlin test also checks Monday's
            // ScheduleIndex(r).dayView("mon", 2026-11-09T08:00-07:00, "Lucy Sweet") for each of
            // these inputs (colo empty; longsTitle "Co-located + off-site"; longsFirst; 11 longs
            // with note "All-Access pass"). ScheduleIndex belongs to the Schedule port, which adds
            // them in Tests/KCNA26CoreTests/Schedule/ColocatedRepositoryTests+Schedule.swift
            // using `Self.loadWith` and `Self.colocatedJsonFailures()`.
        }
    }

    func testAnEventWithoutItsPlaceholderSupersedesNothing() throws {
        let root = coloJson()
        let events = try XCTUnwrap(root["events"]?.arrayValue).map { e -> JSONValue in
            let o = e.objectValue!
            return o["key"]?.stringValue == "colo-argocon" ? .object(o.with("supersedes", .string("nope"))) : e
        }
        let r = try loadWith(JSONValue.object(root.with("events", .array(events))).compactString)
        XCTAssertEqual(10, r.supersededIds.count)
        XCTAssertFalse(r.supersededIds.contains("1289755"))
    }
}
