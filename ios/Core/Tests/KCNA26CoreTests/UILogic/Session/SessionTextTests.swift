import XCTest
@testable import KCNA26Core

/// Port of ui/session/SessionTextTest.kt.
final class SessionTextTests: XCTestCase {
    private typealias SpeakerRow = SessionText.SpeakerRow
    private let repo = TestData.repo
    private func s(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> Session {
        try XCTUnwrap(repo.session(id), "no session \(id)", file: file, line: line)
    }
    private func at(_ iso: String) -> Date { TestData.clockAt(iso).now() }

    private let eviction = "1289660" // Wed 5:00–5:30 PM, 251 A–C (the spec's example)

    func testMetaRowMatchesTheWeb() throws {
        let x = try s(eviction)
        XCTAssertEqual("Maintainer", SessionText.categoryLabel(repo, x))
        XCTAssertEqual("Wed 5:00–5:30 PM", SessionText.dayAndTime(repo.dayOf(x), x))
        XCTAssertEqual("30 min", SessionText.duration(x))
        XCTAssertNil(SessionText.tag(x))

        // Estimated end: "~"; Maintainer Summit note as a tag.
        let summit = try s("m1290687")
        XCTAssertEqual("~45 min", SessionText.duration(summit))
        XCTAssertEqual("Main Track", SessionText.tag(summit))
        XCTAssertNil(SessionText.whereNote(summit))
        XCTAssertNil(SessionText.tag(try s("m1318410"))) // "Keynote" is not shown as a tag

        // Open-ended reception: "from 5:30 PM", no duration.
        let reception = try s("m1318417")
        XCTAssertEqual("Sun from 5:30 PM", SessionText.dayAndTime(repo.dayOf(reception), reception))
        XCTAssertNil(SessionText.duration(reception))

        // Breaks have no category label.
        XCTAssertEqual("", SessionText.categoryLabel(repo, try s("1289742")))
    }

    func testLiveCountdownLikeTheWebSheet() throws {
        let x = try s(eviction)
        XCTAssertNil(SessionText.liveLabel(x, at("2026-11-11T16:59:59-07:00")))
        XCTAssertEqual("Live · 30 min left", SessionText.liveLabel(x, at("2026-11-11T17:00:00-07:00")))
        XCTAssertEqual("Live · 12 min left", SessionText.liveLabel(x, at("2026-11-11T17:18:40-07:00")))
        XCTAssertEqual("Live · 1 min left", SessionText.liveLabel(x, at("2026-11-11T17:29:59-07:00")))
        XCTAssertNil(SessionText.liveLabel(x, at("2026-11-11T17:30:00-07:00")))
        // Open-ended sessions count as 90 minutes.
        XCTAssertEqual("Live · 30 min left", SessionText.liveLabel(try s("m1318417"), at("2026-11-08T18:30:00-07:00")))
    }

    func testWhereAndFloorLines() throws {
        let r = repo.room("251AC")
        XCTAssertEqual("251 A–C", SessionText.roomName(r, try s(eviction)))
        XCTAssertEqual("Salt Palace L2", SessionText.buildingLabel(r))
        XCTAssertEqual("Level 2", SessionText.levelLabel(r))
        XCTAssertEqual("Salt Palace · 251 A–C", SessionText.buildingAndRoom(r))
        XCTAssertEqual("Level 2 · Salt Palace · 251 A–C", SessionText.locationLine(r))
        XCTAssertNil(SessionText.directionsUnavailable(r, try s(eviction)))

        XCTAssertEqual("Level 3 · Hyatt Regency · Park City", SessionText.locationLine(repo.room("PC")))
        // Hyatt lobby: a position but no building label.
        XCTAssertEqual("Level 1 · Hyatt Regency · Hyatt lobby", SessionText.locationLine(repo.room("HL")))
        XCTAssertNil(SessionText.buildingLabel(repo.room("HL")))
        XCTAssertEqual("Level 1 · Salt Palace · Project Pavilion, Hall 5", SessionText.locationLine(repo.room("PP")))
    }

    func testOffSiteDisablesDirectionsWithTheWebWording() throws {
        let hackathon = try s("1344383")
        let off = repo.room("OFF")
        XCTAssertEqual("Off-site", SessionText.roomName(off, hackathon))
        XCTAssertNil(SessionText.buildingLabel(off))
        XCTAssertNil(SessionText.levelLabel(off))
        XCTAssertNil(SessionText.locationLine(off))
        XCTAssertEqual("Sold out", SessionText.whereNote(hackathon))
        XCTAssertEqual(
            "Off-site event. The official listing has the address and registration details.",
            SessionText.directionsUnavailable(off, hackathon)
        )
        // Unknown room code (no Room at all): no position.
        XCTAssertEqual("No map position for this room.", SessionText.directionsUnavailable(nil, try s(eviction)))
        XCTAssertEqual("XYZ", SessionText.roomName(nil, try s(eviction).copying(room: "XYZ")))
    }

    func testSpeakersShowYouAndAnthropicFromTheCurrentSetting() throws {
        let x = try s(eviction)
        let detail = try XCTUnwrap(try repo.details[eviction]).speakers
        let ant = repo.anthropicSpeakers

        let asLucy = SessionText.speakerRows(detail, x.speakers, "Lucy Sweet", ant)
        XCTAssertEqual(
            [
                SpeakerRow("You", "Member of Technical Staff at Anthropic", isMe: true, isAnthropic: false),
                SpeakerRow("Ryan Hallisey", "Nvidia, Software Engineer", isMe: false, isAnthropic: false),
                SpeakerRow("Filip Křepinský", "Principal Software Engineer, Red Hat", isMe: false, isAnthropic: false),
            ],
            asLucy
        )
        XCTAssertEqual("Speakers", SessionText.speakersHeading(asLucy.count))

        // None: Lucy is an Anthropic colleague like anyone else.
        let asNone = SessionText.speakerRows(detail, x.speakers, nil, ant)
        XCTAssertEqual(SpeakerRow("Lucy Sweet", "Member of Technical Staff at Anthropic", isMe: false, isAnthropic: true), asNone[0])

        // Someone else: "You" moves with the setting.
        let asRyan = SessionText.speakerRows(detail, x.speakers, "Ryan Hallisey", ant)
        XCTAssertEqual(["Lucy Sweet", "You", "Filip Křepinský"], asRyan.map(\.label))
        XCTAssertEqual([true, false, false], asRyan.map(\.isAnthropic))

        // A colleague on someone else's talk.
        let colleague = try XCTUnwrap(repo.sessions.first { ses in ses.speakers.contains { ant.contains($0) && $0 != "Lucy Sweet" } })
        let rows = SessionText.speakerRows(try repo.details[colleague.id]?.speakers ?? [], colleague.speakers, "Lucy Sweet", ant)
        XCTAssertEqual(true, rows.contains { $0.isAnthropic })
    }

    func testSpeakersFallBackToScheduleNamesWhileLoading() throws {
        let x = try s("m1290687")
        XCTAssertEqual(
            [SpeakerRow("Rohit Agrawal", "", isMe: false, isAnthropic: false), SpeakerRow("Kateryna Nezdolii", "", isMe: false, isAnthropic: false)],
            SessionText.speakerRows([], x.speakers, "Lucy Sweet", repo.anthropicSpeakers)
        )
        XCTAssertEqual("Speaker", SessionText.speakersHeading(1))
        XCTAssertEqual([SpeakerRow](), SessionText.speakerRows([], [], "Lucy Sweet", []))
    }

    func testSessionizeNameQuirksStillMatchTheSchedule() throws {
        XCTAssertEqual("Flynn", SessionText.cleanName("Flynn -"))
        XCTAssertEqual("Suhani", SessionText.cleanName("Suhani \u{200E}"))
        XCTAssertEqual("Ann Lee", SessionText.cleanName(" Ann Lee – "))
        XCTAssertEqual("Smit Jain", SessionText.matchScheduleName("Smit Jain (he/him)", ["Smit Jain"]))
        XCTAssertEqual("Piotr Prokop", SessionText.matchScheduleName("Piotr Prokop PL", ["Piotr Prokop", "Sreeja Varnam"]))
        XCTAssertNil(SessionText.matchScheduleName("Ann", ["Ann Lee"]))

        let suhani = SessionText.speakerRows([SpeakerTagline("Suhani \u{200E}", "Contributor @Kyverno")], ["Suhani"], "Suhani", [])
        XCTAssertEqual([SpeakerRow("You", "Contributor @Kyverno", isMe: true, isAnthropic: false)], suhani)
        let smit = SessionText.speakerRows([SpeakerTagline("Smit Jain (he/him)", "")], ["Smit Jain"], "Smit Jain", [])
        XCTAssertEqual("You", try smit.singleMatch { _ in true }.label)
        // Display keeps the Sessionize spelling otherwise.
        XCTAssertEqual(
            "Smit Jain (he/him)",
            try SessionText.speakerRows([SpeakerTagline("Smit Jain (he/him)", "")], ["Smit Jain"], nil, []).singleMatch { _ in true }.label
        )
    }

    func testCoLocatedSessions() throws {
        let talk = try s("1311945") // ArgoCon sponsored keynote
        XCTAssertEqual("ArgoCon", SessionText.coloEyebrow(repo, talk))
        let tags = SessionText.coloTags(talk)
        XCTAssertEqual(["Keynote", "Any level", "Sponsored"].filter { tags.contains($0) }, tags)
        XCTAssertTrue(tags.contains(SessionText.SPONSORED))
        XCTAssertEqual("Keynote", tags.first)
        XCTAssertEqual("Event", SessionText.categoryLabel(repo, talk)) // replaced by the eyebrow in the meta row
        XCTAssertNil(SessionText.whereNote(talk))
        XCTAssertNil(SessionText.tag(talk))
        XCTAssertEqual(talk.officialUrl, SessionText.officialUrl(repo, talk))
        XCTAssertTrue(talk.officialUrl.hasSuffix("?id=1311945"))
        // A break several events share, and one event's own break.
        let lunch = try s("1309415")
        XCTAssertEqual(SessionText.COLOCATED_EVENTS, SessionText.coloEyebrow(repo, lunch))
        XCTAssertEqual("For Agentics Day: MCP + Agents, ArgoCon, BackstageCon and Open Source SecurityCon", SessionText.servesLine(repo, lunch))
        XCTAssertEqual([String](), SessionText.coloTags(lunch))
        let ciliumLunch = try s("1309414")
        XCTAssertEqual("CiliumCon", SessionText.coloEyebrow(repo, ciliumLunch))
        XCTAssertNil(SessionText.servesLine(repo, ciliumLunch))
        // Their places have no position: say where they are instead of the bare sentence.
        XCTAssertEqual(
            "Lower Concourse foyer and Hall 4, reached via the Lower Mezzanine. No map position for this room.",
            SessionText.directionsUnavailable(repo.roomOf(lunch), lunch)
        )
        XCTAssertNil(SessionText.levelLabel(repo.roomOf(lunch)))
        // Talks are in real rooms: Directions work, "Getting there" shows.
        XCTAssertNil(SessionText.directionsUnavailable(repo.roomOf(talk), talk))
        XCTAssertEqual("Level 1 · Salt Palace · Room 151", SessionText.locationLine(repo.roomOf(talk)))
        // The reception and everything from schedule.json have no eyebrow or tags.
        XCTAssertNil(SessionText.coloEyebrow(repo, try s("1309453")))
        XCTAssertNil(SessionText.coloEyebrow(repo, try s("1289660")))
        XCTAssertEqual([String](), SessionText.coloTags(try s("1289660")))
        // No official link of its own: the event's page.
        let bare = talk.copying(officialUrl: "")
        XCTAssertEqual(try XCTUnwrap(repo.coloEvent("colo-argocon")).pageUrl, SessionText.officialUrl(repo, bare))
        XCTAssertNil(SessionText.officialUrl(repo, try s("1289660").copying(officialUrl: "")))
    }
}

private extension Session {
    /// Kotlin `copy(room = …)` / `copy(officialUrl = …)`.
    func copying(room: String? = nil, officialUrl: String? = nil) -> Session {
        Session(
            id: id, event: event, day: day, start: start, end: end, endIsEstimate: endIsEstimate, room: room ?? self.room,
            title: title, speakers: speakers, note: note, category: category, group: group,
            precomputedIsMine: precomputedIsMine, precomputedHasAnthropic: precomputedHasAnthropic,
            officialUrl: officialUrl ?? self.officialUrl, description: description, slidesUrl: slidesUrl,
            discussionUrl: discussionUrl, coloEvent: coloEvent, coloEvents: coloEvents, format: format, level: level,
            sponsored: sponsored, topic: topic
        )
    }
}
