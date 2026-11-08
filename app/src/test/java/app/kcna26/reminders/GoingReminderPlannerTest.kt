package app.kcna26.reminders

import app.kcna26.TestData
import app.kcna26.time.FixedClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** The reminder planner with starred ("Going") sessions mixed in with my own talks. */
class GoingReminderPlannerTest {

    private val repo = TestData.repo
    private val lucy = "Lucy Sweet"

    private val rb220 = "1251049" // "In-Place Pod Resizing Like I'm 5…", Regency Ballroom B (Hyatt L4), Wed 2:20 PM
    private val rb500 = "1251218" // "Feeling Lost? A Newcomer's Guide to the Gateway API", Regency Ballroom B, Wed 5:00 PM
    private val off = "1344383" // Agent Rush Hackathon, Off-site, Sun 9:00 AM

    private fun at(iso: String): Instant = FixedClock.parse(iso).now()

    private fun plan(me: String?, now: String, going: Set<String>, minutes: Int = 10) =
        ReminderPlanner.plan(repo.sessions, repo.rooms, me, at(now), going, minutes)

    @Test
    fun aStarredSessionGetsOneReminderWithTheGoingText() {
        val r = plan(null, "2026-11-10T12:00", setOf(rb220)).single()
        assertEquals(rb220, r.sessionId)
        assertEquals(ReminderKind.GOING, r.kind)
        assertEquals(10, r.minutesBefore)
        assertEquals(at("2026-11-11T14:10"), r.triggerAt)
        assertEquals(repo.session(rb220)!!.title, r.title)
        assertEquals("Starting in 10 min · Regency Ballroom B, Level 4", r.text)
        assertEquals("$rb220/10", r.key)
    }

    @Test
    fun theLeadTimeFollowsTheSetting() {
        for (m in listOf(5, 10, 15)) {
            val r = plan(null, "2026-11-10T12:00", setOf(rb220), m).single()
            assertEquals(m, r.minutesBefore)
            assertEquals(repo.session(rb220)!!.start.minusSeconds(m * 60L), r.triggerAt)
            assertEquals("Starting in $m min · Regency Ballroom B, Level 4", r.text)
        }
    }

    @Test
    fun offMeansNoGoingRemindersButMyTalksKeepTheirs() {
        assertTrue(plan(null, "2026-11-10T12:00", setOf(rb220, rb500), 0).isEmpty())
        val mine = plan(lucy, "2026-11-10T12:00", setOf(rb220, rb500), 0)
        assertEquals(6, mine.size)
        assertTrue(mine.all { it.kind == ReminderKind.MINE })
    }

    @Test
    fun myTalksAndStarredSessionsMix() {
        val r = plan(lucy, "2026-11-10T12:00", setOf(rb220, rb500))
        assertEquals(
            listOf(
                "1363905/30", "1363905/10",
                "1249844/30", "1249844/10", "$rb220/10",
                "1289660/30", "$rb500/10", "1289660/10",
            ),
            r.map { it.key },
        )
        assertEquals(r.sortedBy { it.triggerAt }, r)
        // Same trigger time for my 2:20 talk's 10-minute reminder and the starred 2:20 session: both
        // arm (different sessions), ordered by id.
        assertEquals(at("2026-11-11T14:10"), r.single { it.key == "1249844/10" }.triggerAt)
        assertEquals(at("2026-11-11T14:10"), r.single { it.key == "$rb220/10" }.triggerAt)
        assertEquals("Your talk in 10 min · Grand Ballroom GI, Level 1", r.single { it.key == "1249844/10" }.text)
        assertEquals("Starting in 10 min · Regency Ballroom B, Level 4", r.single { it.key == "$rb220/10" }.text)
    }

    @Test
    fun lucysWednesdayTalksStarredTooAreNotDoubleNotified() {
        val talks = setOf("1363905", "1249844", "1289660")
        for (m in listOf(5, 10, 15)) {
            val r = plan(lucy, "2026-11-10T12:00", talks + rb220, m)
            // Still exactly the six talk reminders (30 and 10), plus the one starred session.
            assertEquals(7, r.size)
            assertEquals(6, r.count { it.kind == ReminderKind.MINE })
            for (id in talks) {
                assertEquals(listOf(30, 10), r.filter { it.sessionId == id }.map { it.minutesBefore })
                assertTrue(r.filter { it.sessionId == id }.all { it.text.startsWith("Your talk in ") })
            }
            assertEquals(listOf(m), r.filter { it.sessionId == rb220 }.map { it.minutesBefore })
        }
        // The keys stay unique, so every alarm is distinct.
        val keys = plan(lucy, "2026-11-10T12:00", talks + rb220).map { it.key }
        assertEquals(keys.size, keys.toSet().size)
    }

    @Test
    fun whenTheSpeakingAsChangesAStarredTalkBecomesAGoingReminder() {
        // Lucy's 2:20 talk, starred, while speaking as someone else (or None).
        val r = plan(null, "2026-11-10T12:00", setOf("1249844")).single()
        assertEquals(ReminderKind.GOING, r.kind)
        assertEquals("Starting in 10 min · Grand Ballroom GI, Level 1", r.text)
        assertEquals(1, plan("Ryan Hallisey", "2026-11-10T12:00", setOf("1249844")).count { it.sessionId == "1249844" })
    }

    @Test
    fun pastSessionsAndPastRemindersAreDropped() {
        val going = setOf(rb220, rb500)
        // 2:12: the 2:10 reminder for RB 2:20 is past; the 4:50 one for 5:00 stays.
        assertEquals(listOf("$rb500/10"), plan(null, "2026-11-11T14:12", going).map { it.key })
        // Exactly at the trigger time: not in the future any more.
        assertEquals(listOf("$rb500/10"), plan(null, "2026-11-11T14:10", going).map { it.key })
        assertEquals(listOf("$rb220/10", "$rb500/10"), plan(null, "2026-11-11T14:09", going).map { it.key })
        // After the start (live or over): nothing.
        assertTrue(plan(null, "2026-11-11T16:55", going).isEmpty())
        assertTrue(plan(null, "2026-11-12T09:00", going).isEmpty())
        // With 15 min, a session 12 minutes away gets no reminder (it would be in the past).
        assertTrue(plan(null, "2026-11-11T14:08", setOf(rb220), 15).isEmpty())
    }

    @Test
    fun unknownStarredIdsAreIgnored() {
        assertTrue(plan(null, "2026-11-10T12:00", setOf("gone", "also-gone")).isEmpty())
        assertEquals(listOf("$rb220/10"), plan(null, "2026-11-10T12:00", setOf("gone", rb220)).map { it.key })
    }

    @Test
    fun goingTextUsesTheReminderRoomRules() {
        assertEquals("Starting in 10 min · 251 A–C, Level 2", ReminderPlanner.goingText(10, repo.room("251AC")))
        assertEquals("Starting in 5 min · Off-site", ReminderPlanner.goingText(5, repo.room("OFF")))
        assertEquals("Starting in 15 min", ReminderPlanner.goingText(15, null))
        assertEquals("Starting in 10 min · Off-site", plan(null, "2026-11-08T08:00", setOf(off)).single().text)
        assertEquals("Starting in 10 min · Hyatt lobby, Level 1", ReminderPlanner.text(ReminderKind.GOING, 10, repo.room("HL")))
        assertEquals("Your talk in 10 min · Hyatt lobby, Level 1", ReminderPlanner.text(ReminderKind.MINE, 10, repo.room("HL")))
    }

    @Test
    fun specForPicksMineFirst() {
        val talk = repo.session("1249844")!!
        val other = repo.session(rb220)!!
        assertEquals(ReminderSpec(ReminderKind.MINE, listOf(30, 10)), ReminderPlanner.specFor(talk, lucy, setOf(talk.id), 15))
        assertEquals(ReminderSpec(ReminderKind.GOING, listOf(15)), ReminderPlanner.specFor(other, lucy, setOf(other.id), 15))
        assertNull(ReminderPlanner.specFor(other, lucy, setOf(other.id), 0))
        assertNull(ReminderPlanner.specFor(other, lucy, emptySet(), 10))
        assertEquals(ReminderKind.GOING, ReminderPlanner.specFor(talk, null, setOf(talk.id), 10)!!.kind)
    }

    @Test
    fun aLateGoingAlarmUsesItsOwnOffsets() {
        val start = at("2026-11-11T14:20")
        val going15 = listOf(15)
        // A 15-minute "Going" reminder that fires 8 minutes late still shows (there's no 10-minute one).
        assertEquals(7, ReminderPlanner.minutesLeftToShow(start, 15, at("2026-11-11T14:13"), going15))
        assertEquals(15, ReminderPlanner.minutesLeftToShow(start, 15, at("2026-11-11T14:05"), going15))
        // My talks still drop a 30-minute reminder that runs into the 10-minute one.
        assertNull(ReminderPlanner.minutesLeftToShow(start, 30, at("2026-11-11T14:12")))
        // Never once it has started.
        assertNull(ReminderPlanner.minutesLeftToShow(start, 15, start, going15))
    }

    private fun planArmed(now: String, minutes: Int, armed: Set<String>, going: Set<String> = setOf(rb500), me: String? = null) =
        ReminderPlanner.plan(repo.sessions, repo.rooms, me, at(now), going, minutes, armed)

    @Test
    fun raisingTheLeadTimeTooLateKeepsTheArmedReminder() {
        // RB 5:00 PM starred at 5 min (alarm at 4:55). At 4:52 the setting goes to 15 min: 4:45 is
        // past, so the 4:55 one stays (same key, so the reschedule doesn't cancel it).
        val kept = planArmed("2026-11-11T16:52", 15, setOf("$rb500/5")).single()
        assertEquals("$rb500/5", kept.key)
        assertEquals(at("2026-11-11T16:55"), kept.triggerAt)
        assertEquals(ReminderKind.GOING, kept.kind)
        assertEquals("Starting in 5 min · Regency Ballroom B, Level 4", kept.text)
        // Same for 5 → 10 at 4:52.
        assertEquals(listOf("$rb500/5"), planArmed("2026-11-11T16:52", 10, setOf("$rb500/5")).map { it.key })
        // 10 → 15 at 4:48: the 4:50 one stays.
        assertEquals(listOf("$rb500/10"), planArmed("2026-11-11T16:48", 15, setOf("$rb500/10")).map { it.key })
        // Without it armed (nothing to keep), or once its time has passed, there is nothing.
        assertTrue(planArmed("2026-11-11T16:52", 15, emptySet()).isEmpty())
        assertTrue(planArmed("2026-11-11T16:56", 15, setOf("$rb500/5")).isEmpty())
        // Off means off.
        assertTrue(planArmed("2026-11-11T16:52", 0, setOf("$rb500/5")).isEmpty())
        // Unstarred: nothing either.
        assertTrue(planArmed("2026-11-11T16:52", 15, setOf("$rb500/5"), going = emptySet()).isEmpty())
    }

    @Test
    fun theArmedSetChangesNothingElse() {
        val armed = setOf("$rb500/5", "$rb220/15", "1289660/30", "junk", "$rb500/x")
        // In good time, the new lead time wins and the old key goes (it isn't planned, so it's cancelled).
        assertEquals(listOf("$rb500/15"), planArmed("2026-11-11T12:00", 15, armed).map { it.key })
        // Lowering it close to the start just plans the shorter one (the longer one has fired).
        assertEquals(listOf("$rb500/5"), planArmed("2026-11-11T16:52", 5, setOf("$rb500/15")).map { it.key })
        // My talks keep their 30/10 whatever is armed.
        val mine = planArmed("2026-11-11T16:45", 15, armed + "1289660/5", going = emptySet(), me = lucy)
        assertEquals(listOf("1289660/10"), mine.map { it.key })
        // Planning with the store's keys is idempotent: the plan's own keys plan the same again.
        val first = planArmed("2026-11-11T16:52", 15, setOf("$rb500/5"))
        assertEquals(first, planArmed("2026-11-11T16:52", 15, first.mapTo(HashSet()) { it.key }))
    }

    @Test
    fun theReceiverAcceptsAKeptShorterGoingAlarm() {
        val going15 = ReminderSpec(ReminderKind.GOING, listOf(15))
        assertTrue(ReminderPlanner.accepts(going15, 15))
        assertTrue(ReminderPlanner.accepts(going15, 10))
        assertTrue(ReminderPlanner.accepts(going15, 5))
        assertFalse(ReminderPlanner.accepts(going15, 30))
        assertFalse(ReminderPlanner.accepts(going15, 0))
        // A longer one left over from before the time was lowered is not shown.
        assertFalse(ReminderPlanner.accepts(ReminderSpec(ReminderKind.GOING, listOf(5)), 15))
        // My talks: only 30 and 10.
        val mine = ReminderSpec(ReminderKind.MINE, ReminderPlanner.OFFSETS_MIN)
        assertTrue(ReminderPlanner.accepts(mine, 30))
        assertTrue(ReminderPlanner.accepts(mine, 10))
        assertFalse(ReminderPlanner.accepts(mine, 5))
        // The kept 5-minute alarm firing on time shows "5 min".
        assertEquals(5, ReminderPlanner.minutesLeftToShow(at("2026-11-11T17:00"), 5, at("2026-11-11T16:55"), going15.offsets))
    }

    @Test
    fun requestCodesDifferForEveryLeadTime() {
        for (id in listOf(rb220, "1249844", "m1318417")) {
            val codes = listOf(30, 15, 10, 5).map { ReminderPlanner.requestCode(id, it) }
            assertEquals(4, codes.toSet().size)
        }
    }
}
