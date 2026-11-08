package app.kcna26

import android.content.Context
import androidx.compose.runtime.staticCompositionLocalOf
import app.kcna26.data.Repository
import app.kcna26.details.DetailsRepository
import app.kcna26.going.GoingStore
import app.kcna26.route.Router
import app.kcna26.settings.SettingsStore
import app.kcna26.sync.DataSync
import app.kcna26.time.AppClock

/**
 * The app's shared objects (implemented by [KcnaApp]).
 *
 * - Compose: `val graph = LocalAppGraph.current` (provided at the root by MainActivity).
 * - Elsewhere (receivers, schedulers): `context.appGraph`.
 */
interface AppGraph {
    /**
     * All schedule data: the bundled assets, or a newer set downloaded by [dataSync].
     * Loaded once, on a background thread at process start.
     * Blocking on first access if not loaded yet: off the main thread use
     * [awaitRepository]. Inside composition it is always already loaded (the
     * shell waits for it before composing any screen).
     *
     * It is replaced as a whole (never mixed) when [dataSync] swaps in newer data.
     * It is backed by snapshot state, so composables that read it recompose with
     * the new data; `remember(repo)` and keyed lists keep everything stable.
     */
    val repository: Repository

    /** True once [repository] is loaded. */
    val isRepositoryLoaded: Boolean

    /** [repository], loading it on a background dispatcher if needed. */
    suspend fun awaitRepository(): Repository

    /** "Now" (real time, or the debug fake time). Never call Instant.now() directly. */
    val clock: AppClock

    /** RSVPs ("Going" in code): starred sessions and how long before them to send a reminder. */
    val going: GoingStore

    /** "I'm speaking as" and the Directions "From" choice. */
    val settings: SettingsStore

    /** Session descriptions and speaker taglines (owner: details). Rebuilt for each [repository]. */
    val details: DetailsRepository

    /** Indoor routing (owner: engine). Rebuilt for each [repository]. */
    val router: Router

    /** Live data updates from GitHub: [DataSync.active] (StateFlow), status and "Check now". */
    val dataSync: DataSync
}

/** The [AppGraph] for composables. */
val LocalAppGraph = staticCompositionLocalOf<AppGraph> { error("LocalAppGraph is not provided") }

/** The [AppGraph] from any context. */
val Context.appGraph: AppGraph get() = applicationContext as AppGraph
