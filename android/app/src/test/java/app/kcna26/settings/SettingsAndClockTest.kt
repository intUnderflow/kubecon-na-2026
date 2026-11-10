package app.kcna26.settings

import app.kcna26.InMemoryPrefs
import app.kcna26.time.FakeableClock
import app.kcna26.time.parseFakeNow
import app.kcna26.time.realEpochMillis
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.Instant

class SettingsAndClockTest {

    @Test
    fun speakingAsDefaultsToNoneAndDistinguishesNeverSet() {
        val prefs = InMemoryPrefs()
        val s = SettingsStore(prefs)
        assertNull(s.speakingAs.value)
        assertFalse(s.isSpeakingAsSet)
        s.setSpeakingAs(null)
        assertNull(s.speakingAs.value)
        assertTrue(s.isSpeakingAsSet)
        // Survives a restart.
        assertNull(SettingsStore(prefs).speakingAs.value)
        s.setSpeakingAs("Graham Helton")
        assertEquals("Graham Helton", SettingsStore(prefs).speakingAs.value)
        s.resetSpeakingAs()
        assertNull(s.speakingAs.value)
        assertNull(SettingsStore(prefs).speakingAs.value)
        assertFalse(SettingsStore(prefs).isSpeakingAsSet)
    }

    @Test
    fun directionsFromDefaultsToLive() {
        val prefs = InMemoryPrefs()
        val s = SettingsStore(prefs)
        assertEquals(SettingsStore.FROM_LIVE, s.directionsFrom.value)
        s.setDirectionsFrom("EWT")
        assertEquals("EWT", SettingsStore(prefs).directionsFrom.value)
    }

    @Test
    fun fakeNowPersistsAndTicks() {
        val prefs = InMemoryPrefs()
        val c = FakeableClock(prefs, allowFake = true)
        val target = parseFakeNow("2026-11-11T09:00:00-07:00")
        assertTrue(c.applyFakeNowArg("2026-11-11T09:00:00-07:00"))
        assertTrue(Duration.between(target, c.now()).abs() < Duration.ofSeconds(2))
        // A new clock (app restart) keeps the offset.
        val c2 = FakeableClock(prefs, allowFake = true)
        assertTrue(Duration.between(target, c2.now()).abs() < Duration.ofSeconds(2))
        // Alarm conversion maps back to real time.
        val real = c2.realEpochMillis(target.plusSeconds(600))
        assertTrue(kotlin.math.abs(real - (System.currentTimeMillis() + 600_000)) < 2_000)
        assertTrue(c2.applyFakeNowArg("clear"))
        assertFalse(c2.isFaked)
        assertTrue(Duration.between(Instant.now(), FakeableClock(prefs, true).now()).abs() < Duration.ofSeconds(2))
        // Release builds ignore it.
        val rel = FakeableClock(prefs, allowFake = false)
        assertFalse(rel.applyFakeNowArg("2026-11-11T09:00:00-07:00"))
        assertFalse(rel.isFaked)
        assertFalse(c2.applyFakeNowArg("not a date"))
    }
}
