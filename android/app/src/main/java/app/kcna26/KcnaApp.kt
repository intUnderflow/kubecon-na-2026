package app.kcna26

import android.app.Application
import android.util.Log
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.snapshots.Snapshot
import app.kcna26.data.Repository
import app.kcna26.details.DetailsRepository
import app.kcna26.going.GoingStore
import app.kcna26.reminders.ReminderScheduler
import app.kcna26.route.Router
import app.kcna26.settings.SettingsStore
import app.kcna26.sync.ActiveData
import app.kcna26.sync.DataSync
import app.kcna26.sync.HttpDataFetcher
import app.kcna26.sync.RepositoryScoped
import app.kcna26.time.AppClock
import app.kcna26.time.FakeableClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** Application: holds the [AppGraph]. Declared in the manifest as `.KcnaApp`. */
class KcnaApp : Application(), AppGraph {

    override val dataSync: DataSync by lazy {
        DataSync(
            root = File(filesDir, "data"),
            bundled = { name -> assets.open(name) },
            fetcher = HttpDataFetcher(),
            prefs = getSharedPreferences(DataSync.PREFS, MODE_PRIVATE),
            baseUrl = BuildConfig.DATA_BASE_URL,
            onSwapped = ::onDataSwapped,
            appVersion = BuildConfig.VERSION_CODE,
        )
    }

    // The downloaded set if valid and newer than the bundled assets, else the assets.
    private val repositoryLazy = lazy(LazyThreadSafetyMode.SYNCHRONIZED) { dataSync.loadActive().repository }

    /** Set when DataSync swaps in newer data. Snapshot state, so composables reading [repository] recompose. */
    private val swappedRepository = mutableStateOf<Repository?>(null)

    override val repository: Repository get() = swappedRepository.value ?: repositoryLazy.value

    override val isRepositoryLoaded: Boolean get() = repositoryLazy.isInitialized()

    override suspend fun awaitRepository(): Repository =
        if (isRepositoryLoaded) repository else withContext(Dispatchers.IO) { repository }

    /** The concrete clock, for the debug fake-time override (MainActivity). */
    val fakeableClock: FakeableClock by lazy {
        FakeableClock(getSharedPreferences(FakeableClock.PREFS, MODE_PRIVATE), allowFake = BuildConfig.DEBUG)
    }

    override val clock: AppClock get() = fakeableClock

    override val going: GoingStore by lazy {
        GoingStore(getSharedPreferences(GoingStore.PREFS, MODE_PRIVATE)).also { g ->
            // Reminders follow the stars and "Remind me before sessions I'm going to" (cheap, idempotent).
            merge(g.ids.drop(1), g.remindMinutes.drop(1)).onEach { ReminderScheduler.reschedule(this) }.launchIn(appScope)
        }
    }

    override val settings: SettingsStore by lazy {
        SettingsStore(getSharedPreferences(SettingsStore.PREFS, MODE_PRIVATE))
    }

    // filesDir, not cacheDir: live-fetched descriptions must survive low-storage cache purges (offline use).
    private val detailsByRepository = RepositoryScoped { DetailsRepository(it, File(filesDir, "details")) }
    override val details: DetailsRepository get() = detailsByRepository[repository]

    private val routerByRepository = RepositoryScoped { Router(it) }
    override val router: Router get() = routerByRepository[repository]

    /** Process-lifetime scope for background work. */
    val appScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        // Parse the bundled JSON off the main thread right away; details.json after the core files.
        appScope.launch(Dispatchers.IO) {
            try {
                details.warmBundled() // parses details.json, so the first sheet open is synchronous
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load bundled data", e)
            }
        }
        // Newer schedule data from GitHub: on app start and back in the foreground (see DataSync),
        // rolled back to the bundled data if the app keeps crashing with a new set.
        dataSync.installCrashGuard()
        dataSync.watchForeground(this)
        // Reminders follow "I'm speaking as" and the debug fake time.
        settings.speakingAs.drop(1).onEach { ReminderScheduler.reschedule(this) }.launchIn(appScope)
        fakeableClock.offsetMillis.drop(1).onEach { ReminderScheduler.reschedule(this) }.launchIn(appScope)
    }

    /** DataSync committed a newer data set (background thread): publish it, then re-plan reminders. */
    private fun onDataSwapped(next: ActiveData) {
        Snapshot.withMutableSnapshot { swappedRepository.value = next.repository }
        appScope.launch(Dispatchers.IO) { runCatching { details.warmBundled() } }
        ReminderScheduler.reschedule(this)
    }

    companion object {
        const val TAG = "kcna26"
    }
}
