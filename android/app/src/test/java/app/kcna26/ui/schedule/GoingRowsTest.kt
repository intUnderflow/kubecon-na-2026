package app.kcna26.ui.schedule

import app.kcna26.TestData
import app.kcna26.going.GoingLogic
import app.kcna26.schedule.ScheduleIndex
import app.kcna26.time.FixedClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The "Going" rows: "Up next" beside the speaker banner, the filtered list and its empty state. */
class GoingRowsTest {
    private val idx = ScheduleIndex.of(TestData.repo)
    private val lucy = "Lucy Sweet"
    private fun at(iso: String) = FixedClock.parse(iso).now()
    private val going = setOf("1251049", "1251218")

    @Test
    fun upNextSitsUnderTheSpeakerBannerOnDaysISpeak() {
        val now = at("2026-11-11T14:00")
        val next = GoingLogic.upNext(idx, "wed", going, lucy, now)
        val rows = ScheduleRows.build(idx.dayView("wed", now, lucy), idx.banner("wed", now, lucy), null, goingNext = next)
        assertEquals(Row.Search, rows[0])
        assertTrue(rows[1] is Row.Banner)
        assertEquals("1251049", (rows[2] as Row.GoingNext).next.session.id)
        assertTrue(rows[3] is Row.DayHead)
        assertEquals(rows.size, rows.map { it.key }.toSet().size)
        assertEquals(1, rows.count { it.key == "goingnext" })
    }

    @Test
    fun upNextWithoutABannerAndNeverInSearch() {
        val now = at("2026-11-11T14:00")
        val next = GoingLogic.upNext(idx, "wed", going, null, now)
        val rows = ScheduleRows.build(idx.dayView("wed", now, null), idx.banner("wed", now, null), null, goingNext = next)
        assertTrue(rows[1] is Row.GoingNext)
        assertTrue(rows[2] is Row.DayHead)
        val q = ScheduleRows.build(null, null, idx.search("gateway", now, null), goingNext = next)
        assertTrue(q.none { it is Row.GoingNext })
    }

    @Test
    fun theFilteredDayKeepsStableKeysAndShowsTheGoingEmptyState() {
        val now = at("2026-11-11T08:00")
        val full = idx.dayView("wed", now, null)!!
        val filtered = GoingLogic.filterDay(full, now) { it.id in going }
        val all = ScheduleRows.build(full, null, null)
        val some = ScheduleRows.build(filtered, null, null)
        // Every filtered row is a row of the full list, with the same key (LazyColumn keeps its place).
        val allKeys = all.map { it.key }.toSet()
        assertTrue(some.all { it.key in allKeys })
        assertEquals(listOf("s-1251049", "s-1251218"), some.filterIsInstance<Row.Item>().map { it.key })

        val none = GoingLogic.filterDay(full, now) { false }
        val (title, text) = GoingLogic.emptyText(true, full, none, null, null, idx, emptySet(), now, 10)!!
        val rows = ScheduleRows.build(none, null, null, empty = Row.Empty(title, text))
        val empty = rows.single { it is Row.Empty } as Row.Empty
        assertEquals("No RSVPs yet", empty.title)
        assertTrue(rows.none { it is Row.Item })
    }

    @Test
    fun theHowToStarNoteFollowsMyOwnTalks() {
        // Lucy, nothing starred, filter on: her three Wednesday talks, then the note, then the footer.
        val now = at("2026-11-11T08:00")
        val full = idx.dayView("wed", now, lucy)!!
        val mine = GoingLogic.filterDay(full, now) { GoingLogic.keeps(it, emptySet(), lucy) }
        val (title, text) = GoingLogic.emptyText(true, full, mine, null, null, idx, emptySet(), now, 10)!!
        val rows = ScheduleRows.build(mine, idx.banner("wed", now, lucy), null, empty = Row.Empty(title, text))
        // The 9:45 keynote (in the keynotes card), 2:20 in GI and 5:00 in 251 A–C.
        val items = rows.withIndex().filter { it.value is Row.Item }
        assertEquals(3, items.size)
        for (id in listOf("1363905", "1249844", "1289660")) assertTrue(ScheduleRows.indexOfSession(rows, id) >= 0)
        val note = rows.indexOfFirst { it is Row.Empty }
        assertTrue(note > items.last().index)
        assertEquals(Row.Footer, rows[note + 1])
        assertEquals(rows.size, rows.map { it.key }.toSet().size)
        // Search: the note follows the matching talks too.
        val q = ScheduleRows.build(null, null, idx.search("Lucy Sweet", now, lucy), empty = Row.Empty(title, text))
        assertTrue(q.indexOfFirst { it is Row.Empty } > q.indexOfLast { it is Row.Item })
    }

    @Test
    fun withoutAnOverrideTheUsualEmptyStatesStay() {
        val now = at("2026-11-08T08:00")
        val rows = ScheduleRows.build(null, null, idx.search("zzzzqqq", now, null))
        assertEquals(ScheduleRows.NO_MATCHES_TITLE, (rows.single { it is Row.Empty } as Row.Empty).title)
        val starred = ScheduleRows.build(null, null, idx.search("zzzzqqq", now, null), empty = Row.Empty("No starred matches", "x"))
        assertEquals("No starred matches", (starred.single { it is Row.Empty } as Row.Empty).title)
    }
}
