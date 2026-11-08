package app.kcna26.data

import app.kcna26.TestData
import app.kcna26.ui.session.SessionText
import kotlinx.serialization.Serializable
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.OffsetDateTime

/**
 * The Sunday updates (data/updates/2026-11-08-sunday.json, applied by scripts/apply_updates.py)
 * as the app sees them: through the parsed assets in src/main/assets.
 *
 * Only its sessionUpdates matter: the unconference (voting) feature and unconference.json were
 * removed once the Summit's voting was over, so its topicUpdates are skipped by the script.
 */
class SundayUpdatesTest {
    private val repo = TestData.repo

    private val unconfIds = listOf(
        "m1318474", "m1318479", "m1318476", "m1318475", "m1318482",
        "m1318481", "m1318480", "m1318486", "m1318484", "m1318483",
    )

    /** The file's topicUpdates are ignored (unknown keys). */
    @Serializable
    private data class Updates(val sessionUpdates: List<SessionUpdate>)

    @Serializable
    private data class SessionUpdate(
        val id: String,
        val start: String,
        val end: String? = null,
        val endIsEstimate: Boolean = false,
        val room: String,
        val title: String,
        val speakers: List<String>,
        val description: String? = null,
        val discussionUrl: String? = null,
    )

    /** A file under the repository's data/ folder (tests run with app/ as the working directory). */
    private fun dataFile(name: String): File? =
        listOf(File("../data/$name"), File("data/$name")).firstOrNull { it.isFile }

    private val updates: Updates by lazy {
        val f = dataFile("updates/2026-11-08-sunday.json") ?: error("data/updates/2026-11-08-sunday.json not found")
        Repository.json.decodeFromString(Updates.serializer(), f.readText())
    }

    private fun instant(iso: String) = OffsetDateTime.parse(iso).toInstant()

    @Test
    fun theTenUnconferenceSessionsHaveTheirNewTitlesAndSpeakers() {
        assertEquals(unconfIds.toSet(), updates.sessionUpdates.map { it.id }.toSet())
        for (u in updates.sessionUpdates) {
            val s = repo.session(u.id)!!
            assertEquals(u.id, u.title, s.title)
            assertEquals(u.id, u.speakers, s.speakers)
            assertEquals(u.id, instant(u.start), s.start)
            assertEquals(u.id, u.end?.let(::instant), s.end)
            assertEquals(u.id, u.endIsEstimate, s.endIsEstimate)
            assertEquals(u.id, u.room, s.room)
            assertEquals(u.id, u.description, s.description)
            assertEquals(u.id, u.discussionUrl, s.discussionUrl)
            assertTrue(u.id, s.title.startsWith("Unconference: "))
            assertTrue(u.id, s.speakers.isNotEmpty())
            // Still ordinary Maintainer Summit sessions tagged "Unconference".
            assertEquals("Unconference", s.note)
            assertTrue(s.isMaintainerSummit)
            // Recomputed at runtime as usual: none of them is mine or has an Anthropic speaker.
            assertFalse(isMine(s, repo.defaultMe))
            assertFalse(repo.hasAnthropic(s, repo.defaultMe))
        }
        assertEquals(614, repo.sessions.count { !it.isColocated }) // schedule.json; colocated.json's follow
        assertTrue(repo.sessions.none { it.title.matches(Regex("Unconference Session \\d+")) })
    }

    @Test
    fun firstUnconferenceSessionEndsAt210() {
        val s = repo.session("m1318474")!!
        assertEquals("Unconference: Surviving the CVE vulnpocalypse", s.title)
        assertEquals(listOf("Samuel Karp"), s.speakers)
        assertEquals(instant("2026-11-08T13:35:00-07:00"), s.start)
        assertEquals(instant("2026-11-08T14:10:00-07:00"), s.end)
        assertFalse(s.endIsEstimate)
        assertEquals("1:35–2:10 PM", app.kcna26.time.TimeFormat.range(s))
        assertEquals("35 min", app.kcna26.time.TimeFormat.dur(s))
        // The other nine keep estimated ends ("~45 min").
        assertTrue(unconfIds.drop(1).all { repo.session(it)!!.endIsEstimate })
    }

    @Test
    fun speakersAreSearchableAndPickable() {
        for (name in listOf("Samuel Karp", "Antonio Ojea", "Filip Křepinský", "Diana Todea")) {
            assertTrue(name, name in repo.allSpeakers)
        }
    }

    @Test
    fun assetsMatchTheDataFolder() {
        for (name in listOf(Repository.SCHEDULE, Repository.SUMMIT_DETAILS)) {
            val data = dataFile(name) ?: error("data/$name not found")
            assertEquals(name, data.readText(), TestData.text(name))
        }
    }

    @Test
    fun unconferenceDataIsGone() {
        // The unconference (voting) feature was removed: no unconference.json anywhere...
        assertFalse(File(TestData.assetsDir, "unconference.json").exists())
        assertNull(dataFile("unconference.json"))
        // ...and loading never asks for it.
        val opened = mutableListOf<String>()
        val loaded = Repository.load { name ->
            opened += name
            File(TestData.assetsDir, name).inputStream()
        }
        assertEquals(614, loaded.sessions.count { !it.isColocated })
        assertFalse(opened.toString(), "unconference.json" in opened)
    }

    // ------------------------------------------------------------ parsing the new optional field

    private fun loadWith(schedule: String) =
        Repository.load { name ->
            when (name) {
                Repository.SCHEDULE -> schedule.byteInputStream()
                else -> File(TestData.assetsDir, name).inputStream()
            }
        }

    @Test
    fun discussionUrlIsParsedAndOptional() {
        assertEquals("https://github.com/cncf/maintainer-summit/discussions/117", repo.session("m1318474")!!.discussionUrl)
        assertEquals(10, repo.sessions.count { it.discussionUrl != null })
        assertEquals(unconfIds.toSet(), repo.sessions.filter { it.discussionUrl != null }.map { it.id }.toSet())
        assertTrue(repo.sessions.all { it.discussionUrl?.startsWith("https://github.com/") ?: true })
        assertNull(repo.session("m1318417")!!.discussionUrl) // the reception has none
        assertTrue(repo.sessions.filter { !it.isMaintainerSummit }.all { it.discussionUrl == null })

        // Absent, null or blank: null. Present: kept as is.
        val text = TestData.text(Repository.SCHEDULE)
        val url = "\"discussionUrl\": \"https://github.com/cncf/maintainer-summit/discussions/117\""
        assertTrue(url in text)
        assertNull(loadWith(text.replace(url, "\"discussionUrl\": null")).session("m1318474")!!.discussionUrl)
        assertNull(loadWith(text.replace(url, "\"discussionUrl\": \"\"")).session("m1318474")!!.discussionUrl)
        assertNull(loadWith(text.replace(",\n   $url", "")).session("m1318474")!!.discussionUrl)
        val other = loadWith(text.replace(url, "\"discussionUrl\": \"https://example.com/d/1\""))
        assertEquals("https://example.com/d/1", other.session("m1318474")!!.discussionUrl)
    }

    @Test
    fun detailsLinkWording() {
        assertEquals("Proposal and replies on GitHub ↗", SessionText.DISCUSSION)
        // No "See and vote on the topics" link is left in the data.
        assertTrue(repo.summitDetails.values.none { it.linkText != null || it.link != null })
        assertFalse("See and vote" in TestData.text(Repository.SUMMIT_DETAILS))
    }
}
