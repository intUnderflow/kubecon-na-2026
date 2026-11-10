package app.kcna26.going

import app.kcna26.InMemoryPrefs
import app.kcna26.settings.SettingsStore
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * When the contextual POST_NOTIFICATIONS ask fires (first star, a name picked, reminders turned
 * on, or reminders already planned at start) and what the notifications-off hint says.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class NotificationAskTest {

    private fun countTriggers(block: (SettingsStore, GoingStore) -> Unit): Int {
        var n = 0
        runTest(UnconfinedTestDispatcher()) {
            val settings = SettingsStore(InMemoryPrefs())
            val going = GoingStore(InMemoryPrefs())
            val job = NotificationAsk.triggers(settings, going).onEach { n++ }.launchIn(this)
            block(settings, going)
            job.cancel()
        }
        return n
    }

    @Test
    fun nothingHappensUntilTheUserDoesSomething() {
        assertEquals(0, countTriggers { _, _ -> })
    }

    @Test
    fun starringASessionTriggers() {
        assertEquals(1, countTriggers { _, g -> g.toggle("1251049") })
        // Unstarring the last one doesn't.
        assertEquals(1, countTriggers { _, g -> g.toggle("1251049"); g.toggle("1251049") })
    }

    @Test
    fun pickingANameTriggersButNoneDoesNot() {
        assertEquals(1, countTriggers { s, _ -> s.setSpeakingAs("Graham Helton") })
        assertEquals(0, countTriggers { s, _ -> s.setSpeakingAs(null) })
    }

    @Test
    fun turningTheGoingRemindersOnTriggersButOffDoesNot() {
        assertEquals(0, countTriggers { _, g -> g.setRemindMinutes(0) })
        assertEquals(1, countTriggers { _, g -> g.setRemindMinutes(0); g.setRemindMinutes(15) })
    }

    // ------------------------------------------------------------------ at start

    private val repo = app.kcna26.TestData.repo
    private fun at(iso: String) = app.kcna26.time.FixedClock.parse(iso).now()
    private fun toCome(me: String?, now: String, going: Set<String> = emptySet(), minutes: Int = 10) =
        NotificationAsk.remindersToCome(repo.sessions, repo.rooms, me, at(now), going, minutes)

    @Test
    fun atStartTheAskIsDueOnlyWhenRemindersArePlanned() {
        // The default speaker (Lucy Sweet) has talks to come: the ask is due at start, as before.
        assertTrue(toCome(SettingsStore.DEFAULT_SPEAKER, "2026-11-08T08:00"))
        // None and nothing starred (the public default): nothing to deliver, so no ask at launch.
        assertFalse(toCome(null, "2026-11-08T08:00"))
        // A star counts while its reminder is on and still to come.
        assertTrue(toCome(null, "2026-11-08T08:00", setOf("1251049")))
        assertFalse(toCome(null, "2026-11-08T08:00", setOf("1251049"), minutes = 0))
        assertFalse(toCome(null, "2026-11-11T14:15", setOf("1251049"))) // its 2:10 reminder is past
        // After Lucy's last talk (Wed 5:00 PM) there is nothing left for her.
        assertFalse(toCome("Lucy Sweet", "2026-11-11T17:30"))
    }

    // ------------------------------------------------------------------ the hint

    private fun block(
        permission: Boolean = true,
        appOn: Boolean = true,
        channelOn: Boolean = true,
        needsRuntimeAsk: Boolean = true,
        asked: Boolean = true,
        asking: Boolean = false,
    ) = NotificationAsk.blockOf(permission, appOn, channelOn, needsRuntimeAsk, asked, asking)

    @Test
    fun theHintStatesFollowThePermissionAndTheChannels() {
        assertEquals(NotificationAsk.Block.NONE, block())
        // Refused: the app is off.
        assertEquals(NotificationAsk.Block.APP, block(permission = false))
        // Not asked yet on Android 13+: nothing to say until the contextual ask.
        assertEquals(NotificationAsk.Block.NONE, block(permission = false, asked = false))
        // While the system dialog is up: nothing either (no "off" hint behind the dialog).
        assertEquals(NotificationAsk.Block.NONE, block(permission = false, asking = true))
        // Notifications switched off for the app (any Android version).
        assertEquals(NotificationAsk.Block.APP, block(appOn = false, needsRuntimeAsk = false, asked = false))
        // Only the channel is off: a deliberate choice, told apart from the app being off.
        assertEquals(NotificationAsk.Block.CHANNEL, block(channelOn = false))
        assertEquals(NotificationAsk.Block.APP, block(appOn = false, channelOn = false))
    }

    @Test
    fun askingIsTrackedUntilTheDialogAnswers() {
        assertFalse(NotificationAsk.asking.value)
        NotificationAsk.requestStarted()
        assertTrue(NotificationAsk.asking.value)
        NotificationAsk.requestFinished()
        assertFalse(NotificationAsk.asking.value)
    }

    @Test
    fun theCurrentValuesAtStartDoNotTrigger() {
        var n = 0
        runTest(UnconfinedTestDispatcher()) {
            val settings = SettingsStore(InMemoryPrefs()).apply { setSpeakingAs("Lucy Sweet") }
            val going = GoingStore(InMemoryPrefs()).apply { toggle("1251049"); setRemindMinutes(5) }
            val job = NotificationAsk.triggers(settings, going).onEach { n++ }.launchIn(this)
            job.cancel()
        }
        assertEquals(0, n)
    }
}
