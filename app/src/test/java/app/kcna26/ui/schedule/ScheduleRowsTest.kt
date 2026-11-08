package app.kcna26.ui.schedule

import app.kcna26.TestData
import app.kcna26.schedule.GroupBlock
import app.kcna26.schedule.ScheduleIndex
import app.kcna26.schedule.SessionBlock
import app.kcna26.time.FixedClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduleRowsTest {
    private val idx = ScheduleIndex.of(TestData.repo)
    private val lucy = "Lucy Sweet"
    private fun at(iso: String) = FixedClock.parse(iso).now()

    private fun dayRows(day: String, iso: String, me: String? = lucy): List<Row> {
        val now = at(iso)
        return ScheduleRows.build(idx.dayView(day, now, me), idx.banner(day, now, me), null)
    }

    @Test
    fun keysAreUniqueOnEveryDayAndInSearch() {
        for (d in idx.days) {
            val rows = dayRows(d.key, "2026-11-07T12:00:00-07:00")
            assertEquals(d.key, rows.size, rows.map { it.key }.toSet().size)
        }
        val now = at("2026-11-07T12:00:00-07:00")
        val q = ScheduleRows.build(null, null, idx.search("kubernetes", now, lucy))
        assertEquals(q.size, q.map { it.key }.toSet().size)
    }

    @Test
    fun wednesdayOrder() {
        val rows = dayRows("wed", "2026-11-11T08:00:00-07:00")
        assertEquals(Row.Search, rows[0])
        assertTrue(rows[1] is Row.Banner)
        assertTrue(rows[2] is Row.DayHead)
        assertTrue(rows[3] is Row.SlotHead)
        assertEquals(Row.Footer, rows.last())
        // Today before the first block: no "Up next" line ahead of the first block.
        assertFalse(rows.subList(0, 4).contains(Row.UpNext))
        assertTrue(rows.none { it is Row.Empty })
        // Off-site section comes after the blocks (not Monday).
        val sect = rows.indexOfFirst { it is Row.Section }
        if (sect >= 0) assertTrue(sect > rows.indexOfLast { it is Row.SlotHead })
    }

    @Test
    fun mondayListsCoLocatedFirstAndSundayGoesStraightToTheBlocks() {
        val mon = dayRows("mon", "2026-11-09T08:00:00-07:00")
        // Day heading, then the "Co-located events" cards, then the blocks, then the off-site list.
        val head = mon.indexOfFirst { it is Row.DayHead }
        val sect = mon.indexOfFirst { it is Row.Section }
        assertEquals(head + 1, sect)
        assertEquals("Co-located events", (mon[sect] as Row.Section).title)
        assertTrue(mon[sect + 1] is Row.Colo)
        assertTrue(mon.indexOfLast { it is Row.Colo } < mon.indexOfFirst { it is Row.SlotHead })
        val offSite = mon.indexOfLast { it is Row.Section }
        assertEquals("Sponsor-hosted · off-site", (mon[offSite] as Row.Section).title)
        assertTrue(offSite > mon.indexOfLast { it is Row.SlotHead })
        // Sunday (the Summit): no Unconference entry card any more (voting is over); the day
        // heading is followed directly by the first half-hour block, unconference sessions included.
        for (at in listOf("2026-11-08T08:00:00-07:00", "2026-11-08T15:10:00-07:00")) {
            val sun = dayRows("sun", at)
            val head = sun.indexOfFirst { it is Row.DayHead }
            assertTrue(at, sun[head + 1] is Row.SlotHead || sun[head + 1] == Row.UpNext)
            assertTrue(at, sun.none { it.key == "unconf" })
            assertEquals(at, sun.size, sun.map { it.key }.distinct().size)
        }
    }

    @Test
    fun upNextLineSitsBeforeTheBlockAfterNow() {
        val rows = dayRows("sun", "2026-11-08T10:05:00-07:00")
        val i = rows.indexOf(Row.UpNext)
        assertTrue(i > 0)
        val next = rows[i + 1] as Row.SlotHead
        assertEquals("11:00 AM", next.slot.label)
        assertEquals(1, rows.count { it == Row.UpNext })
    }

    @Test
    fun breakRowsAndGroupsGetTheirOwnContentTypes() {
        val rows = dayRows("wed", "2026-11-11T08:00:00-07:00")
        val items = rows.filterIsInstance<Row.Item>()
        val group = items.first { it.block is GroupBlock }
        val brk = items.first { (it.block as? SessionBlock)?.category == "log" }
        val card = items.first { (it.block as? SessionBlock)?.category == "talk" }
        assertEquals(setOf(7, 8, 9), setOf(group.type, brk.type, card.type))
    }

    @Test
    fun wrapAndNoMatches() {
        val wrap = dayRows("sun", "2026-11-08T23:30:00-07:00")
        assertEquals(listOf(Row.Search::class, Row.DayHead::class, Row.Empty::class, Row.Footer::class), wrap.map { it::class })
        assertEquals(ScheduleRows.WRAP_TITLE, (wrap[2] as Row.Empty).title)
        val none = ScheduleRows.build(null, null, idx.search("zzzz", at("2026-11-08T08:00:00-07:00"), lucy))
        assertEquals("0 matches", (none[1] as Row.SearchHead).heading)
        assertEquals(ScheduleRows.NO_MATCHES_TEXT, (none[2] as Row.Empty).text)
    }

    @Test
    fun searchRowsAreGroupedByDayWithIndividualCards() {
        val res = idx.search("lucy", at("2026-11-08T08:00:00-07:00"), lucy)
        val rows = ScheduleRows.build(null, null, res)
        assertEquals(listOf("Wednesday, Nov 11"), rows.filterIsInstance<Row.Section>().map { it.title })
        val ids = rows.filterIsInstance<Row.Item>().map { (it.block as SessionBlock).session.id }
        assertEquals(listOf("1363905", "1249844", "1289660"), ids) // keynote shown as its own card in search
        assertTrue(rows.none { it is Row.Banner })
    }

    @Test
    fun coLocatedCardsOnePerRowOrTwoWithOpenAgendas() {
        val now = at("2026-11-09T08:00:00-07:00")
        val view = idx.dayView("mon", now, lucy)!!
        val all = view.colo.map { it.key }.toSet()
        assertEquals(11, all.size)
        for (columns in listOf(1, 2)) {
            for (open in listOf(emptySet(), setOf("colo-argocon"), all)) {
                val rows = ScheduleRows.build(view, null, null, columns, open)
                // Keys stay unique with ~230 more sessions and every card open.
                assertEquals("$columns $open", rows.size, rows.map { it.key }.toSet().size)
                val colo = rows.filterIsInstance<Row.Colo>()
                assertEquals(if (columns == 1) 11 else 6, colo.size)
                assertTrue(colo.all { it.cards.size <= columns })
                // A row is keyed by its leading card, so the key survives a re-chunk (a card leaving, fold/unfold).
                assertTrue(colo.all { it.key == "colo-" + it.cards.first().key })
                assertEquals(view.colo.map { it.key }, colo.flatMap { r -> r.cards.map { it.key } }) // alphabetical, in reading order
                val agendas = rows.filterIsInstance<Row.ColoAgenda>()
                assertEquals(open, agendas.map { it.card.key }.toSet())
                assertTrue(agendas.all { it.attached == (columns == 1) })
                // Each open agenda sits right after its card's row (or its pair's other agenda).
                for (a in agendas) {
                    val i = rows.indexOf(a)
                    val owner = rows.indexOfFirst { it is Row.Colo && it.cards.any { c -> c.key == a.card.key } }
                    assertTrue(i > owner)
                    assertTrue(rows.subList(owner + 1, i).all { it is Row.ColoAgenda })
                }
            }
        }
        // Search shows co-located talks as ordinary cards (with the event name as eyebrow), no event cards.
        val q = ScheduleRows.build(null, null, idx.search("argocon", now, lucy), 2, all)
        assertTrue(q.none { it is Row.Colo || it is Row.ColoAgenda })
        assertEquals(q.size, q.map { it.key }.toSet().size)
    }

    @Test
    fun jumpTargetsFindCoLocatedTalks() {
        val now = at("2026-11-09T08:00:00-07:00")
        val view = idx.dayView("mon", now, "Katie Lamkin-Fulsher")!!
        // Collapsed: the event's card. Open: the agenda row holding it.
        val closed = ScheduleRows.build(view, null, null, 1, emptySet())
        val i = ScheduleRows.indexOfSession(closed, "1312052")
        assertEquals("colo-argocon", (closed[i] as Row.Colo).cards.single().key)
        val opened = ScheduleRows.build(view, null, null, 2, setOf("colo-argocon"))
        val j = ScheduleRows.indexOfSession(opened, "1312052")
        assertEquals("colo-argocon", (opened[j] as Row.ColoAgenda).card.key)
    }

    @Test
    fun aBannerJumpToACoLocatedTalkWaitsForItsOpenAgenda() {
        // The banner tap opens the card and sends the jump in the same frame, so the jump's first look
        // is at the old rows, where the card is still collapsed. Settling on the card there (as
        // indexOfSession would) lands on the card head and never reveals the talk further down.
        val katie = "Katie Lamkin-Fulsher"
        val now = at("2026-11-09T08:00:00-07:00")
        val view = idx.dayView("mon", now, katie)!!
        val banner = idx.banner("mon", now, katie)!!
        val closing = "1312052" // ArgoCon closing remarks, 5:40 PM: far down a ~30-row agenda
        for (columns in 1..2) {
            val closed = ScheduleRows.build(view, banner, null, columns, emptySet())
            assertTrue(closed[ScheduleRows.indexOfSession(closed, closing)] is Row.Colo) // the old, wrong target
            assertEquals(-1, ScheduleRows.jumpIndex(closed, closing, "colo-argocon")) // keep waiting
            val open = setOf("colo-argocon")
            val opened = ScheduleRows.build(view, banner, null, columns, open)
            val j = ScheduleRows.jumpIndex(opened, closing, "colo-argocon")
            assertEquals("colo-argocon", (opened[j] as Row.ColoAgenda).card.key)
            assertTrue(ScheduleRows.revealsAfterJump(opened[j], closing, open))
            // The timeout fallback (the card head) still reveals the talk once its agenda is composed.
            val card = ScheduleRows.indexOfColoCard(opened, "colo-argocon")
            assertTrue(ScheduleRows.revealsAfterJump(opened[card], closing, open))
            assertFalse(ScheduleRows.revealsAfterJump(opened[card], closing, emptySet()))
        }
        // Anything else jumps as before: no agenda to wait for.
        val wed = dayRows("wed", "2026-11-11T08:00:00-07:00")
        assertEquals(ScheduleRows.indexOfSession(wed, "1249844"), ScheduleRows.jumpIndex(wed, "1249844", null))
        val keynote = ScheduleRows.jumpIndex(wed, "1363905", null)
        assertTrue(ScheduleRows.revealsAfterJump(wed[keynote], "1363905", emptySet())) // inside a group card
        val own = ScheduleRows.jumpIndex(wed, "1249844", null)
        assertFalse(ScheduleRows.revealsAfterJump(wed[own], "1249844", emptySet())) // its own card
    }

    @Test
    fun coLocatedRowKeysSurviveACardLeaving() {
        // CiliumCon's card goes at 12:30. Every row that still starts with the same card keeps its key.
        for (columns in 1..2) {
            fun keys(iso: String) = ScheduleRows.build(idx.dayView("mon", at(iso), lucy), null, null, columns)
                .filterIsInstance<Row.Colo>().associate { it.cards.first().key to it.key }
            val before = keys("2026-11-09T12:29:00-07:00")
            val after = keys("2026-11-09T12:30:00-07:00")
            assertEquals(before.size - 1, after.size) // 11 → 10 rows, or 6 → 5 pairs
            for ((lead, key) in after) if (lead in before) assertEquals(before[lead], key)
        }
    }

    @Test
    fun coLocatedCardsGoTwoUpOnlyInAWideListColumn() {
        // The cover screen's list (443 dp, 411 dp of content) and the unfolded list–detail pane
        // (852 dp × 0.47 = 400 dp, 368 dp of content) both get one card per row.
        assertEquals(1, ScheduleRows.coloColumns(411f))
        assertEquals(1, ScheduleRows.coloColumns(368f))
        assertEquals(1, ScheduleRows.coloColumns(559f))
        assertEquals(2, ScheduleRows.coloColumns(560f))
        assertEquals(2, ScheduleRows.coloColumns(728f))
    }

    @Test
    fun hidingAnAgendaFindsItsCard() {
        val view = idx.dayView("mon", at("2026-11-09T08:00:00-07:00"), lucy)!!
        for (columns in 1..2) {
            val rows = ScheduleRows.build(view, null, null, columns, setOf("colo-fluxcon"))
            val i = ScheduleRows.indexOfColoCard(rows, "colo-fluxcon")
            assertTrue((rows[i] as Row.Colo).cards.any { it.key == "colo-fluxcon" })
            assertTrue(rows[i + 1] is Row.ColoAgenda) // the agenda right under it
            // Collapsing doesn't move the card: same index without the agenda.
            assertEquals(i, ScheduleRows.indexOfColoCard(ScheduleRows.build(view, null, null, columns), "colo-fluxcon"))
        }
        assertEquals(-1, ScheduleRows.indexOfColoCard(ScheduleRows.build(view, null, null), "nope"))
    }

    @Test
    fun jumpTargetsFindCardsAndGroups() {
        val rows = dayRows("wed", "2026-11-11T08:00:00-07:00")
        val keynote = ScheduleRows.indexOfSession(rows, "1363905")
        assertTrue((rows[keynote] as Row.Item).block is GroupBlock)
        val gi = ScheduleRows.indexOfSession(rows, "1249844")
        assertEquals("1249844", ((rows[gi] as Row.Item).block as SessionBlock).session.id)
        assertEquals(-1, ScheduleRows.indexOfSession(rows, "nope"))
    }
}
