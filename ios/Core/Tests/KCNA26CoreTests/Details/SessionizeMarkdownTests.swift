import XCTest
@testable import KCNA26Core

/// `SessionizeMarkdown.parse` must match scripts/fetch_details.py parse() exactly. Every expected
/// value here was produced by running the Python function on the same input.
final class SessionizeMarkdownTests: XCTestCase {

    private func sp(_ name: String, _ tagline: String = "") -> SpeakerTagline { SpeakerTagline(name, tagline) }

    func testRealResponsesParseToTheirBundledEntries() throws {
        let details = try TestData.repo.details
        for (id, md) in SessionizeSamples.byId {
            XCTAssertEqual(details[id], SessionizeMarkdown.parse(md), "session \(id)")
        }
    }

    func testRealResponseKeepsOddSpeakerNamesLikeThePythonScript() {
        XCTAssertEqual([sp("Flynn -", "Technical Evangelist, Buoyant")], SessionizeMarkdown.parse(SessionizeSamples.byId["1289637"]!).speakers)
        XCTAssertEqual([sp("Suhani \u{200E}", "Contributor @Kyverno")], SessionizeMarkdown.parse(SessionizeSamples.byId["1289901"]!).speakers)
    }

    func testLinkedSpeakersWithEmEnDashAndHyphen() {
        let md = "# T\n\n- **Session ID:** 1\n\n## Description\n\nPara one.\n\nPara two\nline two.\n\n## Speakers\n\n" +
            "- [Jane Doe](https://x/speaker/1) — Staff Engineer, ACME\n" +
            "- [Bob Ray](https://x/speaker/2) – Maintainer – Project X\n" +
            "- [Al Hyphen](https://x/s/3) - SRE at Foo\n" +
            "- [No Tag](https://x/s/4)\n"
        XCTAssertEqual(
            SessionDetail(
                description: "Para one.\n\nPara two\nline two.",
                speakers: [
                    sp("Jane Doe", "Staff Engineer, ACME"),
                    sp("Bob Ray", "Maintainer – Project X"),
                    sp("Al Hyphen", "SRE at Foo"),
                    sp("No Tag"),
                ]
            ),
            SessionizeMarkdown.parse(md)
        )
    }

    func testPlainAndBoldSpeakersUnderSingularHeadingAndH3() {
        let md = "## Description\nHello\n### Speaker\n" +
            "* **Ann Bold** — CTO, Startup\n" +
            "* Plain Name – Dev\n" +
            "* Name - With Hyphen\n" +
            "* **Only Bold**\n" +
            "not a bullet\n" +
            "  -   Indented Person — Lead\n"
        XCTAssertEqual(
            SessionDetail(
                description: "Hello",
                speakers: [
                    sp("Ann Bold", "CTO, Startup"),
                    sp("Plain Name", "Dev"),
                    // Unlinked names only split on em/en dashes, so a hyphen stays in the name.
                    sp("Name - With Hyphen"),
                    sp("Only Bold"),
                    sp("Indented Person", "Lead"),
                ]
            ),
            SessionizeMarkdown.parse(md)
        )
    }

    func testCrlfAndExtraSpaces() {
        let md = "## Description\r\n\r\nLine A\r\nLine B\r\n\r\n## Speakers\r\n- [\u{DC} Name](u) —  Tag with spaces  \r\n"
        XCTAssertEqual(SessionDetail(description: "Line A\nLine B", speakers: [sp("\u{DC} Name", "Tag with spaces")]), SessionizeMarkdown.parse(md))
    }

    func testUnicodeWhitespaceCountsAsPythonWhitespace() {
        let md = "##\u{A0}Description\u{A0}\nText\u{A0}\n## Speakers\n-\u{A0}[A B](u)\u{A0}—\u{A0}Tag\n"
        XCTAssertEqual(SessionDetail(description: "Text", speakers: [sp("A B", "Tag")]), SessionizeMarkdown.parse(md))
    }

    func testRepeatedHeadingsResetAndAnEmptySpeakersSectionWins() {
        let md = "## Description\nfirst\n## Description\nsecond\n## Speakers\n## Speaker\n- [X](u) — y\n"
        XCTAssertEqual(SessionDetail(description: "second", speakers: []), SessionizeMarkdown.parse(md))
    }

    func testEmptyAndHeadinglessInputs() {
        let none = SessionDetail(description: "", speakers: [])
        XCTAssertEqual(none, SessionizeMarkdown.parse(""))
        XCTAssertEqual(none, SessionizeMarkdown.parse("# Closing Remarks\n\n- **When:** x\n"))
        // Only ## and ### start sections.
        XCTAssertEqual(none, SessionizeMarkdown.parse("# Description\nnope\n#### Description\nalso nope\n"))
    }

    func testOddSpeakerLinesFallBackLikePython() {
        let md = "## Speakers\n" +
            "- [Name [with] bracket](u) — t\n" +
            "- Weird*Star — t\n" +
            "- **Bold Tag** — **Bold tagline**\n" +
            "- [Flynn -](u)\n"
        XCTAssertEqual(
            [
                sp("[Name [with] bracket](u)", "t"),
                sp("Weird*Star — t"),
                sp("Bold Tag", "**Bold tagline**"),
                sp("Flynn -"),
            ],
            SessionizeMarkdown.parse(md).speakers
        )
    }

    func testPyStripMatchesPythonStrip() {
        XCTAssertEqual("a b", SessionizeMarkdown.pyStrip("\u{3000}\u{A0} a b\u{2009}\u{0085}\t"))
        // U+200E (LRM) is not whitespace in Python.
        XCTAssertEqual("x \u{200E}", SessionizeMarkdown.pyStrip(" x \u{200E} "))
    }
}
