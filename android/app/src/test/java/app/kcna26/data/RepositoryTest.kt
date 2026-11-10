package app.kcna26.data

import app.kcna26.TestData
import app.kcna26.theme.CategoryDark
import app.kcna26.theme.CategoryLight
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class RepositoryTest {
    private val repo = TestData.repo

    @Test
    fun loadsAllSessions() {
        // schedule.json's 615, then colocated.json's 223 (see ColocatedRepositoryTest).
        assertEquals(838, repo.sessions.size)
        assertEquals(838, repo.sessionsById.size)
        assertEquals(615, repo.sessions.count { !it.isColocated })
        assertTrue(repo.sessions.take(615).none { it.isColocated })
    }

    @Test
    fun loadsDaysCategoriesAndSpeakers() {
        assertEquals(listOf("sun", "mon", "tue", "wed", "thu"), repo.days.map { it.key })
        assertEquals(LocalDate.of(2026, 11, 8), repo.days[0].date)
        assertEquals("Sun", repo.days[0].dow)
        assertEquals(8, repo.days[0].num)
        assertEquals(9, repo.categories.size)
        assertEquals("Lucy Sweet", repo.defaultMe)
        assertTrue("Lucy Sweet" in repo.anthropicSpeakers)
        assertTrue("Lucy Sweet" in repo.allSpeakers)
    }

    @Test
    fun sessionFields() {
        val open = repo.sessions.single { it.end == null }
        assertEquals("m1318417", open.id)
        assertEquals(open.start.plusSeconds(90 * 60), open.effectiveEnd)
        assertTrue(open.isMaintainerSummit)
        val grouped = repo.session("1289955")!!
        assertEquals(SessionGroup("mon-plt", "Project Lightning Talks"), grouped.group)
        assertEquals("RBD", grouped.room)
        assertTrue(repo.sessions.any { it.slidesUrl != null })
        assertTrue(repo.sessions.count { it.description != null } > 0)
    }

    @Test
    fun roomsIncludingOffSite() {
        assertEquals(40, repo.rooms.size)
        val off = repo.room("OFF")!!
        assertEquals("Off-site", off.name)
        assertFalse(off.hasPosition)
        assertNull(off.pos)
        assertNull(off.level)
        val r = repo.room("251AC")!!
        assertEquals(2, r.level)
        assertEquals("UC", r.attachNode)
        assertTrue(r.hasPosition)
        assertNull(repo.room("HL")!!.buildingLabel)
        // Every session's room exists.
        assertTrue(repo.sessions.all { repo.room(it.room) != null })
    }

    @Test
    fun wayfindingAndVenue() {
        val w = repo.wayfinding
        assertEquals(listOf("E200S", "EWT", "EHY", "E200W"), w.entrances.keys.toList())
        assertEquals(18, w.nodes.size)
        assertEquals(19, w.edges.size)
        assertEquals(84300.0, w.origin.metersPerDegLon, 0.0)
        assertEquals(listOf("S200", "LCS", "LCM", "NF"), w.routing.lowerConcourseMerge.nodes)
        assertEquals(setOf("SP", "HY"), repo.venue.buildings.keys)
        assertEquals(6, repo.venue.streets.size)
        assertEquals(5, repo.venue.zones.size)
    }

    @Test
    fun detailsAndSummitDetails() {
        assertEquals(562 + 223, repo.details.size) // details.json + colocated_details.json
        assertEquals(562, repo.details.keys.count { repo.session(it)?.isColocated != true })
        val d = repo.details["1203350"]!!
        assertEquals("Vinayak Goyal", d.speakers[0].name)
        assertEquals("Cluster Security @ Anthropic", d.speakers[0].tagline)
        assertEquals(14, repo.summitDetails.size)
        assertTrue(repo.summitDetails.keys.all { repo.session(it) != null })
        // The unconference feature is gone: no "UNCONF" entry ("See and vote on the topics").
        assertFalse(repo.summitDetails.containsKey("UNCONF"))
        assertTrue(repo.summitDetails.values.all { it.link == null && it.linkText == null })
        assertFalse(repo.summitDetails.containsKey("_about"))
    }

    @Test
    fun builtInCategoryColoursMatchScheduleJson() {
        for ((k, c) in repo.categories) {
            assertEquals(k, c.lightArgb, CategoryLight.getValue(k).toArgbInt())
            assertEquals(k, c.darkArgb, CategoryDark.getValue(k).toArgbInt())
        }
    }

    @Test
    fun mineAndAnthropicAtRuntime() {
        val mine = repo.mySessions("Lucy Sweet")
        assertEquals(3, mine.size)
        assertTrue(mine.all { it.day == "wed" })
        assertTrue(repo.mySessions(null).isEmpty())
        // Matches the precomputed flags for the default setting.
        for (s in repo.sessions) {
            assertEquals(s.id, s.precomputedIsMine, isMine(s, "Lucy Sweet"))
            assertEquals(s.id, s.precomputedHasAnthropic, repo.hasAnthropic(s, "Lucy Sweet"))
        }
        // With None, Lucy's own sessions count as Anthropic sessions.
        assertTrue(mine.all { repo.hasAnthropic(it, null) })
        assertEquals("You", speakerLabel("Lucy Sweet", "Lucy Sweet"))
        assertEquals("Lucy Sweet", speakerLabel("Lucy Sweet", null))
    }

    private fun androidx.compose.ui.graphics.Color.toArgbInt(): Int {
        fun ch(v: Float) = (v * 255f + 0.5f).toInt()
        return (ch(alpha) shl 24) or (ch(red) shl 16) or (ch(green) shl 8) or ch(blue)
    }
}
