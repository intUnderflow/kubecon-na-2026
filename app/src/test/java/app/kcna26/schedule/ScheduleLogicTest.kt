package app.kcna26.schedule

import app.kcna26.TestData
import app.kcna26.time.FixedClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class ScheduleLogicTest {
    private val repo = TestData.repo
    private val days = repo.days

    private fun at(iso: String): Instant = FixedClock.parse(iso).now()
    private fun s(id: String) = repo.session(id)!!

    // ------------------------------------------------------------ finished / live

    @Test
    fun finishedUsesEndAndIsExclusiveAtTheEndMinute() {
        val eviction = s("1289660") // Wed 5:00–5:30 PM, 251 A–C
        assertFalse(ScheduleLogic.isFinished(eviction, at("2026-11-11T17:29:59-07:00")))
        assertTrue(ScheduleLogic.isFinished(eviction, at("2026-11-11T17:30:00-07:00")))
        assertTrue(ScheduleLogic.isFinished(eviction, at("2026-11-11T18:00:00-07:00")))
        assertFalse(ScheduleLogic.isFinished(eviction, at("2026-11-11T09:00:00-07:00")))
    }

    @Test
    fun nullEndCountsAsNinetyMinutes() {
        val reception = s("m1318417") // Sun 5:30 PM, no end
        assertNull(reception.end)
        assertFalse(ScheduleLogic.isFinished(reception, at("2026-11-08T18:59:00-07:00")))
        assertTrue(ScheduleLogic.isLive(reception, at("2026-11-08T18:59:00-07:00")))
        assertTrue(ScheduleLogic.isFinished(reception, at("2026-11-08T19:00:00-07:00")))
        assertFalse(ScheduleLogic.isLive(reception, at("2026-11-08T19:00:00-07:00")))
        assertEquals(60, ScheduleLogic.minutesLeft(reception, at("2026-11-08T18:00:00-07:00")))
    }

    @Test
    fun liveWindowAndMinutesLeft() {
        val eviction = s("1289660")
        assertFalse(ScheduleLogic.isLive(eviction, at("2026-11-11T16:59:59-07:00")))
        assertTrue(ScheduleLogic.isLive(eviction, at("2026-11-11T17:00:00-07:00")))
        assertEquals(30, ScheduleLogic.minutesLeft(eviction, at("2026-11-11T17:00:00-07:00")))
        assertEquals(20, ScheduleLogic.minutesLeft(eviction, at("2026-11-11T17:10:00-07:00")))
        // Seconds are dropped like the web's minute arithmetic.
        assertEquals(20, ScheduleLogic.minutesLeft(eviction, at("2026-11-11T17:10:59-07:00")))
        assertEquals(1, ScheduleLogic.minutesLeft(eviction, at("2026-11-11T17:29:30-07:00")))
        assertEquals("Live · 20 min left", ScheduleLogic.liveLabel(eviction, at("2026-11-11T17:10:00-07:00"), long = false))
        assertEquals("On now", ScheduleLogic.liveLabel(eviction, at("2026-11-11T17:10:00-07:00"), long = true))
    }

    @Test
    fun liveProgressIsMinutePrecisePercent() {
        val eviction = s("1289660") // 30 min
        assertEquals(0f, ScheduleLogic.liveProgress(eviction, at("2026-11-11T17:00:00-07:00")), 0.001f)
        assertEquals(0.5f, ScheduleLogic.liveProgress(eviction, at("2026-11-11T17:15:40-07:00")), 0.001f)
        assertEquals(0.33f, ScheduleLogic.liveProgress(eviction, at("2026-11-11T17:10:00-07:00")), 0.001f)
    }

    // ------------------------------------------------------------ days

    private fun keys(iso: String) = ScheduleLogic.visibleDays(days, at(iso)).map { it.key }

    @Test
    fun visibleDaysHidePastDays() {
        assertEquals(listOf("sun", "mon", "tue", "wed", "thu"), keys("2026-11-07T12:00:00-07:00")) // before: all
        assertEquals(listOf("sun", "mon", "tue", "wed", "thu"), keys("2026-11-08T08:00:00-07:00"))
        assertEquals(listOf("mon", "tue", "wed", "thu"), keys("2026-11-09T00:00:00-07:00"))
        assertEquals(listOf("tue", "wed", "thu"), keys("2026-11-10T23:59:00-07:00"))
        assertEquals(listOf("wed", "thu"), keys("2026-11-11T09:00:00-07:00"))
        assertEquals(listOf("thu"), keys("2026-11-12T20:00:00-07:00"))
        assertEquals(listOf("sun", "mon", "tue", "wed", "thu"), keys("2026-11-13T09:00:00-07:00")) // after: web shows all
    }

    @Test
    fun visibleDaysUseDenverTime() {
        // 2026-11-11T05:30Z is still Tue Nov 10, 10:30 PM in Denver.
        assertEquals(listOf("tue", "wed", "thu"), keys("2026-11-11T05:30:00Z"))
        assertEquals("tue", ScheduleLogic.todayKey(days, at("2026-11-11T05:30:00Z")))
    }

    @Test
    fun todayAndDefaultDay() {
        assertEquals("sun", ScheduleLogic.todayKey(days, at("2026-11-08T10:00:00-07:00")))
        assertEquals("wed", ScheduleLogic.todayKey(days, at("2026-11-11T10:00:00-07:00")))
        assertNull(ScheduleLogic.todayKey(days, at("2026-11-07T10:00:00-07:00")))
        assertNull(ScheduleLogic.todayKey(days, at("2026-11-13T10:00:00-07:00")))
        assertEquals("wed", ScheduleLogic.defaultDayKey(days, at("2026-11-11T10:00:00-07:00")))
        assertEquals("sun", ScheduleLogic.defaultDayKey(days, at("2026-11-07T10:00:00-07:00")))
        assertEquals("sun", ScheduleLogic.defaultDayKey(days, at("2026-11-13T10:00:00-07:00")))
    }

    @Test
    fun resolveDayKeepsAVisibleSelectionAndDropsAStaleOne() {
        val tue = at("2026-11-10T10:00:00-07:00")
        assertEquals("tue", ScheduleLogic.resolveDayKey(days, tue, null))
        assertEquals("thu", ScheduleLogic.resolveDayKey(days, tue, "thu"))
        assertEquals("tue", ScheduleLogic.resolveDayKey(days, tue, "mon")) // past day: back to today
        assertEquals("tue", ScheduleLogic.resolveDayKey(days, tue, "nope"))
        // Selected Monday, then midnight passes: the view moves on to the new today.
        assertEquals("mon", ScheduleLogic.resolveDayKey(days, at("2026-11-09T23:59:00-07:00"), "mon"))
        assertEquals("tue", ScheduleLogic.resolveDayKey(days, at("2026-11-10T00:00:00-07:00"), "mon"))
    }

    // ------------------------------------------------------------ labels

    @Test
    fun slotKeysAreHalfHours() {
        assertEquals(600, ScheduleLogic.slotKey(600))
        assertEquals(600, ScheduleLogic.slotKey(615))
        assertEquals(600, ScheduleLogic.slotKey(629))
        assertEquals(630, ScheduleLogic.slotKey(630))
        assertEquals(0, ScheduleLogic.slotKey(29))
    }

    @Test
    fun countdownLabels() {
        assertEquals("In 0 min", ScheduleLogic.countdownLabel(0))
        assertEquals("In 25 min", ScheduleLogic.countdownLabel(25))
        assertEquals("In 59 min", ScheduleLogic.countdownLabel(59))
        assertEquals("In 1h", ScheduleLogic.countdownLabel(60))
        assertEquals("In 1h 45m", ScheduleLogic.countdownLabel(105))
        assertEquals("In 2h 5m", ScheduleLogic.countdownLabel(125))
    }

    @Test
    fun clockLabel() {
        assertEquals("9:05 AM MST", ScheduleLogic.clockLabel(days, at("2026-11-11T09:05:00-07:00")))
        assertEquals("Times in MST", ScheduleLogic.clockLabel(days, at("2026-11-07T09:05:00-07:00")))
        assertEquals("Times in MST", ScheduleLogic.clockLabel(days, at("2026-11-13T09:05:00-07:00")))
    }

    @Test
    fun spanLabelLikeRange() {
        assertEquals("9:00–10:30 AM", ScheduleLogic.spanLabel(at("2026-11-11T09:00:00-07:00"), at("2026-11-11T10:30:00-07:00")))
        assertEquals("11:30 AM–1:00 PM", ScheduleLogic.spanLabel(at("2026-11-11T11:30:00-07:00"), at("2026-11-11T13:00:00-07:00")))
    }

    @Test
    fun breakTitleDropsTheEmoji() {
        assertEquals("Coffee Break", ScheduleLogic.breakTitle("☕ Coffee Break"))
        assertEquals("Lunch (on your own)", ScheduleLogic.breakTitle("🍲 Lunch (on your own)"))
        assertEquals("Break: donuts + cinnamon rolls", ScheduleLogic.breakTitle("Break: donuts + cinnamon rolls"))
    }
}
