package app.kcna26.reminders

import app.kcna26.InMemoryPrefs
import app.kcna26.TestData
import app.kcna26.time.FixedClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class ReminderPlannerTest {

    private val repo = TestData.repo
    private val lucy = "Lucy Sweet"

    private fun plan(me: String?, clock: FixedClock) = ReminderPlanner.plan(repo.sessions, repo.rooms, me, clock.now())

    private fun at(iso: String): Instant = FixedClock.parse(iso).now()

    @Test
    fun lucysThreeWednesdayTalksGiveSixRemindersOnTuesday() {
        val reminders = plan(lucy, TestData.clockAt("2026-11-10T12:00:00-07:00"))
        assertEquals(6, reminders.size)
        assertEquals(
            listOf(
                Triple("1363905", at("2026-11-11T09:15:00-07:00"), 30),
                Triple("1363905", at("2026-11-11T09:35:00-07:00"), 10),
                Triple("1249844", at("2026-11-11T13:50:00-07:00"), 30),
                Triple("1249844", at("2026-11-11T14:10:00-07:00"), 10),
                Triple("1289660", at("2026-11-11T16:30:00-07:00"), 30),
                Triple("1289660", at("2026-11-11T16:50:00-07:00"), 10),
            ),
            reminders.map { Triple(it.sessionId, it.triggerAt, it.minutesBefore) },
        )
        assertEquals(
            listOf(
                "Your talk in 30 min · Hall DE, Level 1",
                "Your talk in 10 min · Hall DE, Level 1",
                "Your talk in 30 min · Grand Ballroom GI, Level 1",
                "Your talk in 10 min · Grand Ballroom GI, Level 1",
                "Your talk in 30 min · 251 A–C, Level 2",
                "Your talk in 10 min · 251 A–C, Level 2",
            ),
            reminders.map { it.text },
        )
        assertEquals(
            listOf(
                "A Tribute to Open Source",
                "A Tribute to Open Source",
                "Kubernetes The Hard Way - Live",
                "Kubernetes The Hard Way - Live",
                "The Future of Kubernetes Eviction and Node Lifecycle",
                "The Future of Kubernetes Eviction and Node Lifecycle",
            ),
            reminders.map { it.title },
        )
    }

    @Test
    fun triggerTimesAreStartMinusOffset() {
        for (r in plan(lucy, TestData.clockAt("2026-11-08T13:00"))) {
            val s = repo.session(r.sessionId)!!
            assertEquals(s.start.minusSeconds(r.minutesBefore * 60L), r.triggerAt)
        }
    }

    @Test
    fun theExampleTextMatchesExactly() {
        val gi10 = plan(lucy, TestData.clockAt("2026-11-10T12:00")).single { it.sessionId == "1249844" && it.minutesBefore == 10 }
        assertEquals("Your talk in 10 min · Grand Ballroom GI, Level 1", gi10.text)
        assertEquals("1249844/10", gi10.key)
    }

    @Test
    fun noneGivesNoReminders() {
        assertEquals(0, plan(null, TestData.clockAt("2026-11-10T12:00")).size)
        assertEquals(0, plan(null, TestData.clockAt("2026-11-08T08:00")).size)
    }

    @Test
    fun unknownSpeakerGivesNoReminders() {
        assertEquals(0, plan("Nobody At All", TestData.clockAt("2026-11-10T12:00")).size)
    }

    @Test
    fun followsTheSpeakingAsSetting() {
        // Ryan Hallisey: two talks in CC plus the 5:00 PM one shared with Lucy.
        val ryan = plan("Ryan Hallisey", TestData.clockAt("2026-11-10T12:00"))
        assertEquals(6, ryan.size)
        assertEquals(setOf("1334847", "1334856", "1289660"), ryan.map { it.sessionId }.toSet())
        assertTrue(ryan.none { it.sessionId == "1249844" })
    }

    @Test
    fun pastRemindersAreDropped() {
        // 9:20: the 9:45 keynote's 30-min reminder (9:15) is gone, its 10-min one (9:35) stays.
        val morning = plan(lucy, TestData.clockAt("2026-11-11T09:20"))
        assertEquals(5, morning.size)
        assertEquals("1363905/10", morning.first().key)

        // 14:15: both 2:20 PM reminders are past; only the 5:00 PM talk is left.
        val afternoon = plan(lucy, TestData.clockAt("2026-11-11T14:15"))
        assertEquals(listOf("1289660/30", "1289660/10"), afternoon.map { it.key })

        // 16:55: the last 10-min reminder fired at 16:50.
        assertEquals(0, plan(lucy, TestData.clockAt("2026-11-11T16:55")).size)
        assertEquals(0, plan(lucy, TestData.clockAt("2026-11-12T09:00")).size)
    }

    @Test
    fun aReminderExactlyNowIsNotFuture() {
        val r = plan(lucy, TestData.clockAt("2026-11-11T16:30"))
        assertEquals(listOf("1289660/10"), r.map { it.key })
        val justBefore = plan(lucy, FixedClock(at("2026-11-11T16:30").minusMillis(1)))
        assertEquals(listOf("1289660/30", "1289660/10"), justBefore.map { it.key })
    }

    @Test
    fun planIsSortedByTriggerTime() {
        val r = plan("Ryan Hallisey", TestData.clockAt("2026-11-08T13:00"))
        assertEquals(r.sortedBy { it.triggerAt }, r)
    }

    @Test
    fun textUsesRoomNameAndLevelFromRooms() {
        assertEquals("Your talk in 10 min · 251 A–C, Level 2", ReminderPlanner.text(10, repo.room("251AC")))
        assertEquals("Your talk in 30 min · Hyatt lobby, Level 1", ReminderPlanner.text(30, repo.room("HL")))
        for (room in repo.rooms.values) {
            val t = ReminderPlanner.text(10, room)
            if (room.level != null) {
                assertEquals("Your talk in 10 min · ${room.name}, Level ${room.level}", t)
            }
        }
    }

    @Test
    fun textWithoutLevelOrRoom() {
        assertEquals("Your talk in 10 min · Off-site", ReminderPlanner.text(10, repo.room("OFF")))
        assertEquals("Your talk in 10 min", ReminderPlanner.text(10, null))
        // A session of mine in a room code the data doesn't know still plans, with the short text.
        val s = repo.session("1249844")!!.copy(room = "NOPE")
        val r = ReminderPlanner.plan(listOf(s), repo.rooms, lucy, at("2026-11-10T12:00"))
        assertEquals(listOf("Your talk in 30 min", "Your talk in 10 min"), r.map { it.text })
        val off = ReminderPlanner.plan(listOf(s.copy(room = "OFF")), repo.rooms, lucy, at("2026-11-10T12:00"))
        assertEquals("Your talk in 10 min · Off-site", off.last().text)
    }

    @Test
    fun firingOnTimeShowsThePlannedMinutes() {
        val start = at("2026-11-11T17:00")
        assertEquals(30, ReminderPlanner.minutesLeftToShow(start, 30, at("2026-11-11T16:30")))
        assertEquals(10, ReminderPlanner.minutesLeftToShow(start, 10, at("2026-11-11T16:50")))
        // An exact alarm delivered a few hundred ms late still says 10.
        assertEquals(10, ReminderPlanner.minutesLeftToShow(start, 10, at("2026-11-11T16:50").plusMillis(400)))
    }

    @Test
    fun aLateAlarmShowsTheRealMinutesLeft() {
        val start = at("2026-11-11T17:00")
        assertEquals(12, ReminderPlanner.minutesLeftToShow(start, 30, at("2026-11-11T16:48")))
        assertEquals(3, ReminderPlanner.minutesLeftToShow(start, 10, at("2026-11-11T16:57")))
        assertEquals(1, ReminderPlanner.minutesLeftToShow(start, 10, at("2026-11-11T16:59:59")))
    }

    @Test
    fun staleRemindersAreSkipped() {
        val start = at("2026-11-11T17:00")
        // The session has started (or is over): never notify, e.g. after a boot.
        assertNull(ReminderPlanner.minutesLeftToShow(start, 10, start))
        assertNull(ReminderPlanner.minutesLeftToShow(start, 10, at("2026-11-11T17:05")))
        assertNull(ReminderPlanner.minutesLeftToShow(start, 30, at("2026-11-12T09:00")))
        // A 30-min reminder so late that the 10-min one is due anyway is dropped (no double alert).
        assertNull(ReminderPlanner.minutesLeftToShow(start, 30, at("2026-11-11T16:50")))
        assertNull(ReminderPlanner.minutesLeftToShow(start, 30, at("2026-11-11T16:55")))
    }

    @Test
    fun keysRoundTrip() {
        assertEquals("m1318417" to 30, ReminderPlanner.parseKey(ReminderPlanner.key("m1318417", 30)))
        assertEquals("1289660" to 10, ReminderPlanner.parseKey("1289660/10"))
        assertNull(ReminderPlanner.parseKey(""))
        assertNull(ReminderPlanner.parseKey("1289660"))
        assertNull(ReminderPlanner.parseKey("1289660/"))
        assertNull(ReminderPlanner.parseKey("/10"))
        assertNull(ReminderPlanner.parseKey("1289660/x"))
    }

    @Test
    fun requestCodesDifferPerOffset() {
        for (s in repo.sessions) {
            assertNotEquals(ReminderPlanner.requestCode(s.id, 30), ReminderPlanner.requestCode(s.id, 10))
        }
        val lucysCodes = plan(lucy, TestData.clockAt("2026-11-10T12:00")).map { ReminderPlanner.requestCode(it.sessionId, it.minutesBefore) }
        assertEquals(6, lucysCodes.toSet().size)
        assertEquals(ReminderPlanner.requestCode("1249844", 10), ReminderPlanner.requestCode("1249844", 10))
    }

    @Test
    fun storeTracksArmedKeys() {
        val store = ReminderStore(InMemoryPrefs())
        assertEquals(emptySet<String>(), store.armed())
        store.setArmed(setOf("1249844/30", "1249844/10"))
        assertEquals(setOf("1249844/30", "1249844/10"), store.armed())
        // Switching to None: everything armed is stale and the store empties.
        val next = plan(null, TestData.clockAt("2026-11-10T12:00")).map { it.key }.toSet()
        assertEquals(setOf("1249844/30", "1249844/10"), store.armed() - next)
        store.setArmed(next)
        assertEquals(emptySet<String>(), store.armed())
    }
}
