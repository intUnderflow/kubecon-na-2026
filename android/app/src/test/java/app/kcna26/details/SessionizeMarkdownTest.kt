package app.kcna26.details

import app.kcna26.TestData
import app.kcna26.data.SessionDetail
import app.kcna26.data.SpeakerTagline
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [SessionizeMarkdown.parse] must match scripts/fetch_details.py parse() exactly. Every expected
 * value here was produced by running the Python function on the same input.
 */
class SessionizeMarkdownTest {

    private fun sp(name: String, tagline: String = "") = SpeakerTagline(name, tagline)

    @Test
    fun realResponsesParseToTheirBundledEntries() {
        for ((id, md) in SessionizeSamples.byId) {
            assertEquals("session $id", TestData.repo.details.getValue(id), SessionizeMarkdown.parse(md))
        }
    }

    @Test
    fun realResponseKeepsOddSpeakerNamesLikeThePythonScript() {
        assertEquals(listOf(sp("Flynn -", "Technical Evangelist, Buoyant")), SessionizeMarkdown.parse(SessionizeSamples.byId.getValue("1289637")).speakers)
        assertEquals(listOf(sp("Suhani ‎", "Contributor @Kyverno")), SessionizeMarkdown.parse(SessionizeSamples.byId.getValue("1289901")).speakers)
    }

    @Test
    fun linkedSpeakersWithEmEnDashAndHyphen() {
        val md = "# T\n\n- **Session ID:** 1\n\n## Description\n\nPara one.\n\nPara two\nline two.\n\n## Speakers\n\n" +
            "- [Jane Doe](https://x/speaker/1) — Staff Engineer, ACME\n" +
            "- [Bob Ray](https://x/speaker/2) – Maintainer – Project X\n" +
            "- [Al Hyphen](https://x/s/3) - SRE at Foo\n" +
            "- [No Tag](https://x/s/4)\n"
        assertEquals(
            SessionDetail(
                "Para one.\n\nPara two\nline two.",
                listOf(
                    sp("Jane Doe", "Staff Engineer, ACME"),
                    sp("Bob Ray", "Maintainer – Project X"),
                    sp("Al Hyphen", "SRE at Foo"),
                    sp("No Tag"),
                ),
            ),
            SessionizeMarkdown.parse(md),
        )
    }

    @Test
    fun plainAndBoldSpeakersUnderSingularHeadingAndH3() {
        val md = "## Description\nHello\n### Speaker\n" +
            "* **Ann Bold** — CTO, Startup\n" +
            "* Plain Name – Dev\n" +
            "* Name - With Hyphen\n" +
            "* **Only Bold**\n" +
            "not a bullet\n" +
            "  -   Indented Person — Lead\n"
        assertEquals(
            SessionDetail(
                "Hello",
                listOf(
                    sp("Ann Bold", "CTO, Startup"),
                    sp("Plain Name", "Dev"),
                    // Unlinked names only split on em/en dashes, so a hyphen stays in the name.
                    sp("Name - With Hyphen"),
                    sp("Only Bold"),
                    sp("Indented Person", "Lead"),
                ),
            ),
            SessionizeMarkdown.parse(md),
        )
    }

    @Test
    fun crlfAndExtraSpaces() {
        val md = "## Description\r\n\r\nLine A\r\nLine B\r\n\r\n## Speakers\r\n- [Ü Name](u) —  Tag with spaces  \r\n"
        assertEquals(SessionDetail("Line A\nLine B", listOf(sp("Ü Name", "Tag with spaces"))), SessionizeMarkdown.parse(md))
    }

    @Test
    fun unicodeWhitespaceCountsAsPythonWhitespace() {
        val md = "## Description \nText \n## Speakers\n- [A B](u) — Tag\n"
        assertEquals(SessionDetail("Text", listOf(sp("A B", "Tag"))), SessionizeMarkdown.parse(md))
    }

    @Test
    fun repeatedHeadingsResetAndAnEmptySpeakersSectionWins() {
        val md = "## Description\nfirst\n## Description\nsecond\n## Speakers\n## Speaker\n- [X](u) — y\n"
        assertEquals(SessionDetail("second", emptyList()), SessionizeMarkdown.parse(md))
    }

    @Test
    fun emptyAndHeadinglessInputs() {
        val none = SessionDetail("", emptyList())
        assertEquals(none, SessionizeMarkdown.parse(""))
        assertEquals(none, SessionizeMarkdown.parse("# Closing Remarks\n\n- **When:** x\n"))
        // Only ## and ### start sections.
        assertEquals(none, SessionizeMarkdown.parse("# Description\nnope\n#### Description\nalso nope\n"))
    }

    @Test
    fun oddSpeakerLinesFallBackLikePython() {
        val md = "## Speakers\n" +
            "- [Name [with] bracket](u) — t\n" +
            "- Weird*Star — t\n" +
            "- **Bold Tag** — **Bold tagline**\n" +
            "- [Flynn -](u)\n"
        assertEquals(
            listOf(
                sp("[Name [with] bracket](u)", "t"),
                sp("Weird*Star — t"),
                sp("Bold Tag", "**Bold tagline**"),
                sp("Flynn -"),
            ),
            SessionizeMarkdown.parse(md).speakers,
        )
    }

    @Test
    fun pyStripMatchesPythonStrip() {
        assertEquals("a b", SessionizeMarkdown.pyStrip("　  a b \u0085\t"))
        // U+200E (LRM) is not whitespace in Python.
        assertEquals("x ‎", SessionizeMarkdown.pyStrip(" x ‎ "))
    }
}
