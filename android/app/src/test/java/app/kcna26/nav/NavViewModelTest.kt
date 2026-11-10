package app.kcna26.nav

import androidx.lifecycle.SavedStateHandle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NavViewModelTest {
    @Test
    fun stackAndSessionSurviveRecreation() {
        val handle = SavedStateHandle()
        val nav = NavViewModel(handle)
        assertEquals(listOf(Screen.Schedule), nav.stack.value)
        assertFalse(nav.pop())
        nav.openSession("1203350")
        nav.openDirections("1203350")
        nav.openDirections("1203350") // no duplicate
        assertEquals(listOf(Screen.Schedule, Screen.Directions("1203350")), nav.stack.value)

        // A recreated activity gets a new ViewModel over the same saved state.
        val again = NavViewModel(handle)
        assertEquals(nav.stack.value, again.stack.value)
        assertEquals("1203350", again.openSessionId.value)

        again.pop()
        assertEquals(listOf(Screen.Schedule), again.stack.value)
        assertEquals("1203350", again.openSessionId.value)
        again.closeSession()
        assertNull(again.openSessionId.value)

        again.openSettings()
        again.openDirectionsFromNotification("m1290687")
        assertEquals(listOf(Screen.Schedule, Screen.Directions("m1290687")), again.stack.value)
        assertEquals("m1290687", again.openSessionId.value)
        assertEquals(Screen.Directions("m1290687"), Screen.decode(Screen.Directions("m1290687").key))
    }

    @Test
    fun staleUnconferenceRouteFromAnOlderInstallFallsBackToSchedule() {
        // The Unconference screen ("unconf") was removed. An older install's saved state with it open,
        // on top or under Directions, restores without it.
        assertNull(Screen.decode("unconf"))
        val onTop = SavedStateHandle(mapOf("nav.stack" to arrayListOf("schedule", "unconf"), "nav.session" to "m1318474"))
        val nav = NavViewModel(onTop)
        assertEquals(listOf(Screen.Schedule), nav.stack.value)
        assertEquals(Screen.Schedule, nav.current)
        assertFalse(nav.pop())
        assertEquals("m1318474", nav.openSessionId.value)
        // The cleaned stack is what gets saved next time.
        assertEquals(arrayListOf("schedule"), onTop.get<ArrayList<String>>("nav.stack"))
        assertEquals(listOf(Screen.Schedule), NavViewModel(onTop).stack.value)

        val under = SavedStateHandle(mapOf("nav.stack" to arrayListOf("schedule", "unconf", "directions:m1318474", "bogus")))
        val nav2 = NavViewModel(under)
        assertEquals(listOf(Screen.Schedule, Screen.Directions("m1318474")), nav2.stack.value)
        assertTrue(nav2.pop())
        assertEquals(listOf(Screen.Schedule), nav2.stack.value)

        // Anything unexpected under the key counts as no saved stack.
        assertEquals(listOf(Screen.Schedule), NavViewModel(SavedStateHandle(mapOf("nav.stack" to "unconf"))).stack.value)
    }
}
