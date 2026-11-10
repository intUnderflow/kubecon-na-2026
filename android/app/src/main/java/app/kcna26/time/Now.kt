package app.kcna26.time

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import app.kcna26.LocalAppGraph
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.time.Instant

/** Default re-evaluation period for [rememberNow]: every 15 s, aligned to :00/:15/:30/:45. */
const val NOW_PERIOD_MS: Long = 15_000L

/**
 * "Now" from the app clock, re-evaluated every [periodMillis] (aligned to the
 * wall clock, so minute labels flip within a second of the minute) while the
 * screen is at least STARTED, immediately on returning to the foreground, and
 * immediately when the debug fake time changes.
 *
 * Reading the returned value recomposes the caller each period; to keep that
 * cheap, read it as low in the tree as practical or use [rememberNowState].
 */
@Composable
fun rememberNow(periodMillis: Long = NOW_PERIOD_MS): Instant =
    rememberNowState(LocalAppGraph.current.clock, periodMillis).value

/** As [rememberNow] with an explicit clock. */
@Composable
fun rememberNow(clock: AppClock, periodMillis: Long = NOW_PERIOD_MS): Instant =
    rememberNowState(clock, periodMillis).value

/** State form of [rememberNow]: pass the State down and read `.value` only where needed. */
@Composable
fun rememberNowState(
    clock: AppClock = LocalAppGraph.current.clock,
    periodMillis: Long = NOW_PERIOD_MS,
): State<Instant> {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val offsetFlow: StateFlow<Long> = remember(clock) {
        (clock as? FakeableClock)?.offsetMillis ?: MutableStateFlow(0L)
    }
    val offset by offsetFlow.collectAsState()
    val now = remember(clock) { mutableStateOf(clock.now()) }
    LaunchedEffect(clock, offset, periodMillis, lifecycle) {
        now.value = clock.now()
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                val t = clock.now()
                now.value = t
                delay(periodMillis - Math.floorMod(t.toEpochMilli(), periodMillis) + 20)
            }
        }
    }
    return now
}
