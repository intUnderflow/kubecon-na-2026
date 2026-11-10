package app.kcna26.schedule

import app.kcna26.TestData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduleRulesTest {
    private val repo = TestData.repo

    /**
     * schedule.json's official sessions: the web rules made their category and group.
     * (colocated.json's and the evening parties' come precomputed.)
     */
    private val web = repo.sessions.filter { !it.isColocated && !it.id.startsWith(TestData.PARTY_ID_PREFIX) }

    /**
     * The three talks the web's /^(…|Break|…)/ files as breaks, with the category
     * (and group) they get with a word-bounded "Break". schedule.json may carry
     * either value for these, so the tests accept both.
     */
    private val misfiled = mapOf("1289638" to "mnt", "1336101" to "show", "1289733" to "mnt")

    @Test
    fun webExactPortReproducesTheJsonCategoriesAndGroups() {
        for (s in web) {
            if (s.id in misfiled) continue
            val cat = ScheduleRules.catOf(s, webExact = true)
            assertEquals("category of ${s.id} ${s.title}", s.category, cat)
            assertEquals("group of ${s.id} ${s.title}", s.group, ScheduleRules.seriesOf(s, cat))
        }
        for (id in misfiled.keys) assertEquals("log", ScheduleRules.catOf(repo.session(id)!!, webExact = true))
    }

    @Test
    fun fixedRegexOnlyChangesTheMisfiledBreakingTalks() {
        for (s in web) {
            val expected = misfiled[s.id] ?: s.category
            assertEquals("${s.id} ${s.title}", expected, ScheduleRules.catOf(s))
        }
        assertTrue(web.filter { ScheduleRules.isMisfiledBreak(it) }.all { it.id in misfiled })
        // Real breaks keep "log" and never list speakers (the co-located ones too).
        for (s in repo.sessions.filter { it.category == "log" && it.id !in misfiled }) {
            assertEquals(s.title, "log", ScheduleRules.catOf(s))
            assertTrue(s.speakers.isEmpty())
        }
    }

    @Test
    fun indexCorrectsTheMisfiledTalks() {
        val idx = ScheduleIndex.of(repo)
        val helm = repo.session("1289638")!! // Tue 250 D–F
        val istio = repo.session("1336101")!! // Wed Cosmic Canyon 3:55 PM
        val metal = repo.session("1289733")!! // Thu 251 A–C
        assertEquals("mnt", idx.category(helm))
        assertEquals(null, idx.group(helm))
        assertEquals("show", idx.category(istio))
        assertEquals("wed-istio", idx.group(istio)?.key)
        assertEquals("Istio Day", idx.group(istio)?.title)
        assertTrue(idx.groups.getValue("wed-istio").kids.any { it.id == "1336101" })
        assertEquals("mnt", idx.category(metal))
        // Everything else is the JSON value, co-located sessions included ("colo" talks, "log" breaks).
        for (s in repo.sessions.filter { it.id !in misfiled }) {
            assertEquals(s.category, idx.category(s))
            assertEquals(s.group, idx.group(s))
        }
        assertEquals(212, repo.sessions.count { it.isColocated && idx.category(it) == "colo" })
    }
}
