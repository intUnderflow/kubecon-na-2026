package app.kcna26.time

import app.kcna26.TestData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class TimeFormatTest {
    private val repo = TestData.repo

    @Test
    fun clockFormats() {
        assertEquals("12:00", TimeFormat.hm(0))
        assertEquals("AM", TimeFormat.ap(0))
        assertEquals("12:05 PM", TimeFormat.hma(12 * 60 + 5))
        assertEquals("9:30 AM", TimeFormat.hma(9 * 60 + 30))
        assertEquals("1:00 AM", TimeFormat.hma(1440 + 60))
    }

    @Test
    fun rangesAndDurations() {
        val plt = repo.session("1289955")!! // Mon 9:30–9:35 AM
        assertEquals("9:30–9:35 AM", TimeFormat.range(plt))
        assertEquals("5 min", TimeFormat.dur(plt))
        val open = repo.session("m1318417")!!
        assertEquals("from 5:30 PM", TimeFormat.range(open))
        assertNull(TimeFormat.dur(open))
        val est = repo.session("m1290687")!! // 10:15–11:00, estimate
        assertEquals("~45 min", TimeFormat.dur(est))
        assertEquals("1h", TimeFormat.durationLabel(60))
        assertEquals("1h 30m", TimeFormat.durationLabel(90))
        val hack = repo.session("1344383")!! // 9 AM – 6 PM
        assertEquals("9:00 AM–6:00 PM", TimeFormat.range(hack))
        assertEquals("9h", TimeFormat.dur(hack))
    }

    @Test
    fun fixedAndFakeTimeParsing() {
        val c = TestData.clockAt("2026-11-11T09:00:00-07:00")
        assertEquals(Instant.parse("2026-11-11T16:00:00Z"), c.now())
        assertEquals(Instant.parse("2026-11-11T16:00:00Z"), parseFakeNow("2026-11-11T09:00"))
        assertEquals(Instant.parse("2026-11-11T16:00:00Z"), parseFakeNow("2026-11-11T16:00:00Z"))
        assertEquals(9 * 60, TimeFormat.minuteOfDay(c.now()))
        assertEquals(15, TimeFormat.minutesBetween(c.now(), Instant.parse("2026-11-11T16:15:59Z")))
    }
}
