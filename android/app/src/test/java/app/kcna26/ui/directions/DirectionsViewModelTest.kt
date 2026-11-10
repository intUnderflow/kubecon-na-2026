package app.kcna26.ui.directions

import android.hardware.Sensor
import app.kcna26.InMemoryPrefs
import app.kcna26.TestData
import app.kcna26.geo.Geo
import app.kcna26.route.Router
import app.kcna26.settings.SettingsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DirectionsViewModelTest {

    private val dispatcher = UnconfinedTestDispatcher()
    private val repo = TestData.repo
    private val logs = mutableListOf<String>()
    private lateinit var settings: SettingsStore
    private var nowMs = 0L

    /** "The Future of Kubernetes Eviction and Node Lifecycle" (Wed, 251 A–C). */
    private val evictionTalk = repo.sessions.first { it.title.startsWith("The Future of Kubernetes Eviction") }.id
    private val vector = TestData.vectors.compass.first()

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        settings = SettingsStore(InMemoryPrefs())
        logs.clear()
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun vm(sessionId: String = evictionTalk) = DirectionsViewModel(
        repo = repo,
        router = Router(repo),
        settings = settings,
        clock = TestData.clockAt("2026-11-11T16:30:00-07:00"),
        sessionId = sessionId,
        declinationOf = { _, _, _, _ -> 10.0 },
        log = { logs += it },
        elapsedMs = { nowMs },
    )

    private fun test(block: suspend TestScope.() -> Unit) = runTest(dispatcher) { block() }

    @Test
    fun resolvesTheRoom() {
        val vm = vm()
        assertEquals("251AC", vm.room?.code)
        assertNotNull(vm.target)
        assertEquals(10.0, vm.declination, 1e-9)
    }

    @Test
    fun offSite_hasNoTargetOrPlan() {
        val off = repo.sessions.first { it.room == "OFF" }.id
        val vm = vm(off)
        assertNull(vm.target)
        assertNull(vm.plan.value)
    }

    @Test
    fun unknownSession_isSafe() {
        val vm = vm("nope")
        assertNull(vm.session)
        assertNull(vm.target)
        assertNull(vm.plan.value)
    }

    @Test
    fun myLocation_fallsBackUntilAFixThenGoesLive() = test {
        val vm = vm()
        val before = vm.plan.value!!
        assertEquals("LIVE", before.from)
        assertTrue(before.showFallbackNote)

        vm.onLocation(vector.lat, vector.lng, 12.0, null)
        runCurrent()
        val fix = vm.fix.value!!
        val local = Geo.toLocal(vector.lat, vector.lng, repo.wayfinding.origin)
        assertEquals(local.x, fix.x, 1e-9)
        assertEquals(local.y, fix.y, 1e-9)
        assertEquals(12.0, fix.accuracyM, 1e-9)
        val after = vm.plan.value!!
        assertTrue(after.route!!.live)
        assertFalse(after.showFallbackNote)
    }

    @Test
    fun reRoutesOnlyWhenTheLiveStartChanges() = test {
        val vm = vm()
        vm.onLocation(vector.lat, vector.lng, 10.0, null) // 200 South sidewalk: inside, starts at S200
        runCurrent()
        val first = vm.plan.value!!
        assertEquals(vector.myLocationStart.node, first.startKey)
        vm.onLocation(vector.lat + 0.00001, vector.lng, 10.0, null) // ~1 m on: same start, same steps
        runCurrent()
        assertSame(first, vm.plan.value)
        val far = TestData.vectors.compass[1] // Temple Square: outside, head to the West Temple entrance
        vm.onLocation(far.lat, far.lng, 10.0, null)
        runCurrent()
        assertNotSame(first, vm.plan.value)
        assertEquals("o${far.myLocationStart.entrance}", vm.plan.value!!.startKey)
        assertTrue(vm.plan.value!!.route!!.steps.first().text.startsWith("Head to the West Temple entrance"))
    }

    @Test
    fun heading_nullUntilTheCompassWakesThenTrue() = test {
        val vm = vm()
        vm.onLocation(vector.lat, vector.lng, 12.0, null)
        runCurrent()
        // The map hides the heading cone until there is a heading, fix or not.
        assertNull(vm.heading.value)

        // Magnetic 340° + 10° declination = 350° true (GeomagneticField's value is injected here).
        vm.onAzimuth(340.0, 0, 0, 0L)
        runCurrent()
        assertEquals(350.0, vm.heading.value!!, 1e-9)
    }

    @Test
    fun heading_isSmoothedTheShortWay() = test {
        val vm = vm()
        vm.onAzimuth(340.0, 0, 0, 0L) // 350 true
        vm.onAzimuth(0.0, 0, 0, 100L) // 10 true: half way is 0, not 180
        assertEquals(0.0, vm.heading.value!!, 1e-9)
    }

    @Test
    fun compassLog_atMostOncePerSecond() = test {
        val vm = vm()
        vm.onAzimuth(80.0, 7, 1, 0L)
        vm.onAzimuth(81.0, 7, 1, 400L)
        vm.onAzimuth(82.0, 7, 1, 999L)
        vm.onAzimuth(83.0, 7, 1, 1000L)
        assertEquals(2, logs.size)
        assertEquals("display=7 rotation=1 (90°) rawAzimuth=80.0 declination=10.0 trueHeading=90.0", logs[0])
    }

    @Test
    fun from_isPersistedAndValidated() = test {
        val vm = vm()
        vm.setFrom("EWT")
        runCurrent()
        assertEquals("EWT", settings.directionsFrom.value)
        assertEquals("EWT", vm.plan.value!!.from)
        vm.setFrom("REG") // not offered by the picker
        vm.setFrom("bogus")
        assertEquals("EWT", settings.directionsFrom.value)
        vm.setFrom("LIVE")
        runCurrent()
        assertEquals("LIVE", vm.plan.value!!.from)
    }

    @Test
    fun calibrationHint_afterAMomentOfPoorAccuracy() = test {
        val vm = vm()
        vm.onSensorAccuracy(Sensor.TYPE_MAGNETIC_FIELD, Calibration.UNRELIABLE)
        assertFalse(vm.calibrate.value)
        advanceTimeBy(DirectionsViewModel.CALIBRATE_AFTER_MS + 1)
        assertTrue(vm.calibrate.value)
        vm.onSensorAccuracy(Sensor.TYPE_MAGNETIC_FIELD, 3)
        assertFalse(vm.calibrate.value)

        // A brief blip doesn't flash the hint.
        vm.onSensorAccuracy(Sensor.TYPE_ROTATION_VECTOR, Calibration.LOW)
        advanceTimeBy(500)
        vm.onSensorAccuracy(Sensor.TYPE_ROTATION_VECTOR, 3)
        advanceTimeBy(DirectionsViewModel.CALIBRATE_AFTER_MS)
        assertFalse(vm.calibrate.value)
    }

    @Test
    fun noFix_after30SecondsOfTracking() = test {
        val vm = vm()
        vm.trackingStarted()
        advanceTimeBy(DirectionsViewModel.NO_FIX_AFTER_MS - 1)
        assertFalse(vm.noFix.value)
        advanceTimeBy(2)
        assertTrue(vm.noFix.value)
        vm.onLocation(vector.lat, vector.lng, 30.0, 1300.0)
        assertFalse(vm.noFix.value)
    }

    @Test
    fun staleFix_isDroppedWhenTrackingRestarts() = test {
        val vm = vm()
        nowMs = 1_000
        vm.onLocation(vector.lat, vector.lng, 10.0, null)
        vm.trackingStopped()
        nowMs = 3_000 // a fold/unfold later: keep it
        vm.trackingStarted()
        assertNotNull(vm.fix.value)
        vm.trackingStopped()
        nowMs = 1_000 + DirectionsViewModel.STALE_FIX_MS + 1 // back after a while: drop it
        vm.trackingStarted()
        assertNull(vm.fix.value)
        assertTrue(vm.plan.value!!.showFallbackNote)
    }

    @Test
    fun noFix_timerStopsWithTracking() = test {
        val vm = vm()
        vm.trackingStarted()
        vm.trackingStopped()
        advanceTimeBy(DirectionsViewModel.NO_FIX_AFTER_MS + 1)
        assertFalse(vm.noFix.value)
        vm.onLocationFailure()
        assertTrue(vm.noFix.value)
    }

    @Test
    fun badInputIsIgnored() = test {
        val vm = vm()
        vm.onLocation(Double.NaN, 0.0, 5.0, null)
        assertNull(vm.fix.value)
        vm.onAzimuth(Double.NaN, 0, 0, 0L)
        assertNull(vm.heading.value)
        vm.onLocation(vector.lat, vector.lng, Double.NaN, null)
        assertEquals(0.0, vm.fix.value!!.accuracyM, 1e-9)
    }
}
