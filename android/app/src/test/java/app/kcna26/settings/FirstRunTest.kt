package app.kcna26.settings

import app.kcna26.InMemoryPrefs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The first-run "Speaking at KubeCon? Pick your name" state. */
class FirstRunTest {

    @Test
    fun freshInstallIsNoneWithThePickerPending() {
        val s = SettingsStore(InMemoryPrefs())
        assertNull(s.speakingAs.value)
        assertTrue(s.firstRunPending.value)
        assertFalse(s.isSpeakingAsSet)
    }

    @Test
    fun pickingSetsTheSpeakerAndTheFlag() {
        val prefs = InMemoryPrefs()
        val s = SettingsStore(prefs)
        s.finishFirstRun("Lucy Sweet")
        assertEquals("Lucy Sweet", s.speakingAs.value)
        assertFalse(s.firstRunPending.value)
        // Survives a restart (and fold/unfold, which recreates the activity but not the store).
        val again = SettingsStore(prefs)
        assertEquals("Lucy Sweet", again.speakingAs.value)
        assertFalse(again.firstRunPending.value)
    }

    @Test
    fun skippingKeepsNoneAndNeverAsksAgain() {
        val prefs = InMemoryPrefs()
        val s = SettingsStore(prefs)
        s.finishFirstRun(null)
        assertNull(s.speakingAs.value)
        assertFalse(s.firstRunPending.value)
        assertFalse(s.isSpeakingAsSet)
        assertFalse(SettingsStore(prefs).firstRunPending.value)
        assertNull(SettingsStore(prefs).speakingAs.value)
    }

    @Test
    fun swipingTheSheetAwayOnlyHidesItUntilTheNextStart() {
        val prefs = InMemoryPrefs()
        val s = SettingsStore(prefs)
        s.dismissFirstRunForNow()
        assertFalse(s.firstRunPending.value) // hidden for this process (fold/unfold keeps the store)
        assertNull(s.speakingAs.value)
        assertFalse(s.isSpeakingAsSet)
        assertTrue(SettingsStore(prefs).firstRunPending.value) // asks again on the next cold start
    }

    @Test
    fun anExistingExplicitChoiceIsUntouched() {
        val named = InMemoryPrefs().also { SettingsStore(it).setSpeakingAs("Graham Helton") }
        SettingsStore(named).let {
            assertEquals("Graham Helton", it.speakingAs.value)
            assertFalse(it.firstRunPending.value)
        }
        val none = InMemoryPrefs().also { SettingsStore(it).setSpeakingAs(null) }
        SettingsStore(none).let {
            assertNull(it.speakingAs.value)
            assertTrue(it.isSpeakingAsSet)
            assertFalse(it.firstRunPending.value)
        }
    }

    @Test
    fun choosingInSettingsAlsoEndsTheFirstRun() {
        val s = SettingsStore(InMemoryPrefs())
        s.setSpeakingAs("Decheng Dai")
        assertFalse(s.firstRunPending.value)
    }

    @Test
    fun speakingAsEmitsOnlyWhenAPickChangesIt() {
        // KcnaApp reschedules reminders on every speakingAs change after the first value.
        val s = SettingsStore(InMemoryPrefs())
        val before = s.speakingAs.value
        s.finishFirstRun(null)
        assertEquals(before, s.speakingAs.value) // Skip: no change, nothing to reschedule
        val s2 = SettingsStore(InMemoryPrefs())
        s2.finishFirstRun("Lucy Sweet")
        assertEquals("Lucy Sweet", s2.speakingAs.value) // a change, so reminders are rescheduled
    }
}
