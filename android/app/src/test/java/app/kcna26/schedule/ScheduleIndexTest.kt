package app.kcna26.schedule

import app.kcna26.TestData
import app.kcna26.time.FixedClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class ScheduleIndexTest {
    private val repo = TestData.repo
    private val idx = ScheduleIndex.of(repo)
    private val lucy = "Lucy Sweet"

    private fun at(iso: String): Instant = FixedClock.parse(iso).now()
    private fun s(id: String) = repo.session(id)!!

    private fun DayView.allSessionIds(): List<String> =
        slots.flatMap { sl ->
            sl.blocks.flatMap { b ->
                when (b) {
                    is SessionBlock -> listOf(b.session.id)
                    is GroupBlock -> b.kids.map { it.id }
                }
            }
        } + longs.map { it.session.id }

    // ------------------------------------------------------------ blocks

    @Test
    fun blockIsLabelledWithItsEarliestRealStart() {
        val sun = idx.dayView("sun", at("2026-11-08T08:00:00-07:00"), lucy)!!
        val tenBlock = sun.slots.single { it.key == 600 } // 10:00–10:29
        assertEquals("10:15 AM", tenBlock.label)
        assertTrue(tenBlock.blocks.all { TimeFormatMinute.of(it.start) in 600..629 })
        // Every block's label is the earliest start in it, and blocks are in time order.
        for (sl in sun.slots) {
            assertEquals(sl.blocks.minOf { it.start }, sl.start)
            assertEquals(ScheduleLogic.slotKey(TimeFormatMinute.of(sl.start)), sl.key)
        }
        assertEquals(sun.slots.map { it.key }.sorted(), sun.slots.map { it.key })
        assertEquals(sun.slots.size, sun.slots.map { it.key }.toSet().size)
    }

    @Test
    fun finishedSessionsDisappear() {
        val now = at("2026-11-08T12:00:00-07:00")
        val sun = idx.dayView("sun", now, lucy)!!
        val ids = sun.allSessionIds().toSet()
        assertFalse("10:15–11:00 talk is over", "m1290687" in ids)
        assertTrue("12:20 lunch is still to come", "m1318414" in ids)
        assertTrue("open-ended reception is listed", "m1318417" in ids)
        for (id in ids) assertFalse(id, ScheduleLogic.isFinished(s(id), now))
        // The reception (no end) is still listed at 6:59 PM, gone at 7:00 PM.
        assertTrue("m1318417" in idx.dayView("sun", at("2026-11-08T18:59:00-07:00"), lucy)!!.allSessionIds())
        assertFalse("m1318417" in idx.dayView("sun", at("2026-11-08T19:00:00-07:00"), lucy)!!.allSessionIds())
    }

    @Test
    fun wrapWhenTheDayIsOver() {
        val sun = idx.dayView("sun", at("2026-11-08T23:00:00-07:00"), lucy)!!
        assertTrue(sun.isEmpty)
        assertFalse(idx.dayView("thu", at("2026-11-08T23:00:00-07:00"), lucy)!!.isEmpty)
    }

    @Test
    fun groupsBecomeOneCardWithUnfinishedKids() {
        val now = at("2026-11-11T09:46:00-07:00")
        val wed = idx.dayView("wed", now, lucy)!!
        val keynotes = wed.slots.flatMap { it.blocks }.filterIsInstance<GroupBlock>().single { it.group.key == "wed-key" }
        assertEquals("Morning keynotes", keynotes.group.title)
        assertEquals("DE", keynotes.room)
        assertEquals("key", keynotes.category)
        assertEquals("1363905", keynotes.kids.first().id) // 9:45 is still on; earlier keynotes are gone
        assertTrue(keynotes.kids.none { ScheduleLogic.isFinished(it, now) })
        assertEquals(13, idx.groups.getValue("wed-key").kids.size)
        assertEquals("wed-key", idx.groupKeyOf("1363905"))
        // No grouped session is also shown on its own.
        val singles = wed.slots.flatMap { it.blocks }.filterIsInstance<SessionBlock>().map { it.session.id }
        assertFalse("1363905" in singles)
        // The group sits in the block of its earliest remaining kid (9:45 → the 9:30 block).
        val slot = wed.slots.single { sl -> sl.blocks.any { it === keynotes } }
        assertEquals(570, slot.key)
    }

    @Test
    fun myTalksSortFirstThenTheNormalOrderInABlock() {
        val at2 = at("2026-11-11T14:00:00-07:00")
        val wed = idx.dayView("wed", at2, lucy)!!
        val slot = wed.slots.single { it.key == 840 }
        val first = slot.blocks[0] as SessionBlock
        assertEquals("1249844", first.session.id) // Kubernetes The Hard Way - Live (mine)
        assertTrue(first.mine)
        // The rest: category, then room. An Anthropic talk gets no head start (Vinayak Goyal's
        // 1203350 keeps its badge but sits where its category and room put it).
        val rest = slot.blocks.drop(1)
        assertTrue(rest.none { it.mine })
        assertTrue(rest.any { it is SessionBlock && it.session.id == "1203350" && it.anthropic })
        assertEquals(rest.sortedWith(normalOrder), rest)
        // With None, Lucy's talk is just an Anthropic talk: the whole block is in the normal order.
        val none = idx.dayView("wed", at2, null)!!.slots.single { it.key == 840 }
        assertTrue(none.blocks.none { it.mine })
        assertEquals(none.blocks.sortedWith(normalOrder), none.blocks)
        assertTrue(none.blocks.single { it is SessionBlock && it.session.id == "1249844" }.anthropic)
    }

    /** The block order without "mine": start, category, then room (rooms.json order). */
    private val normalOrder: Comparator<Block> by lazy {
        val rooms = TestData.repo.rooms.keys.withIndex().associate { (i, k) -> k to i }
        compareBy<Block> { it.start }
            .thenBy { ScheduleIndex.CATEGORY_ORDER[it.category] ?: ScheduleIndex.CATEGORY_ORDER.size }
            .thenBy { rooms[it.room] ?: -1 }
    }

    @Test
    fun mondayLongsAreTheSponsorHostedOffSiteEvents() {
        // The CNCF co-located events are cards above the blocks now (ColocatedTest); their
        // All-Access placeholders are gone from the list, leaving the separate-registration events.
        val mon = idx.dayView("mon", at("2026-11-09T08:00:00-07:00"), lucy)!!
        assertEquals("Sponsor-hosted · off-site", mon.longsTitle)
        assertFalse(mon.longsFirst)
        assertEquals(12, mon.longs.size)
        assertTrue(mon.longs.all { it.session.room == "OFF" })
        assertTrue(mon.longs.none { it.session.note == "All-Access pass" })
        assertEquals(11, mon.colo.size)
        val sun = idx.dayView("sun", at("2026-11-08T08:00:00-07:00"), lucy)!!
        assertEquals("Off-site", sun.longsTitle)
        assertFalse(sun.longsFirst)
        assertEquals(listOf("1344383"), sun.longs.map { it.session.id }) // the hackathon
    }

    @Test
    fun todayStatusAndUpNextLine() {
        val now = at("2026-11-08T10:05:00-07:00")
        val sun = idx.dayView("sun", now, lucy)!!
        assertTrue(sun.isToday)
        val st = sun.status!!
        assertEquals(0, st.onNow)
        assertEquals(at("2026-11-08T10:15:00-07:00"), st.nextStart)
        // Web: the line goes before the first block whose half-hour is after now (11:00), not the first block.
        assertEquals(1100, TimeFormatMinute.hhmm(sun.slots[sun.upNextBefore].start))
        assertTrue(sun.upNextBefore > 0)
        // Other days: no status, no line.
        val mon = idx.dayView("mon", now, lucy)!!
        assertNull(mon.status)
        assertEquals(-1, mon.upNextBefore)
    }

    @Test
    fun unconferenceSessionsAreOrdinarySundaySessions() {
        // 3:10 PM on Sunday: the 3:05 unconference sessions are live cards in the normal blocks.
        val sun = idx.dayView("sun", at("2026-11-08T15:10:00-07:00"), lucy)!!
        val shown = sun.slots.flatMap { it.blocks }.filterIsInstance<SessionBlock>().map { it.session }
        val unconf = shown.filter { it.note == "Unconference" }
        assertEquals(setOf("m1318482", "m1318481", "m1318480", "m1318486", "m1318484", "m1318483"), unconf.map { it.id }.toSet())
        assertTrue(unconf.all { it.title.startsWith("Unconference: ") && it.speakers.isNotEmpty() })
        assertTrue(unconf.all { idx.category(it) == "com" })
    }

    // ------------------------------------------------------------ mine / Anthropic

    @Test
    fun mineAndAnthropicFollowTheSetting() {
        val keynote = s("1363905") // Lucy alone
        val kthw = s("1249844") // Lucy + Sandeep Kanabar
        val vinayak = s("1203350") // Anthropic colleague
        // Lucy Sweet
        assertTrue(idx.isMine(keynote, lucy))
        assertTrue(idx.isMine(kthw, lucy))
        assertFalse(idx.hasAnthropic(kthw, lucy))
        assertTrue(idx.hasAnthropic(vinayak, lucy))
        assertFalse(idx.isMine(vinayak, lucy))
        // Another speaker: their talk is mine; Lucy's other talks become Anthropic talks.
        val sandeep = "Sandeep Kanabar"
        assertTrue(idx.isMine(kthw, sandeep))
        assertFalse(idx.hasAnthropic(kthw, sandeep))
        assertFalse(idx.isMine(keynote, sandeep))
        assertTrue(idx.hasAnthropic(keynote, sandeep))
        // None
        assertFalse(idx.isMine(keynote, null))
        assertTrue(idx.hasAnthropic(keynote, null))
        assertTrue(idx.hasAnthropic(vinayak, null))
        // The precomputed flags are never consulted: a speaker the JSON didn't flag.
        assertTrue(repo.sessions.none { idx.isMine(it, null) })
    }

    @Test
    fun dayTabsMarkDaysWithMyTalksStillToCome() {
        val tue = idx.dayTabs(at("2026-11-10T10:00:00-07:00"), lucy)
        assertEquals(listOf("tue", "wed", "thu"), tue.map { it.key })
        assertEquals(listOf("Today", "Wed", "Thu"), tue.map { it.label })
        assertEquals(listOf(10, 11, 12), tue.map { it.number })
        assertEquals(listOf(false, true, false), tue.map { it.hasMine })
        // After her last talk the Wednesday mark goes.
        assertTrue(idx.dayTabs(at("2026-11-11T17:29:00-07:00"), lucy).first { it.key == "wed" }.hasMine)
        assertFalse(idx.dayTabs(at("2026-11-11T17:30:00-07:00"), lucy).first { it.key == "wed" }.hasMine)
        // None: no marks. Someone else: their days.
        assertTrue(idx.dayTabs(at("2026-11-08T08:00:00-07:00"), null).none { it.hasMine })
        val decheng = idx.dayTabs(at("2026-11-08T08:00:00-07:00"), "Decheng Dai")
        assertEquals(listOf("thu"), decheng.filter { it.hasMine }.map { it.key })
        // Before the conference every day is a tab, none is "Today".
        val before = idx.dayTabs(at("2026-11-07T10:00:00-07:00"), lucy)
        assertEquals(5, before.size)
        assertTrue(before.none { it.label == "Today" })
    }

    // ------------------------------------------------------------ banner

    @Test
    fun wednesdayBannerShowsLucysThreeTalks() {
        val b = idx.banner("wed", at("2026-11-11T08:00:00-07:00"), lucy)!!
        assertEquals("1363905", b.next.id) // 9:45 keynote, inside the Morning keynotes group
        assertEquals("wed-key", idx.groupKeyOf(b.next.id))
        assertEquals("9:45 AM", b.nextTime)
        assertEquals("In 1h 45m", b.countdown)
        assertFalse(b.soon)
        assertEquals("Hall DE · Salt Palace L1 · Keynote", b.nextWhere)
        assertEquals(listOf("1249844", "1289660"), b.later.map { it.session.id })
        assertEquals(listOf("2:20 PM", "5:00 PM"), b.later.map { it.time })
        assertEquals(listOf("Grand Ballroom GI", "251 A–C"), b.later.map { it.roomName })
    }

    @Test
    fun bannerCountsDownAndSaysHeadToWhenSoon() {
        val live = idx.banner("wed", at("2026-11-11T09:46:00-07:00"), lucy)!!
        assertEquals("On now", live.countdown)
        assertTrue(live.soon)
        assertTrue(live.live)
        assertEquals("Head to Hall DE · Salt Palace L1 · Keynote", live.nextWhere)

        val gi = idx.banner("wed", at("2026-11-11T13:40:00-07:00"), lucy)!!
        assertEquals("1249844", gi.next.id)
        assertEquals("In 40 min", gi.countdown)
        assertTrue(gi.soon)
        assertEquals("Head to Grand Ballroom GI · Salt Palace L1", gi.nextWhere)
        assertEquals(listOf("1289660"), gi.later.map { it.session.id })

        val notYet = idx.banner("wed", at("2026-11-11T13:30:00-07:00"), lucy)!!
        assertEquals("In 50 min", notYet.countdown)
        assertFalse(notYet.soon)
        assertEquals("Grand Ballroom GI · Salt Palace L1", notYet.nextWhere)

        val last = idx.banner("wed", at("2026-11-11T16:30:00-07:00"), lucy)!!
        assertEquals("1289660", last.next.id)
        assertEquals("Head to 251 A–C · Salt Palace L2", last.nextWhere)
        assertTrue(last.later.isEmpty())

        assertNull(idx.banner("wed", at("2026-11-11T17:30:00-07:00"), lucy))
    }

    @Test
    fun bannerForAnotherDaySaysTomorrowOrTheWeekday() {
        val tue = idx.banner("wed", at("2026-11-10T12:00:00-07:00"), lucy)!!
        assertEquals("Tomorrow", tue.countdown)
        assertEquals("Wed 9:45 AM", tue.nextTime)
        assertFalse(tue.soon)
        assertEquals(listOf("2:20 PM", "5:00 PM"), tue.later.map { it.time })
        val mon = idx.banner("wed", at("2026-11-09T12:00:00-07:00"), lucy)!!
        assertEquals("Wednesday", mon.countdown)
    }

    @Test
    fun noBannerOnDaysWithoutMyTalksForNoneOrWhileSearching() {
        val now = at("2026-11-10T09:00:00-07:00")
        for (d in listOf("sun", "mon", "tue", "thu")) assertNull(d, idx.banner(d, now, lucy))
        assertNull(idx.banner("wed", now, null))
        assertNull(idx.banner("wed", now, lucy, searching = true))
        assertNull(idx.banner(null, now, lucy))
        // Another speaker gets their own banner.
        val d = idx.banner("thu", now, "Decheng Dai")!!
        assertEquals(listOf("1250150", "1228453"), listOf(d.next.id) + d.later.map { it.session.id })
    }

    // ------------------------------------------------------------ search

    private fun searchIds(q: String, now: String = "2026-11-08T08:00:00-07:00", me: String? = lucy) =
        idx.search(q, at(now), me).days.flatMap { it.sessions }.map { it.session.id }

    @Test
    fun searchMatchesTitleSpeakerRoomAndCategoryIgnoringCaseAndAccents() {
        assertTrue("1289660" in searchIds("EVICTION"))
        assertTrue("1289660" in searchIds("krepinsky")) // Filip Křepinský
        assertTrue("1289660" in searchIds("Křepinský"))
        assertTrue("1247612" in searchIds("rozacki")) // Maciek Różacki
        val roomHits = searchIds("251 a–c")
        assertTrue(roomHits.isNotEmpty())
        assertTrue(roomHits.all { s(it).room == "251AC" || "251" in s(it).title || s(it).speakers.any { n -> "251" in n } })
        assertEquals(roomHits, searchIds("251 a-c")) // en dash or hyphen
        val maint = searchIds("maintainer")
        assertTrue(maint.any { idx.category(s(it)) == "mnt" && "maintainer" !in s(it).title.lowercase() })
        // All terms must match.
        assertEquals(listOf("1289660"), searchIds("eviction lucy"))
        assertTrue(searchIds("eviction zzzz").isEmpty())
    }

    @Test
    fun searchCoversTheRestOfTheWeekWithoutBreaks() {
        val all = idx.search("kubernetes", at("2026-11-11T12:00:00-07:00"), lucy)
        val ids = all.days.flatMap { it.sessions }.map { it.session.id }
        assertEquals(all.count, ids.size)
        assertEquals(listOf("wed", "thu"), all.days.map { it.day.key })
        for (id in ids) assertFalse(ScheduleLogic.isFinished(s(id), at("2026-11-11T12:00:00-07:00")))
        for (d in all.days) assertEquals(d.sessions.sortedBy { it.start }, d.sessions)
        assertTrue(searchIds("coffee").none { idx.isBreak(s(it)) })
        assertTrue(searchIds("lunch").none { idx.isBreak(s(it)) })
        // The misfiled "Breaking…" talks are searchable.
        assertTrue("1289638" in searchIds("helm 4"))
        assertEquals("1 match", SearchResults(1, emptyList()).heading)
        assertEquals("0 matches", idx.search("zzzz", at("2026-11-08T08:00:00-07:00"), lucy).heading)
        assertEquals(0, idx.search("   ", at("2026-11-08T08:00:00-07:00"), lucy).count)
    }

    @Test
    fun anthropicKeywordFollowsTheSetting() {
        val withLucy = searchIds("anthropic").toSet()
        assertTrue("1249844" in withLucy) // mine
        assertTrue("1203350" in withLucy) // colleague
        val withNone = searchIds("anthropic", me = null).toSet()
        assertTrue("1249844" in withNone) // Lucy is a colleague under None
        val withOther = searchIds("anthropic", me = "Graham Helton").toSet()
        assertTrue("1203350" in withOther) // his own talk counts as mine
    }

    @Test
    fun cardStatusForLiveCards() {
        val eviction = s("1289660")
        val st = idx.cardStatus(eviction, at("2026-11-11T17:10:00-07:00"))
        assertTrue(st.live)
        assertEquals("Live · 20 min left", st.liveLabel)
        assertNotNull(st.progress)
        assertEquals(CardStatus.NotLive, idx.cardStatus(eviction, at("2026-11-11T16:00:00-07:00")))
        val hackathon = s("1344383") // off-site, long
        val h = idx.cardStatus(hackathon, at("2026-11-08T10:00:00-07:00"))
        assertEquals("On now", h.liveLabel)
        assertNull(h.progress)
    }
}

/** Small helpers for readable assertions. */
private object TimeFormatMinute {
    fun of(t: Instant): Int = app.kcna26.time.TimeFormat.minuteOfDay(t)
    fun hhmm(t: Instant): Int = of(t).let { (it / 60) * 100 + it % 60 }
}
