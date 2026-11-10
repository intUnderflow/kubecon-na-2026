import XCTest
@testable import KCNA26Core

private typealias Block = DescriptionFormat.Block
private typealias Rich = DescriptionFormat.Rich
private typealias Span = DescriptionFormat.Span
private typealias Item = DescriptionFormat.Item

final class DescriptionFormatTests: XCTestCase {

    private func para(_ text: String, _ spans: Span...) -> Block { .paragraph(Rich(text, spans)) }

    func testParagraphsSplitOnBlankLinesAndKeepLineBreaks() {
        XCTAssertEqual(
            [para("One.\nStill one."), para("Two.")],
            DescriptionFormat.parse("One.\nStill one.\n\n  \n\nTwo.\n")
        )
        XCTAssertEqual([para("A"), para("B")], DescriptionFormat.parse("A\r\n\r\nB"))
        XCTAssertEqual([Block](), DescriptionFormat.parse(nil))
        XCTAssertEqual([Block](), DescriptionFormat.parse("  \n "))
    }

    func testSessionizeEscapedBulletsBecomeAList() {
        let blocks = DescriptionFormat.parse(
            "We will discuss:\n\n\\* Architecting workloads\n\\* Building platforms\n\nWhat’s next:\n\\- One\n\\- Two\n\\+ Three"
        )
        let expected: [Block] = [
            para("We will discuss:"),
            .listBlock([
                Item("•", Rich("Architecting workloads"), ordered: false),
                Item("•", Rich("Building platforms"), ordered: false),
            ]),
            para("What’s next:"),
            .listBlock([
                Item("•", Rich("One"), ordered: false),
                Item("•", Rich("Two"), ordered: false),
                Item("•", Rich("Three"), ordered: false),
            ]),
        ]
        XCTAssertEqual(expected, blocks)
    }

    func testNumberedListsKeepTheirNumbersAndPlainBulletsWork() {
        let blocks = DescriptionFormat.parse("Topics:\n1\\. Security\n2\\. Quality\n3) Cost\n\nWho:\n• Developers\n- Platform folks\n  who run clusters")
        let expected: [Block] = [
            para("Topics:"),
            .listBlock([
                Item("1.", Rich("Security"), ordered: true),
                Item("2.", Rich("Quality"), ordered: true),
                Item("3)", Rich("Cost"), ordered: true),
            ]),
            para("Who:"),
            .listBlock([
                Item("•", Rich("Developers"), ordered: false),
                // An indented line continues the item.
                Item("•", Rich("Platform folks who run clusters"), ordered: false),
            ]),
        ]
        XCTAssertEqual(expected, blocks)
    }

    func testNotListsOrHeadings() {
        // Emphasis at line start, years, hashtags.
        XCTAssertEqual(
            [para("Moneyball, then\n2026. A year\n#KubeCrawl tonight", .italic(0, 9))],
            DescriptionFormat.parse("*Moneyball*, then\n2026. A year\n#KubeCrawl tonight")
        )
        XCTAssertEqual([Block.heading(Rich("Agenda"))], DescriptionFormat.parse("### Agenda ###"))
    }

    func testMarkdownLinksShowTheirText() {
        let r = DescriptionFormat.inline("See [the docs](https://example.com/a_b) and [mail](mailto:x@y.z).")
        XCTAssertEqual("See the docs and mail.", r.text)
        XCTAssertEqual(
            [Span.link(4, 12, "https://example.com/a_b"), Span.link(17, 21, "mailto:x@y.z")],
            r.spans
        )
        // Not a link: no URL scheme, or no (…) part.
        XCTAssertEqual(Rich("[x](foo) [y]"), DescriptionFormat.inline("[x](foo) [y]"))
    }

    func testBareUrlsLeaveTrailingPunctuationOutside() {
        let r = DescriptionFormat.inline(
            "The project (https://www.crossplane.io/) is here: https://github.com/kubernetes/community/tree/master/wg-data-protection. Also <https://lima-vm.io/>!"
        )
        XCTAssertEqual(
            "The project (https://www.crossplane.io/) is here: https://github.com/kubernetes/community/tree/master/wg-data-protection. Also https://lima-vm.io/!",
            r.text
        )
        let links = r.spans.compactMap(\.url)
        XCTAssertEqual(
            [
                "https://www.crossplane.io/",
                "https://github.com/kubernetes/community/tree/master/wg-data-protection",
                "https://lima-vm.io/",
            ],
            links
        )
        for l in r.spans where l.isLink {
            XCTAssertEqual(l.url, r.text.kotlinSubstring(l.start, l.end))
        }
        // Balanced parentheses stay in the URL.
        let w = DescriptionFormat.inline("https://en.wikipedia.org/wiki/Foo_(bar).")
        XCTAssertEqual([Span.link(0, 39, "https://en.wikipedia.org/wiki/Foo_(bar)")], w.spans)
    }

    func testBoldItalicAndEscapes() {
        XCTAssertEqual(
            Rich("a cloud-native stack, including Docker, Kubernetes.", [.bold(32, 51)]),
            DescriptionFormat.inline("a cloud-native stack, including **Docker, Kubernetes.**")
        )
        // The Kubernetes Meet & Greet note: \***SHOUT***  →  "*" + bold + "*".
        let shout = DescriptionFormat.inline("\\***PLEASE GRAB YOUR LUNCH FIRST.***")
        XCTAssertEqual("*PLEASE GRAB YOUR LUNCH FIRST.*", shout.text)
        XCTAssertEqual([Span.bold(1, 30)], shout.spans)
        // Sponsor disclaimers are wrapped in _…_; snake_case and lone stars stay literal.
        XCTAssertEqual(Rich("In order to facilitate networking.", [.italic(0, 34)]), DescriptionFormat.inline("_In order to facilitate networking._"))
        XCTAssertEqual(Rich("use my_var_name and 5 * 3"), DescriptionFormat.inline("use my_var_name and 5 * 3"))
        XCTAssertEqual(Rich("20+ calls, 1. ok, a-b"), DescriptionFormat.inline("20\\+ calls, 1\\. ok, a\\-b"))
        // Unclosed delimiters are literal.
        XCTAssertEqual(Rich("**open and *half"), DescriptionFormat.inline("**open and *half"))
    }

    func testNestedEmphasisAndLinkInsideBold() {
        let r = DescriptionFormat.inline("**Read [this](https://a.b/c)** now")
        XCTAssertEqual("Read this now", r.text)
        XCTAssertEqual([Span.bold(0, 9), Span.link(5, 9, "https://a.b/c")], r.spans)
    }

    func testEveryBundledDescriptionFormatsWithValidSpans() throws {
        let texts: [String] = try TestData.repo.details.values.map(\.description) +
            TestData.repo.sessions.compactMap(\.description)
        var lists = 0
        var links = 0
        for t in texts {
            for b in DescriptionFormat.parse(t) {
                let riches: [Rich]
                switch b {
                case .paragraph(let r): riches = [r]
                case .heading(let r): riches = [r]
                case .listBlock(let items):
                    riches = items.map(\.text)
                    lists += 1
                }
                for r in riches {
                    XCTAssertTrue(r.text.isNotBlank)
                    for s in r.spans {
                        XCTAssertTrue(s.start >= 0 && s.start < s.end && s.end <= r.text.kotlinLength, "\(s) in \(r.text)")
                        if s.isLink { links += 1 }
                    }
                }
            }
        }
        // details.json has escaped "\-" / "\*" / "1\." lists and ~20 bare URLs.
        XCTAssertTrue(lists >= 15, "lists=\(lists)")
        XCTAssertTrue(links >= 15, "links=\(links)")
    }

    func testNoRawEscapesSurviveInBundledText() throws {
        let rawEscape = KRegex("\\\\[-*+.]")
        for d in try TestData.repo.details.values {
            for b in DescriptionFormat.parse(d.description) {
                let text: String
                switch b {
                case .paragraph(let r): text = r.text
                case .heading(let r): text = r.text
                case .listBlock(let items): text = items.map(\.text.text).joined(separator: "\n")
                }
                XCTAssertTrue(!rawEscape.containsMatchIn(text), text)
            }
        }
    }

    // MARK: - iOS additions (not in the Kotlin suite)

    /// Spans are UTF-16 offsets (Kotlin indices); `stringRange` maps them for AttributedString.
    func testSpanOffsetsAreUtf16AndMapToStringRanges() {
        let r = DescriptionFormat.inline("🚀 **Ünïcode** at https://a.b/c")
        XCTAssertEqual("🚀 Ünïcode at https://a.b/c", r.text)
        XCTAssertEqual([Span.bold(3, 10), Span.link(14, 27, "https://a.b/c")], r.spans)
        XCTAssertEqual("Ünïcode", r.stringRange(r.spans[0]).map { String(r.text[$0]) })
        XCTAssertEqual("https://a.b/c", r.stringRange(r.spans[1]).map { String(r.text[$0]) })
        XCTAssertNil(r.stringRange(.bold(3, 99)))
    }

    /// `runs` flattens nested spans for SwiftUI (bold around a link, italic inside bold).
    func testRunsFlattenNestedSpans() {
        typealias Run = DescriptionFormat.Run
        let r = DescriptionFormat.inline("**Read [this](https://a.b/c) _now_** please")
        XCTAssertEqual("Read this now please", r.text)
        XCTAssertEqual(
            [
                Run(text: "Read ", bold: true, italic: false, url: nil),
                Run(text: "this", bold: true, italic: false, url: "https://a.b/c"),
                Run(text: " ", bold: true, italic: false, url: nil),
                Run(text: "now", bold: true, italic: true, url: nil),
                Run(text: " please", bold: false, italic: false, url: nil),
            ],
            r.runs
        )
        XCTAssertEqual([Run(text: "plain", bold: false, italic: false, url: nil)], Rich("plain").runs)
        XCTAssertEqual([], Rich("").runs)
        // A link inside a link: the inner URL wins where they overlap.
        let nested = DescriptionFormat.inline("[x <https://a.b>](https://c.d)")
        XCTAssertEqual(
            [
                Run(text: "x ", bold: false, italic: false, url: "https://c.d"),
                Run(text: "https://a.b", bold: false, italic: false, url: "https://a.b"),
            ],
            nested.runs
        )
        // Every bundled description: runs join back to the text.
        for d in (try? TestData.repo.details.values) ?? [] {
            for b in DescriptionFormat.parse(d.description) {
                if case .paragraph(let p) = b { XCTAssertEqual(p.text, p.runs.map(\.text).joined()) }
            }
        }
    }
}
