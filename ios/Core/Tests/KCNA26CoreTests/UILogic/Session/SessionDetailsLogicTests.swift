import XCTest
@testable import KCNA26Core

/// Tests of the helpers extracted from ui/session/SessionSheet.kt, SessionDetailsParts.kt and
/// DetailsScrollCarry.kt (no Kotlin test of their own), against the Kotlin expressions they replace.
final class SessionDetailsLogicTests: XCTestCase {
    private let repo = TestData.repo
    private func s(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> Session {
        try XCTUnwrap(repo.session(id), "no session \(id)", file: file, line: line)
    }
    private let eviction = "1289660" // Wed 5:00–5:30 PM, 251 A–C

    private func info(_ description: String? = nil, slides: String? = nil, link: String? = nil, linkText: String? = nil) -> DetailInfo {
        DetailInfo(description: description, speakers: [], slidesUrl: slides, link: link, linkText: linkText, source: .bundled)
    }

    func testLoadsOnlyWhatThePeekDidNotHave() {
        XCTAssertTrue(SessionDetailsLogic.needsLoad(nil))
        XCTAssertTrue(SessionDetailsLogic.needsLoad(.unavailable))
        XCTAssertFalse(SessionDetailsLogic.needsLoad(.nothing))
        XCTAssertFalse(SessionDetailsLogic.needsLoad(.found(info("x"))))
        XCTAssertEqual(250, SessionDetailsLogic.LOADING_DELAY_MS)
        XCTAssertEqual(24, SessionDetailsLogic.horizontalPadding(wide: true))
        XCTAssertEqual(18, SessionDetailsLogic.horizontalPadding(wide: false))
        XCTAssertEqual(44, SessionDetailsLogic.metaTrailingReserve(closeButton: true))
        XCTAssertEqual(0, SessionDetailsLogic.metaTrailingReserve(closeButton: false))
    }

    func testMetaRowUsesTheEventNameAsEyebrow() throws {
        let x = try s(eviction)
        XCTAssertEqual(
            SessionDetailsLogic.Meta(label: "Maintainer", labelCategory: x.category, dayAndTime: "Wed 5:00–5:30 PM", duration: "30 min", tag: nil),
            SessionDetailsLogic.meta(repo, x)
        )
        let talk = try s("1311945") // ArgoCon sponsored keynote
        let m = SessionDetailsLogic.meta(repo, talk)
        XCTAssertEqual("ArgoCon", m.label)
        XCTAssertEqual("colo", m.labelCategory)
        XCTAssertEqual(SessionText.dayAndTime(repo.dayOf(talk), talk), m.dayAndTime)
        XCTAssertEqual("Main Track", SessionDetailsLogic.meta(repo, try s("m1290687")).tag)
        // A break: no eyebrow.
        XCTAssertEqual("", SessionDetailsLogic.meta(repo, try s("1289742")).label)
    }

    func testColoInfoAndTags() throws {
        XCTAssertNil(SessionDetailsLogic.coloInfo(repo, try s(eviction)))
        let lunch = try s("1309415")
        let info = try XCTUnwrap(SessionDetailsLogic.coloInfo(repo, lunch))
        XCTAssertEqual(SessionText.servesLine(repo, lunch), info.serves)
        XCTAssertEqual([], info.tags)
        let talk = try s("1311945")
        let t = try XCTUnwrap(SessionDetailsLogic.coloInfo(repo, talk))
        XCTAssertNil(t.serves)
        XCTAssertEqual(SessionText.coloTags(talk), t.tags)
        XCTAssertEqual(talk.topic, t.topic)
        XCTAssertEqual(.note, SessionDetailsLogic.coloTagColor(SessionText.SPONSORED))
        XCTAssertEqual(.muted, SessionDetailsLogic.coloTagColor("Keynote"))
    }

    func testPillsAndSpeakerColours() throws {
        let x = try s(eviction)
        let live = TestData.instant("2026-11-11T17:18:40-07:00")
        XCTAssertEqual(
            [
                SessionDetailsLogic.Pill(text: "You’re speaking", background: .you, content: .onYou),
                SessionDetailsLogic.Pill(text: "Anthropic", background: .anthropic, content: .onAnthropic),
                SessionDetailsLogic.Pill(text: "Live · 12 min left", background: .you, content: .onYou),
            ],
            SessionDetailsLogic.pills(x, mine: true, anthropic: true, now: live)
        )
        XCTAssertEqual([], SessionDetailsLogic.pills(x, mine: false, anthropic: false, now: TestData.instant("2026-11-11T09:00:00-07:00")))
        XCTAssertEqual(.you, SessionDetailsLogic.speakerColor(SessionText.SpeakerRow("You", "", isMe: true, isAnthropic: false)))
        XCTAssertEqual(.anthropic, SessionDetailsLogic.speakerColor(SessionText.SpeakerRow("Lucy Sweet", "", isMe: false, isAnthropic: true)))
        XCTAssertEqual(.ink, SessionDetailsLogic.speakerColor(SessionText.SpeakerRow("Ryan Hallisey", "", isMe: false, isAnthropic: false)))
    }

    func testGettingThereAndTheDirectionsBar() throws {
        let r = repo.room("251AC")
        let g = try XCTUnwrap(SessionDetailsLogic.gettingThere(r))
        XCTAssertEqual("Level 2", g.level)
        XCTAssertEqual("Salt Palace · 251 A–C", g.place)
        XCTAssertEqual("Level 2 · Salt Palace · 251 A–C", g.accessibilityLabel)
        XCTAssertNil(SessionDetailsLogic.gettingThere(repo.room("OFF")))
        XCTAssertNil(SessionDetailsLogic.gettingThere(nil))
        let ok = SessionDetailsLogic.directionsBar(r, try s(eviction))
        XCTAssertNil(ok.reason)
        XCTAssertTrue(ok.enabled)
        let off = SessionDetailsLogic.directionsBar(repo.room("OFF"), try s("1344383"))
        XCTAssertEqual(SessionText.OFF_SITE, off.reason)
        XCTAssertFalse(off.enabled)
    }

    func testAboutStates() {
        XCTAssertEqual(.hidden, SessionDetailsLogic.about(nil, showLoading: false))
        XCTAssertEqual(.loading, SessionDetailsLogic.about(nil, showLoading: true))
        XCTAssertEqual(.unavailable, SessionDetailsLogic.about(.unavailable, showLoading: true))
        XCTAssertEqual(.hidden, SessionDetailsLogic.about(.nothing, showLoading: true))
        XCTAssertEqual(.hidden, SessionDetailsLogic.about(.found(info(nil)), showLoading: false))
        XCTAssertEqual(.hidden, SessionDetailsLogic.about(.found(info("")), showLoading: false))
        let text = "Intro **bold**.\n\n1. one\n2. two"
        let blocks = DescriptionFormat.parse(text)
        XCTAssertFalse(blocks.isEmpty)
        XCTAssertEqual(.description(blocks), SessionDetailsLogic.about(.found(info(text)), showLoading: false))
        var items: [DescriptionFormat.Item] = []
        for b in blocks { if case .listBlock(let xs) = b { items = xs } }
        XCTAssertEqual(28, SessionDetailsLogic.markerWidth(items))
        let bullets = DescriptionFormat.parse("- a\n- b").compactMap { b -> [DescriptionFormat.Item]? in
            if case .listBlock(let xs) = b { return xs }
            return nil
        }.first ?? []
        XCTAssertFalse(bullets.isEmpty)
        XCTAssertEqual(18, SessionDetailsLogic.markerWidth(bullets))
    }

    func testLinksInTheWebOrder() throws {
        let x = try s(eviction)
        let official = SessionText.officialUrl(repo, x)
        XCTAssertEqual(
            [SessionDetailsLogic.Link(text: "Official listing ↗", url: try XCTUnwrap(official), primary: false)],
            SessionDetailsLogic.links(x, official, nil)
        )
        XCTAssertEqual(
            [
                SessionDetailsLogic.Link(text: "Slides ↗", url: "https://s", primary: true),
                SessionDetailsLogic.Link(text: "https://l ↗", url: "https://l", primary: true),
            ],
            SessionDetailsLogic.links(x, nil, info(slides: "https://s", link: "https://l"))
        )
        XCTAssertEqual("Read more ↗", SessionDetailsLogic.links(x, nil, info(link: "https://l", linkText: "Read more")).first?.text)
        // The schedule's own slides and an unconference discussion.
        let summit = try s("m1290687")
        XCTAssertEqual([SessionText.SLIDES], SessionDetailsLogic.links(summit, nil, nil).map(\.text))
        XCTAssertEqual(summit.slidesUrl, SessionDetailsLogic.links(summit, nil, nil).first?.url)
        let unconf = try s("m1318474")
        XCTAssertEqual(
            [SessionText.DISCUSSION, SessionText.OFFICIAL],
            SessionDetailsLogic.links(unconf, SessionText.officialUrl(repo, unconf), nil).map(\.text)
        )
    }
}

/// DetailsScrollCarry (ui/session/DetailsScrollCarry.kt's ViewModel; main actor).
@MainActor
final class DetailsScrollCarryTests: XCTestCase {
    func testTheScrollCarryHandsThePositionOverOnce() {
        let carry = DetailsScrollCarry()
        XCTAssertEqual(0, carry.take("a"))
        carry.put("a", 120)
        XCTAssertEqual(120, carry.take("a"))
        XCTAssertEqual(0, carry.take("a")) // once
        carry.put("a", 50)
        XCTAssertEqual(0, carry.take("b")) // another session: nothing, and the carry is spent
        XCTAssertEqual(0, carry.take("a"))
    }
}
