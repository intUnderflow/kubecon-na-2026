package app.kcna26.details

import app.kcna26.TestData
import app.kcna26.details.DescriptionFormat.Block
import app.kcna26.details.DescriptionFormat.Rich
import app.kcna26.details.DescriptionFormat.Span
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DescriptionFormatTest {

    private fun para(text: String, vararg spans: Span) = Block.Paragraph(Rich(text, spans.toList()))

    @Test
    fun paragraphsSplitOnBlankLinesAndKeepLineBreaks() {
        assertEquals(
            listOf(para("One.\nStill one."), para("Two.")),
            DescriptionFormat.parse("One.\nStill one.\n\n  \n\nTwo.\n"),
        )
        assertEquals(listOf(para("A"), para("B")), DescriptionFormat.parse("A\r\n\r\nB"))
        assertEquals(emptyList<Block>(), DescriptionFormat.parse(null))
        assertEquals(emptyList<Block>(), DescriptionFormat.parse("  \n "))
    }

    @Test
    fun sessionizeEscapedBulletsBecomeAList() {
        val blocks = DescriptionFormat.parse(
            "We will discuss:\n\n\\* Architecting workloads\n\\* Building platforms\n\nWhat’s next:\n\\- One\n\\- Two\n\\+ Three",
        )
        assertEquals(
            listOf(
                para("We will discuss:"),
                Block.ListBlock(
                    listOf(
                        DescriptionFormat.Item("•", Rich("Architecting workloads"), ordered = false),
                        DescriptionFormat.Item("•", Rich("Building platforms"), ordered = false),
                    ),
                ),
                para("What’s next:"),
                Block.ListBlock(
                    listOf(
                        DescriptionFormat.Item("•", Rich("One"), false),
                        DescriptionFormat.Item("•", Rich("Two"), false),
                        DescriptionFormat.Item("•", Rich("Three"), false),
                    ),
                ),
            ),
            blocks,
        )
    }

    @Test
    fun numberedListsKeepTheirNumbersAndPlainBulletsWork() {
        val blocks = DescriptionFormat.parse("Topics:\n1\\. Security\n2\\. Quality\n3) Cost\n\nWho:\n• Developers\n- Platform folks\n  who run clusters")
        assertEquals(
            listOf(
                para("Topics:"),
                Block.ListBlock(
                    listOf(
                        DescriptionFormat.Item("1.", Rich("Security"), true),
                        DescriptionFormat.Item("2.", Rich("Quality"), true),
                        DescriptionFormat.Item("3)", Rich("Cost"), true),
                    ),
                ),
                para("Who:"),
                Block.ListBlock(
                    listOf(
                        DescriptionFormat.Item("•", Rich("Developers"), false),
                        // An indented line continues the item.
                        DescriptionFormat.Item("•", Rich("Platform folks who run clusters"), false),
                    ),
                ),
            ),
            blocks,
        )
    }

    @Test
    fun notListsOrHeadings() {
        // Emphasis at line start, years, hashtags.
        assertEquals(
            listOf(
                para("Moneyball, then\n2026. A year\n#KubeCrawl tonight", Span.Italic(0, 9)),
            ),
            DescriptionFormat.parse("*Moneyball*, then\n2026. A year\n#KubeCrawl tonight"),
        )
        assertEquals(listOf(Block.Heading(Rich("Agenda"))), DescriptionFormat.parse("### Agenda ###"))
    }

    @Test
    fun markdownLinksShowTheirText() {
        val r = DescriptionFormat.inline("See [the docs](https://example.com/a_b) and [mail](mailto:x@y.z).")
        assertEquals("See the docs and mail.", r.text)
        assertEquals(
            listOf(Span.Link(4, 12, "https://example.com/a_b"), Span.Link(17, 21, "mailto:x@y.z")),
            r.spans,
        )
        // Not a link: no URL scheme, or no (…) part.
        assertEquals(Rich("[x](foo) [y]"), DescriptionFormat.inline("[x](foo) [y]"))
    }

    @Test
    fun bareUrlsLeaveTrailingPunctuationOutside() {
        val r = DescriptionFormat.inline(
            "The project (https://www.crossplane.io/) is here: https://github.com/kubernetes/community/tree/master/wg-data-protection. Also <https://lima-vm.io/>!",
        )
        assertEquals(
            "The project (https://www.crossplane.io/) is here: https://github.com/kubernetes/community/tree/master/wg-data-protection. Also https://lima-vm.io/!",
            r.text,
        )
        val links = r.spans.filterIsInstance<Span.Link>().map { it.url }
        assertEquals(
            listOf(
                "https://www.crossplane.io/",
                "https://github.com/kubernetes/community/tree/master/wg-data-protection",
                "https://lima-vm.io/",
            ),
            links,
        )
        for (l in r.spans.filterIsInstance<Span.Link>()) assertEquals(l.url, r.text.substring(l.start, l.end))
        // Balanced parentheses stay in the URL.
        val w = DescriptionFormat.inline("https://en.wikipedia.org/wiki/Foo_(bar).")
        assertEquals(listOf(Span.Link(0, 39, "https://en.wikipedia.org/wiki/Foo_(bar)")), w.spans)
    }

    @Test
    fun boldItalicAndEscapes() {
        assertEquals(
            Rich("a cloud-native stack, including Docker, Kubernetes.", listOf(Span.Bold(32, 51))),
            DescriptionFormat.inline("a cloud-native stack, including **Docker, Kubernetes.**"),
        )
        // The Kubernetes Meet & Greet note: \***SHOUT***  →  "*" + bold + "*".
        val shout = DescriptionFormat.inline("\\***PLEASE GRAB YOUR LUNCH FIRST.***")
        assertEquals("*PLEASE GRAB YOUR LUNCH FIRST.*", shout.text)
        assertEquals(listOf(Span.Bold(1, 30)), shout.spans)
        // Sponsor disclaimers are wrapped in _…_; snake_case and lone stars stay literal.
        assertEquals(Rich("In order to facilitate networking.", listOf(Span.Italic(0, 34))), DescriptionFormat.inline("_In order to facilitate networking._"))
        assertEquals(Rich("use my_var_name and 5 * 3"), DescriptionFormat.inline("use my_var_name and 5 * 3"))
        assertEquals(Rich("20+ calls, 1. ok, a-b"), DescriptionFormat.inline("20\\+ calls, 1\\. ok, a\\-b"))
        // Unclosed delimiters are literal.
        assertEquals(Rich("**open and *half"), DescriptionFormat.inline("**open and *half"))
    }

    @Test
    fun nestedEmphasisAndLinkInsideBold() {
        val r = DescriptionFormat.inline("**Read [this](https://a.b/c)** now")
        assertEquals("Read this now", r.text)
        assertEquals(listOf(Span.Bold(0, 9), Span.Link(5, 9, "https://a.b/c")), r.spans)
    }

    @Test
    fun everyBundledDescriptionFormatsWithValidSpans() {
        val texts = TestData.repo.details.values.map { it.description } +
            TestData.repo.sessions.mapNotNull { it.description }
        var lists = 0
        var links = 0
        for (t in texts) {
            for (b in DescriptionFormat.parse(t)) {
                val riches = when (b) {
                    is Block.Paragraph -> listOf(b.text)
                    is Block.Heading -> listOf(b.text)
                    is Block.ListBlock -> b.items.map { it.text }.also { lists++ }
                }
                for (r in riches) {
                    assertTrue(r.text.isNotBlank())
                    for (s in r.spans) {
                        assertTrue("$s in ${r.text}", s.start in 0 until s.end && s.end <= r.text.length)
                        if (s is Span.Link) links++
                    }
                }
            }
        }
        // details.json has escaped "\-" / "\*" / "1\." lists and ~20 bare URLs.
        assertTrue("lists=$lists", lists >= 15)
        assertTrue("links=$links", links >= 15)
    }

    @Test
    fun noRawEscapesSurviveInBundledText() {
        for (d in TestData.repo.details.values) {
            for (b in DescriptionFormat.parse(d.description)) {
                val text = when (b) {
                    is Block.Paragraph -> b.text.text
                    is Block.Heading -> b.text.text
                    is Block.ListBlock -> b.items.joinToString("\n") { it.text.text }
                }
                assertTrue(text, !Regex("\\\\[-*+.]").containsMatchIn(text))
            }
        }
    }
}
