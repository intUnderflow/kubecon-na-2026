package app.kcna26.going

import app.kcna26.InMemoryPrefs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GoingStoreTest {

    @Test
    fun startsEmptyWithTenMinuteReminders() {
        val g = GoingStore(InMemoryPrefs())
        assertEquals(emptySet<String>(), g.ids.value)
        assertEquals(10, g.remindMinutes.value)
        assertEquals(GoingStore.DEFAULT_REMIND_MINUTES, g.remindMinutes.value)
        assertEquals(listOf(0, 5, 10, 15), GoingStore.REMIND_OPTIONS)
    }

    @Test
    fun toggleStarsAndUnstarsAndUpdatesTheFlowAtOnce() {
        val g = GoingStore(InMemoryPrefs())
        assertTrue(g.toggle("1251049"))
        assertTrue(g.isGoing("1251049"))
        assertEquals(setOf("1251049"), g.ids.value)
        assertTrue(g.toggle("m1318417"))
        assertEquals(setOf("1251049", "m1318417"), g.ids.value)
        assertFalse(g.toggle("1251049"))
        assertFalse(g.isGoing("1251049"))
        assertEquals(setOf("m1318417"), g.ids.value)
    }

    @Test
    fun setGoingIsIdempotent() {
        val prefs = InMemoryPrefs()
        val g = GoingStore(prefs)
        g.setGoing("1251049", true)
        g.setGoing("1251049", true)
        assertEquals(setOf("1251049"), g.ids.value)
        g.setGoing("nope", false)
        assertEquals(setOf("1251049"), g.ids.value)
        g.setGoing("1251049", false)
        assertEquals(emptySet<String>(), g.ids.value)
        assertEquals(emptySet<String>(), GoingStore(prefs).ids.value)
    }

    @Test
    fun starsAndTheReminderTimeSurviveARestart() {
        val prefs = InMemoryPrefs()
        val g = GoingStore(prefs)
        g.toggle("1251049")
        g.toggle("1251218")
        g.setRemindMinutes(15)
        val again = GoingStore(prefs)
        assertEquals(setOf("1251049", "1251218"), again.ids.value)
        assertEquals(15, again.remindMinutes.value)
        g.setRemindMinutes(GoingStore.REMIND_OFF)
        assertEquals(0, GoingStore(prefs).remindMinutes.value)
    }

    @Test
    fun unknownIdsAreKeptSoTheyComeBackWithTheData() {
        val prefs = InMemoryPrefs()
        val g = GoingStore(prefs)
        g.toggle("gone-from-the-data")
        g.toggle("1251049")
        assertEquals(setOf("gone-from-the-data", "1251049"), GoingStore(prefs).ids.value)
    }

    @Test
    fun onlyTheOfferedReminderTimesAreAccepted() {
        val prefs = InMemoryPrefs()
        val g = GoingStore(prefs)
        g.setRemindMinutes(7)
        assertEquals(10, g.remindMinutes.value)
        g.setRemindMinutes(5)
        assertEquals(5, g.remindMinutes.value)
        // A bad stored value falls back to the default.
        prefs.edit().putInt("remindMinutes", 42).apply()
        assertEquals(10, GoingStore(prefs).remindMinutes.value)
    }

    @Test
    fun theStoredSetIsACopy() {
        val prefs = InMemoryPrefs()
        val g = GoingStore(prefs)
        g.toggle("a")
        val stored = prefs.getStringSet("ids", null)!!
        g.toggle("b")
        assertEquals(setOf("a"), stored.toSet())
        assertEquals(setOf("a", "b"), prefs.getStringSet("ids", null)!!.toSet())
    }
}
