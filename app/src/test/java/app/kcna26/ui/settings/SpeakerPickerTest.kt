package app.kcna26.ui.settings

import app.kcna26.InMemoryPrefs
import app.kcna26.TestData
import app.kcna26.schedule.ScheduleIndex
import app.kcna26.settings.SettingsStore
import app.kcna26.time.FixedClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SpeakerPickerTest {
    private val repo = TestData.repo
    private val options = SpeakerPicker.options(repo)

    @Test
    fun everySpeakerIsAnOptionWithASummary() {
        assertEquals(repo.allSpeakers, options.map { it.name })
        assertEquals("3 sessions · Wed", options.single { it.name == "Lucy Sweet" }.summary)
        assertEquals("2 sessions · Thu", options.single { it.name == "Decheng Dai" }.summary)
        // Co-located speakers are in the picker too.
        assertEquals("3 sessions · Mon", options.single { it.name == "Katie Lamkin-Fulsher" }.summary)
        assertEquals("1 session · Mon", options.single { it.name == "Jiazhou Gao" }.summary)
        assertTrue(SpeakerPicker.filter(options, SpeakerPicker.terms("jiazhou"), null).any { it.name == "Jiazhou Gao" })
    }

    @Test
    fun searchIgnoresCaseAndAccentsAndPinsTheDefault() {
        val all = SpeakerPicker.filter(options, emptyList(), "Lucy Sweet")
        assertEquals(options.size - 1, all.size)
        assertFalse(all.any { it.name == "Lucy Sweet" })
        assertEquals(listOf("Lucy Sweet"), SpeakerPicker.filter(options, SpeakerPicker.terms("lucy swe"), "Lucy Sweet").map { it.name })
        assertTrue(SpeakerPicker.filter(options, SpeakerPicker.terms("KREPINSKY"), null).any { it.name == "Filip Křepinský" })
        assertTrue(SpeakerPicker.filter(options, SpeakerPicker.terms("o'leary"), null).any { it.name == "Justin O’Leary" })
        assertTrue(SpeakerPicker.filter(options, SpeakerPicker.terms("zzzz"), null).isEmpty())
    }

    @Test
    fun choosingASpeakerMovesEverythingMine() {
        val settings = SettingsStore(InMemoryPrefs())
        val idx = ScheduleIndex.of(repo)
        val now = FixedClock.parse("2026-11-10T09:00:00-07:00").now()
        assertNull(settings.speakingAs.value) // default: None
        settings.setSpeakingAs("Lucy Sweet")
        assertEquals("1363905", idx.banner("wed", now, settings.speakingAs.value)!!.next.id)

        settings.setSpeakingAs("Decheng Dai")
        assertNull(idx.banner("wed", now, settings.speakingAs.value))
        assertEquals("1250150", idx.banner("thu", now, settings.speakingAs.value)!!.next.id)
        assertEquals(listOf("thu"), idx.dayTabs(now, settings.speakingAs.value).filter { it.hasMine }.map { it.key })

        settings.setSpeakingAs(null)
        assertNull(settings.speakingAs.value)
        assertTrue(idx.dayTabs(now, settings.speakingAs.value).none { it.hasMine })
        assertTrue(repo.sessions.none { idx.isMine(it, settings.speakingAs.value) })
    }
}
