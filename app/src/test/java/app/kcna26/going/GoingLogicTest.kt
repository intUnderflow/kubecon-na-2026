package app.kcna26.going

import app.kcna26.TestData
import app.kcna26.schedule.ColoLine
import app.kcna26.schedule.DayStatus
import app.kcna26.schedule.GroupBlock
import app.kcna26.schedule.ScheduleIndex
import app.kcna26.schedule.SessionBlock
import app.kcna26.time.FixedClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class GoingLogicTest {
    private val repo = TestData.repo
    private val idx = ScheduleIndex.of(repo)
    private val lucy = "Lucy Sweet"
    private fun at(iso: String): Instant = FixedClock.parse(iso).now()
    private fun s(id: String) = repo.session(id)!!

    // Wednesday: Lucy speaks at 9:45 (1363905, keynote group), 2:20 (1249844, GI) and 5:00 (1289660, 251 A–C).
    private val rb220 = "1251049" // Regency Ballroom B, 2:20–2:50 PM
    private val ra220 = "1240105" // Regency Ballroom A, 2:20–3:40 PM (hands-on)
    private val rb500 = "1251218" // Regency Ballroom B, 5:00–5:30 PM
    private val cc250 = "1336094" // CC, 2:50–3:05 PM
    private val show120 = "1204401" // SHOW, 1:20–2:20 PM

    // ------------------------------------------------------------------ clashes

    @Test
    fun overlapIsStrictSoBackToBackIsNoClash() {
        assertTrue(GoingLogic.overlaps(s(rb220), s(ra220)))
        assertTrue(GoingLogic.overlaps(s(ra220), s(rb220)))
        assertFalse(GoingLogic.overlaps(s(show120), s(rb220))) // ends 2:20, the other starts 2:20
        assertFalse(GoingLogic.overlaps(s(rb220), s(cc250))) // ends 2:50, the other starts 2:50
        assertTrue(GoingLogic.overlaps(s(ra220), s(cc250)))
        assertFalse(GoingLogic.overlaps(s(rb220), s(rb500)))
    }

    @Test
    fun starredSessionsClashWithEachOtherAndWithMyTalks() {
        val going = setOf(rb220, ra220, rb500, show120)
        val c = GoingLogic.clashes(idx, going, lucy)
        assertEquals(setOf(rb220, ra220, rb500), c.keys)
        // Sorted by start, then id; my own talk is flagged.
        assertEquals(listOf(ra220 to false, "1249844" to true), c.getValue(rb220).map { it.session.id to it.mine })
        assertEquals(listOf("1249844" to true, rb220 to false), c.getValue(ra220).map { it.session.id to it.mine })
        assertEquals(listOf("1289660" to true), c.getValue(rb500).map { it.session.id to it.mine })
        // show120 ends as the others start: no clash, no tag.
        assertFalse(show120 in c)
    }

    @Test
    fun myTalksOnlyCountWhileIAmSpeakingAsThem() {
        val c = GoingLogic.clashes(idx, setOf(rb500), null)
        assertTrue(c.isEmpty())
        assertEquals(listOf("1289660"), GoingLogic.clashes(idx, setOf(rb500), lucy).getValue(rb500).map { it.session.id })
    }

    @Test
    fun lucysOwnTalksStarredToo() {
        // Lucy stars her own three talks as well as two sessions against them.
        val going = setOf("1363905", "1249844", "1289660", rb220, rb500)
        val c = GoingLogic.clashes(idx, going, lucy)
        // Her keynote slot clashes with nothing starred; the 2:20 and 5:00 talks do (each listed once).
        assertFalse("1363905" in c)
        assertEquals(listOf(rb220), c.getValue("1249844").map { it.session.id })
        assertEquals(listOf("1249844"), c.getValue(rb220).map { it.session.id })
        assertEquals(listOf(rb500), c.getValue("1289660").map { it.session.id })
    }

    @Test
    fun finishedSessionsNoLongerClash() {
        val going = setOf(rb220, ra220, cc250)
        // 2:30: everything is still on or to come.
        val mid = GoingLogic.clashes(idx, going, null, at("2026-11-11T14:30"))
        assertEquals(setOf(rb220, ra220, cc250), mid.keys)
        assertEquals(listOf(rb220, cc250), mid.getValue(ra220).map { it.session.id })
        // 2:55: RB's 2:20 talk is over; RA still overlaps CC.
        val later = GoingLogic.clashes(idx, going, null, at("2026-11-11T14:55"))
        assertEquals(setOf(ra220, cc250), later.keys)
        assertEquals(listOf(cc250), later.getValue(ra220).map { it.session.id })
        // Nothing left after 3:40.
        assertTrue(GoingLogic.clashes(idx, going, null, at("2026-11-11T15:45")).isEmpty())
    }

    @Test
    fun unknownIdsAndNoStarsGiveNoClashes() {
        assertTrue(GoingLogic.clashes(idx, emptySet(), lucy).isEmpty())
        assertTrue(GoingLogic.clashes(idx, setOf("gone"), lucy).isEmpty())
        assertEquals(listOf("1249844"), GoingLogic.clashesFor(idx, s(rb220), setOf(rb220, "gone"), lucy).map { it.session.id })
        // Not starred: no clash list, even though it overlaps my talk.
        assertTrue(GoingLogic.clashesFor(idx, s(ra220), setOf(rb220), lucy).isEmpty())
    }

    @Test
    fun sessionsInTheSameRoomNeverClash() {
        // Wednesday's posters: all ten in SHOW, 1:20–2:20 PM, one group card. Starring two is one visit.
        val posters = idx.groups.getValue("wed-posters").kids.map { it.id }
        assertEquals(10, posters.size)
        val two = setOf(posters[0], posters[1])
        assertTrue(GoingLogic.overlaps(s(posters[0]), s(posters[1])))
        assertTrue(GoingLogic.clashes(idx, two, null).isEmpty())
        assertTrue(GoingLogic.clashes(idx, posters.toSet(), lucy).isEmpty())
        // Tuesday's keynotes: "From Pod to Actuator" (10:41–10:46) overlaps "Closing Remarks" (10:44–10:45) in DE.
        val keynotes = idx.groups.getValue("tue-key").kids.map { it.id }.toSet()
        assertTrue(GoingLogic.overlaps(s("1380168"), s("1302802")))
        assertTrue(GoingLogic.clashes(idx, keynotes, null).isEmpty())
        // A poster still clashes with a starred talk elsewhere at the same time.
        val withTalk = GoingLogic.clashes(idx, setOf(posters[0], "1336094", "1240105"), null) // CC 2:50, RA 2:20–3:40
        assertFalse(posters[0] in withTalk)
        assertEquals(listOf("1240105"), withTalk.getValue("1336094").map { it.session.id })
    }

    @Test
    fun longRowsNeverClash() {
        // Monday: ArgoCon (all day, 151) with Project Lightning Talks and Peer Group Mentoring.
        val argo = "1289755"
        val talks = setOf("1289828", "1289870", "1345969")
        assertTrue(idx.isLong(s(argo)))
        assertTrue(talks.all { GoingLogic.overlaps(s(argo), s(it)) })
        assertTrue(GoingLogic.clashes(idx, talks + argo, null).isEmpty())
        // Off-site, too: Microsoft Azure Day (8 AM–6 PM, off-site) against a lightning talk.
        assertTrue(idx.isLong(s("1341814")))
        assertTrue(GoingLogic.overlaps(s("1341814"), s("1289828")))
        assertTrue(GoingLogic.clashes(idx, setOf("1341814", "1289828"), null).isEmpty())
        // Two ordinary talks still clash (with an all-day event starred too): RA 2:20 and CC 2:50 on Wednesday.
        assertEquals(setOf(ra220, cc250), GoingLogic.clashes(idx, setOf(ra220, cc250, "1289755"), null).keys)
    }

    // ------------------------------------------------------------------ up next

    @Test
    fun upNextIsTheNextStarredSessionToday() {
        val n = GoingLogic.upNext(idx, "wed", setOf(rb220, rb500), lucy, at("2026-11-11T14:08"))
        assertNotNull(n)
        n!!
        assertEquals(rb220, n.session.id)
        assertFalse(n.live)
        assertEquals("Your next", n.label)
        assertEquals("in 12 min", n.countdown)
        assertEquals("2:20–2:50 PM", n.time)
        assertEquals("Regency Ballroom B", n.roomName)
        assertEquals("Level 4", n.level)
        assertTrue(n.canRoute)
    }

    @Test
    fun aLiveStarredSessionIsShownUntilTheNextIsSoon() {
        val going = setOf(rb220, rb500)
        val live = GoingLogic.upNext(idx, "wed", going, lucy, at("2026-11-11T14:30"))!!
        assertEquals(rb220, live.session.id)
        assertTrue(live.live)
        // Never "Up next · Live": a session on now is labelled as such.
        assertEquals("On now", live.label)
        assertEquals("20 min left", live.countdown)
        // RB 2:20 is over: the 5:00 talk, hours away.
        val after = GoingLogic.upNext(idx, "wed", going, lucy, at("2026-11-11T14:50"))!!
        assertEquals(rb500, after.session.id)
        assertEquals("Your next", after.label)
        assertEquals("in 2h 10m", after.countdown)
        // RA's hands-on runs to 3:40; CC starts at 2:50. From 2:35 the soon one wins.
        val both = setOf(ra220, cc250)
        assertEquals(ra220, GoingLogic.upNext(idx, "wed", both, null, at("2026-11-11T14:30"))!!.session.id)
        val soon = GoingLogic.upNext(idx, "wed", both, null, at("2026-11-11T14:35"))!!
        assertEquals(cc250, soon.session.id)
        assertEquals("in 15 min", soon.countdown)
        assertEquals(ra220, GoingLogic.upNext(idx, "wed", both, null, at("2026-11-11T15:05"))!!.session.id)
    }

    @Test
    fun upNextLeavesOutMyTalksOtherDaysAndFinishedSessions() {
        // Lucy's own 2:20 talk, starred: the speaker banner has it, so not "Up next"...
        assertNull(GoingLogic.upNext(idx, "wed", setOf("1249844"), lucy, at("2026-11-11T14:00")))
        // ...unless she isn't speaking as herself.
        assertEquals("1249844", GoingLogic.upNext(idx, "wed", setOf("1249844"), null, at("2026-11-11T14:00"))!!.session.id)
        // Only on today's list.
        assertNull(GoingLogic.upNext(idx, "thu", setOf(rb220), lucy, at("2026-11-11T14:00")))
        assertNull(GoingLogic.upNext(idx, "wed", setOf(rb220), lucy, at("2026-11-10T14:00")))
        assertNull(GoingLogic.upNext(idx, null, setOf(rb220), lucy, at("2026-11-11T14:00")))
        // Before the conference there is no today.
        assertNull(GoingLogic.upNext(idx, "wed", setOf(rb220), lucy, at("2026-11-07T14:00")))
        // Over.
        assertNull(GoingLogic.upNext(idx, "wed", setOf(rb220), lucy, at("2026-11-11T14:50")))
        assertNull(GoingLogic.upNext(idx, "wed", emptySet(), lucy, at("2026-11-11T14:00")))
        assertNull(GoingLogic.upNext(idx, "wed", setOf("gone"), lucy, at("2026-11-11T14:00")))
    }

    @Test
    fun anAllDayEventOnNowDoesNotHideTheTalksInBetween() {
        val going = setOf("1289755", "1289870", "1345969") // ArgoCon all day; 11:03 lightning talk; 3:00 mentoring
        // 10:30: ArgoCon is on, but the 11:03 talk is the one to plan for.
        val n = GoingLogic.upNext(idx, "mon", going, null, at("2026-11-09T10:30"))!!
        assertEquals("1289870", n.session.id)
        assertEquals("Your next", n.label)
        assertEquals("in 33 min", n.countdown)
        // 11:05: the lightning talk is on now.
        assertEquals("1289870", GoingLogic.upNext(idx, "mon", going, null, at("2026-11-09T11:05"))!!.session.id)
        // 1 PM: nothing on but ArgoCon; the 3:00 mentoring is next.
        assertEquals("1345969", GoingLogic.upNext(idx, "mon", going, null, at("2026-11-09T13:00"))!!.session.id)
        // 4:10 PM: only ArgoCon is left, so it's shown, until its end.
        val argo = GoingLogic.upNext(idx, "mon", going, null, at("2026-11-09T16:10"))!!
        assertEquals("1289755", argo.session.id)
        assertTrue(argo.live)
        assertEquals("On now", argo.label)
        assertEquals("until 5:30 PM", argo.countdown)
        // Starred on its own, it's shown while it runs.
        assertEquals("1289755", GoingLogic.upNext(idx, "mon", setOf("1289755"), null, at("2026-11-09T10:30"))!!.session.id)
    }

    @Test
    fun countdownLabels() {
        assertEquals("in 1 min", GoingLogic.countdown(0))
        assertEquals("in 12 min", GoingLogic.countdown(12))
        assertEquals("in 1h", GoingLogic.countdown(60))
        assertEquals("in 1h 5m", GoingLogic.countdown(65))
    }

    // ------------------------------------------------------------------ filter

    private fun ids(view: app.kcna26.schedule.DayView): List<String> = view.slots.flatMap { sl ->
        sl.blocks.flatMap { b ->
            when (b) {
                is SessionBlock -> listOf(b.session.id)
                is GroupBlock -> b.kids.map { it.id }
            }
        }
    } + view.longs.map { it.session.id }

    @Test
    fun theFilterKeepsStarredSessionsAndMyTalks() {
        val now = at("2026-11-11T08:00")
        val full = idx.dayView("wed", now, lucy)!!
        val going = setOf(rb220, "1372841") // a talk and the 9:00 keynote
        val v = GoingLogic.filterDay(full, now) { GoingLogic.keeps(it, going, lucy) }
        assertEquals(listOf("1372841", "1363905", rb220, "1249844", "1289660").sorted(), ids(v).sorted())
        // Keynotes stay one group card, with just the kept kids.
        val g = v.slots.flatMap { it.blocks }.filterIsInstance<GroupBlock>().single()
        assertEquals(listOf("1372841", "1363905"), g.kids.map { it.id })
        // No breaks, no empty blocks.
        assertTrue(v.slots.all { it.blocks.isNotEmpty() })
        assertTrue(v.slots.flatMap { it.blocks }.none { it.category == "log" })
        assertEquals(full.day, v.day)
        // The status line counts what is shown: nothing on yet, the 9:00 keynote next.
        assertEquals(DayStatus(0, at("2026-11-11T09:00")), v.status)
    }

    @Test
    fun theFilteredStatusLineCountsOnlyTheShownSessions() {
        val now = at("2026-11-11T14:30")
        val full = idx.dayView("wed", now, null)!!
        assertTrue(full.status!!.onNow > 5)
        val going = setOf(rb220, rb500)
        val v = GoingLogic.filterDay(full, now) { GoingLogic.keeps(it, going, null) }
        // RB 2:20 is on; next is RB 5:00 (not the whole day's 2:50 or 3:00 starts).
        assertEquals(DayStatus(1, at("2026-11-11T17:00")), v.status)
        // Not today: no status line, filtered or not.
        assertNull(GoingLogic.filterDay(idx.dayView("thu", now, null)!!, now) { true }.status)
    }

    @Test
    fun aGroupMovesToTheBlockOfItsFirstKeptKid() {
        val now = at("2026-11-11T08:00")
        val full = idx.dayView("wed", now, null)!!
        val v = GoingLogic.filterDay(full, now) { it.id == "1363905" } // 9:45 keynote only
        val slot = v.slots.single()
        assertEquals(9 * 60 + 30, slot.key)
        assertEquals("9:45 AM", slot.label)
        assertEquals(listOf("1363905"), (slot.blocks.single() as GroupBlock).kids.map { it.id })
    }

    @Test
    fun theUpNextLineIsPlacedInTheFilteredBlocks() {
        val going = setOf(rb220, rb500, cc250)
        val now = at("2026-11-11T14:25")
        val full = idx.dayView("wed", now, lucy)!!
        val v = GoingLogic.filterDay(full, now) { GoingLogic.keeps(it, going, lucy) }
        // 2:20 (RB, Lucy's GI talk) is on; then 2:50 CC, then 5:00 (RB, Lucy's 251 A–C).
        assertEquals(listOf(14 * 60, 14 * 60 + 30, 17 * 60), v.slots.map { it.key })
        assertEquals(1, v.upNextBefore)
        // Not today: no line.
        val thu = idx.dayView("thu", now, lucy)!!
        assertEquals(-1, GoingLogic.filterDay(thu, now) { true }.upNextBefore)
        // Nothing on yet: the first block gets no line (web rule).
        val early = at("2026-11-11T08:00")
        val e = GoingLogic.filterDay(idx.dayView("wed", early, lucy)!!, early) { GoingLogic.keeps(it, going, lucy) }
        assertEquals(-1, e.upNextBefore)
    }

    @Test
    fun theFilterWithNothingKeptIsEmpty() {
        val now = at("2026-11-11T08:00")
        val v = GoingLogic.filterDay(idx.dayView("wed", now, null)!!, now) { false }
        assertTrue(v.isEmpty)
        assertEquals(-1, v.upNextBefore)
    }

    @Test
    fun coLocatedCardsKeepOnlyStarredTalksAndGoWhenNoneIsLeft() {
        val now = at("2026-11-09T08:00") // Monday, before the co-located events start
        val full = idx.dayView("mon", now, null)!!
        assertTrue(full.colo.size >= 2)
        val (a, b) = full.colo
        val talks = a.agenda.filter { !it.isBreak }
        assertTrue(talks.size >= 3 && a.agenda.any { it.isBreak })
        val starred = setOf(talks[1].session.id, talks[2].session.id)

        val v = GoingLogic.filterDay(full, now) { GoingLogic.keeps(it, starred, null) }
        // Only the card with starred talks is left, holding just those talks (no breaks).
        assertEquals(listOf(a.key), v.colo.map { it.key })
        val card = v.colo.single()
        assertEquals(starred.toList(), card.agenda.map { it.session.id })
        assertTrue(card.agenda.none { it.isBreak })
        assertFalse(b.key in v.colo.map { it.key })
        // Its "Starts …" line names the first starred talk, not the event's opening talk.
        val line = card.lines.single() as ColoLine.Starts
        assertEquals(talks[1].session.id, line.session?.id)
        assertFalse(v.isEmpty)

        // Nothing starred there: no co-located section at all.
        assertTrue(GoingLogic.filterDay(full, now) { false }.colo.isEmpty())
        // Everything kept: every card stays, with all its talks.
        val all = GoingLogic.filterDay(full, now) { true }
        assertEquals(full.colo.map { it.key }, all.colo.map { it.key })
        assertEquals(full.colo.map { c -> c.agenda.count { !it.isBreak } }, all.colo.map { it.agenda.size })
    }

    @Test
    fun searchResultsAreFilteredToo() {
        val now = at("2026-11-08T08:00")
        val all = idx.search("kubernetes", now, lucy)
        assertTrue(all.count > 10)
        val going = setOf("1249844", "gone")
        val r = GoingLogic.filterSearch(all) { GoingLogic.keeps(it, going, null) }
        assertEquals(1, r.count)
        assertEquals("1 match", r.heading)
        assertEquals("wed", r.days.single().day.key)
        assertEquals(0, GoingLogic.filterSearch(all) { false }.count)
        assertTrue(GoingLogic.filterSearch(all) { false }.days.isEmpty())
    }

    // ------------------------------------------------------------------ empty states

    private fun empty(
        goingOnly: Boolean,
        full: app.kcna26.schedule.DayView?,
        view: app.kcna26.schedule.DayView?,
        going: Set<String>,
        now: Instant,
        remindMinutes: Int = 10,
    ) = GoingLogic.emptyText(goingOnly, full, view, null, null, idx, going, now, remindMinutes)

    @Test
    fun emptyStatesExplainHowToStar() {
        val now = at("2026-11-11T08:00")
        val full = idx.dayView("wed", now, null)!!
        val empty = GoingLogic.filterDay(full, now) { false }
        // Filter off: the usual states.
        assertNull(empty(false, full, empty, emptySet(), now))
        // Nothing starred at all (unknown ids don't count).
        val none = empty(true, full, empty, setOf("gone"), now)!!
        assertEquals("No RSVPs yet", none.first)
        assertTrue(none.second.startsWith("Turn off RSVP’d above, then tap the star on any session to RSVP"))
        assertTrue(none.second.contains("with a reminder 10 min before it starts."))
        assertFalse(empty(true, full, empty, emptySet(), now, remindMinutes = 0)!!.second.contains("reminder"))
        // Stars on other days only: those days are named.
        val thu = "1247970" // Thursday 11:00
        assertEquals(
            "No RSVPs for Wednesday" to "You have 1 on Thursday. " + GoingText.DAY_TEXT,
            empty(true, full, empty, setOf(thu), now),
        )
        // The filtered day has something: no note.
        val some = GoingLogic.filterDay(full, now) { it.id == rb220 }
        assertNull(empty(true, full, some, setOf(rb220), now))
        // A day that is over keeps "That’s a wrap" (the off-site escape room runs to midnight).
        val late = at("2026-11-12T00:30")
        val over = idx.dayView("wed", late, null)!!
        assertTrue(over.isEmpty)
        assertNull(empty(true, over, GoingLogic.filterDay(over, late) { false }, setOf(thu), late))
    }

    @Test
    fun whenTodaysStarsAreOverTheNoteSaysSo() {
        // Wednesday 3 PM: RB 2:20 (starred) is over; Thursday has two stars.
        val now = at("2026-11-11T15:00")
        val going = setOf(rb220, "1247970", "1230488")
        val full = idx.dayView("wed", now, null)!!
        val view = GoingLogic.filterDay(full, now) { GoingLogic.keeps(it, going, null) }
        assertTrue(view.isEmpty)
        val (title, text) = empty(true, full, view, going, now)!!
        assertEquals("No RSVPs left today", title)
        assertEquals(
            "Your RSVP’d sessions for today are over. You have 2 on Thursday. Turn off RSVP’d above to see what’s still on.",
            text,
        )
        // Nothing elsewhere: no "You have" part.
        assertEquals(
            "Your RSVP’d sessions for today are over. Turn off RSVP’d above to see what’s still on.",
            empty(true, full, view, setOf(rb220), now)!!.second,
        )
        // Several days are listed in day order.
        assertEquals(
            "You have 1 on Wednesday and 2 on Thursday.",
            GoingText.othersText(listOf(1 to "Wednesday", 2 to "Thursday")),
        )
        assertEquals(
            "You have 1 on Tuesday, 1 on Wednesday and 2 on Thursday.",
            GoingText.othersText(listOf(1 to "Tuesday", 1 to "Wednesday", 2 to "Thursday")),
        )
        assertEquals(listOf("wed" to 1, "thu" to 2), GoingLogic.starredLeftByDay(idx, going + rb500, now))
    }

    @Test
    fun aSpeakerWithNoStarsIsToldHowToStarUnderTheirTalks() {
        // Lucy, Wednesday, nothing starred, filter on: her own talks are left, with the how-to note.
        val now = at("2026-11-11T08:00")
        val full = idx.dayView("wed", now, lucy)!!
        val view = GoingLogic.filterDay(full, now) { GoingLogic.keeps(it, emptySet(), lucy) }
        assertFalse(view.isEmpty)
        assertEquals("No RSVPs yet", empty(true, full, view, emptySet(), now)!!.first)
        // Once something is starred, the list speaks for itself.
        assertNull(empty(true, full, view, setOf(rb220), now))
        // Search: my talks match, nothing starred.
        val all = idx.search("Lucy Sweet", now, lucy)
        val mine = GoingLogic.filterSearch(all) { GoingLogic.keeps(it, emptySet(), lucy) }
        assertTrue(mine.count > 0)
        assertEquals("No RSVPs yet", GoingLogic.emptyText(true, null, null, all, mine, idx, emptySet(), now, 10)!!.first)
        assertNull(GoingLogic.emptyText(true, null, null, all, mine, idx, setOf(rb220), now, 10))
    }

    @Test
    fun searchEmptyStates() {
        val now = at("2026-11-08T08:00")
        val all = idx.search("kubernetes", now, null)
        val none = GoingLogic.filterSearch(all) { false }
        assertEquals(
            "No RSVP’d matches" to "Turn off RSVP’d to search every session.",
            GoingLogic.emptyText(true, null, null, all, none, idx, setOf(rb220), now, 10),
        )
        assertEquals("No RSVPs yet", GoingLogic.emptyText(true, null, null, all, none, idx, emptySet(), now, 10)!!.first)
        // No matches at all: the usual "No matches".
        val nothing = idx.search("zzzzqqq", now, null)
        assertNull(GoingLogic.emptyText(true, null, null, nothing, GoingLogic.filterSearch(nothing) { false }, idx, setOf(rb220), now, 10))
    }
}
