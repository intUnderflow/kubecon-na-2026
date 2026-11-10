package app.kcna26.sync

import android.app.Activity
import android.app.Application
import android.content.SharedPreferences
import android.os.Bundle
import android.util.Log
import app.kcna26.data.Repository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.InputStream
import java.time.Instant
import kotlin.system.exitProcess

/** The data set the app is using: the bundled assets, or a set downloaded from GitHub. */
class ActiveData internal constructor(
    val repository: Repository,
    val manifest: DataManifest,
    val source: Source,
    /** The downloaded set's folder; null for the bundled assets. */
    internal val dir: File?,
) {
    enum class Source { BUNDLED, GITHUB }

    val version: Int get() = manifest.version
    val updatedAt: Instant? get() = manifest.updatedInstant
}

/** Result of one [DataSync.check]. */
sealed interface SyncOutcome {
    /** A newer set was verified and swapped in. */
    data class Updated(val version: Int) : SyncOutcome

    /** 304: the manifest hasn't changed since the last check. */
    data object NotModified : SyncOutcome

    /** The published set is not newer than the one in use. */
    data class NotNewer(val remoteVersion: Int) : SyncOutcome

    /** Offline, HTTP error, hash mismatch (CDN still serving an old file), partial download: retried next time. */
    data class Failed(val reason: String) : SyncOutcome

    /** The published set is broken (bad JSON, missing room, …): skipped until the manifest changes. */
    data class Rejected(val reason: String) : SyncOutcome
}

/** For the Settings row. */
data class SyncStatus(
    val checking: Boolean = false,
    val last: SyncOutcome? = null,
    val lastCheckedAt: Instant? = null,
)

/**
 * Live schedule data. The app ships its data in the APK and checks
 * [baseUrl]`manifest.json` (raw.githubusercontent.com, see BuildConfig.DATA_BASE_URL) for a newer
 * published set:
 *
 * - When: on app start (the first activity start of the process) and when the app comes back to
 *   the foreground at least [FOREGROUND_INTERVAL_MS] after the last check, plus Settings → "Check
 *   now". No polling. The manifest request sends If-None-Match, so an unchanged manifest is a 304.
 * - What: every file whose sha256 differs from the copy in use is downloaded and checked against
 *   the manifest's sha256 and size. Unchanged files are copied from the current set. The whole set
 *   is then parsed with the app's own DTOs ([Repository.load]) and checked by [DataValidator].
 * - Only then is it committed: written to a staging folder, renamed to `root/v<version>`, and
 *   made current by atomically replacing the `root/current` pointer (temp file + rename).
 *   [active] then emits the new set and [onSwapped] runs (the App republishes the Repository and
 *   reschedules reminders).
 * - Any failure leaves the current data untouched, is logged at debug level, and never throws.
 *
 * At start, [loadActive] uses the downloaded set only if it is intact, valid and newer than the
 * bundled assets' own manifest; otherwise the bundled assets (never a mix of the two).
 *
 * Crash guard ([installCrashGuard]): a downloaded set is on probation for [PROBATION_MS] after it
 * is swapped in. If the app crashes [MAX_CRASHES] times with it during that time, the `current`
 * pointer is deleted, so the next start uses the bundled assets, and that version is not
 * downloaded again by this app version (a newer published version is).
 *
 * Rejections (broken sets, crash rollbacks) are remembered per app version code, so an app
 * update that can read a set the old version rejected downloads it again.
 */
class DataSync(
    /** filesDir/data. */
    private val root: File,
    /** Opens a bundled asset by name (`assets::open`); throws if it doesn't exist. */
    private val bundled: (String) -> InputStream,
    private val fetcher: DataFetcher,
    private val prefs: SharedPreferences,
    /** Ends with '/'. */
    private val baseUrl: String,
    private val onSwapped: (ActiveData) -> Unit = {},
    /** Wall-clock millis, for the foreground throttle, "last checked" and probation (not app "now", which may be faked). */
    private val nowMillis: () -> Long = { System.currentTimeMillis() },
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    /** BuildConfig.VERSION_CODE: remembered rejections apply to this app version only. */
    private val appVersion: Int = 0,
) {
    private val _active = MutableStateFlow<ActiveData?>(null)
    private val _status = MutableStateFlow(SyncStatus())
    private val loadLock = Any()
    private val mutex = Mutex()
    private val scope = CoroutineScope(SupervisorJob() + ioDispatcher)

    @Volatile
    private var lastCheckMillis: Long? = null

    /** The files the bundled manifest lists: a downloaded set must have all of them. */
    @Volatile
    private var requiredFiles: Set<String> = emptySet()

    /** The data set in use; null until [loadActive] has run. */
    val active: StateFlow<ActiveData?> = _active.asStateFlow()

    val status: StateFlow<SyncStatus> = _status.asStateFlow()

    val manifestUrl: String get() = baseUrl + DataManifest.FILE

    // ------------------------------------------------------------------ start

    /**
     * The data set to use, loaded on first call (blocking: call off the main thread). Throws only
     * if the bundled assets themselves can't be loaded.
     */
    fun loadActive(): ActiveData {
        _active.value?.let { return it }
        synchronized(loadLock) {
            _active.value?.let { return it }
            val bundledManifest = readBundledManifest()
            requiredFiles = bundledManifest.files.keys
            val local = currentDir()?.let { dir -> loadLocal(dir, bundledManifest.version) }
            val result = local ?: ActiveData(Repository.load(bundled), bundledManifest, ActiveData.Source.BUNDLED, null)
            prune(keep = result.dir)
            _active.value = result
            return result
        }
    }

    private fun readBundledManifest(): DataManifest =
        try {
            DataManifest.parse(bundled(DataManifest.FILE).use { it.readBytes() })
        } catch (e: Exception) {
            debug("no bundled manifest", e)
            DataManifest()
        }

    /** The downloaded set in [dir] if it is newer than [bundledVersion], intact and valid. */
    private fun loadLocal(dir: File, bundledVersion: Int): ActiveData? =
        try {
            val m = DataManifest.parse(File(dir, DataManifest.FILE).readBytes())
            when {
                m.version <= bundledVersion -> null.also { debug("downloaded v${m.version} is not newer than bundled v$bundledVersion") }
                m.version == badVersion() -> null.also { debug("downloaded v${m.version} was rolled back after crashes") }
                m.problems(requiredFiles).isNotEmpty() -> null.also { debug("downloaded manifest: ${m.problems(requiredFiles)}") }
                else -> {
                    for ((name, e) in m.files) {
                        val b = File(dir, name).readBytes()
                        require(b.size.toLong() == e.bytes && DataManifest.sha256(b) == e.sha256) { "$name changed on disk" }
                    }
                    // Verified in full (details.json too) before it was committed; the hashes
                    // above prove it is unchanged, so details.json stays lazy here (cold start).
                    val repo = Repository.fromDirectory(dir)
                    val problems = DataValidator.problems(repo, includeDetails = false, files = m.files.keys)
                    if (problems.isEmpty()) ActiveData(repo, m, ActiveData.Source.GITHUB, dir)
                    else null.also { debug("downloaded set invalid: $problems") }
                }
            }
        } catch (e: Exception) {
            debug("downloaded set unusable", e)
            null
        }

    // ------------------------------------------------------------------ checks

    /** Registers for activity starts: checks on app start and on foreground after [FOREGROUND_INTERVAL_MS]. */
    fun watchForeground(app: Application) {
        app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            private var started = 0
            override fun onActivityStarted(activity: Activity) {
                if (started++ == 0) onForeground()
            }
            override fun onActivityStopped(activity: Activity) {
                started = (started - 1).coerceAtLeast(0)
            }
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityResumed(activity: Activity) = Unit
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        })
    }

    /** The app came to the foreground: check if none has run in this process, or the last was long enough ago. */
    fun onForeground() {
        if (isDue()) checkInBackground()
    }

    /** True if no check has started in this process, or the last one started [FOREGROUND_INTERVAL_MS] ago. */
    fun isDue(now: Long = nowMillis()): Boolean = lastCheckMillis.let { it == null || now - it >= FOREGROUND_INTERVAL_MS }

    /** "Check now": runs [check] in the background unless one is already running. */
    fun checkInBackground() {
        if (_status.value.checking) return
        lastCheckMillis = nowMillis()
        scope.launch { check() }
    }

    /** One check: manifest, downloads, verification, swap. Main-safe; never throws (except cancellation). */
    suspend fun check(): SyncOutcome = withContext(ioDispatcher) {
        mutex.withLock {
            lastCheckMillis = nowMillis()
            _status.value = _status.value.copy(checking = true)
            val outcome = try {
                runCheck()
            } catch (e: CancellationException) {
                _status.value = _status.value.copy(checking = false)
                throw e
            } catch (e: Throwable) {
                // Includes OOM / StackOverflow from a hostile file: drop it and keep the current data.
                SyncOutcome.Failed(e.javaClass.simpleName + ": " + e.message)
            } finally {
                File(root, STAGING).deleteRecursively()
            }
            debug("check: $outcome")
            _status.value = SyncStatus(checking = false, last = outcome, lastCheckedAt = Instant.ofEpochMilli(nowMillis()))
            outcome
        }
    }

    private fun runCheck(): SyncOutcome {
        val active = loadActive()
        val etag = prefs.getString(KEY_ETAG, null)
        val etagVersion = prefs.getInt(KEY_ETAG_VERSION, 0)
        // A rejection by an older app version doesn't count: this one may accept the set.
        val etagRejected = prefs.getBoolean(KEY_ETAG_REJECTED, false) && prefs.getInt(KEY_REJECTED_BY, -1) == appVersion
        // Only trust a 304 if we already hold that manifest's data (or know it is broken).
        val ifNoneMatch = etag?.takeIf { etagRejected || active.version >= etagVersion }

        val body = when (val r = fetcher.get(manifestUrl, ifNoneMatch, MAX_MANIFEST_BYTES)) {
            HttpResult.NotModified -> return SyncOutcome.NotModified
            is HttpResult.Failed -> return SyncOutcome.Failed("manifest: " + r.reason)
            is HttpResult.Ok -> r
        }
        if (body.body.size > MAX_MANIFEST_BYTES) return SyncOutcome.Failed("manifest too large")
        val remote = try {
            DataManifest.parse(body.body)
        } catch (e: Exception) {
            remember(body.etag, 0, rejected = true)
            return SyncOutcome.Rejected("manifest: " + e.message)
        }
        remote.problems(requiredFiles).takeIf { it.isNotEmpty() }?.let {
            remember(body.etag, remote.version, rejected = true)
            return SyncOutcome.Rejected("manifest: $it")
        }
        if (remote.version <= active.version) {
            remember(body.etag, remote.version, rejected = false)
            return SyncOutcome.NotNewer(remote.version)
        }
        if (remote.version == badVersion()) {
            remember(body.etag, remote.version, rejected = true)
            return SyncOutcome.Rejected("v${remote.version} was rolled back after crashes")
        }

        // Stage the complete set: reuse identical files, download the rest.
        val staging = File(root, STAGING)
        staging.deleteRecursively()
        if (!staging.mkdirs()) return SyncOutcome.Failed("can't create $staging")
        for ((name, entry) in remote.files) {
            val bytes = reusable(active, name, entry) ?: when (val r = fetcher.get(baseUrl + name, null, entry.bytes)) {
                is HttpResult.Ok -> r.body
                HttpResult.NotModified -> return SyncOutcome.Failed("$name: unexpected 304")
                is HttpResult.Failed -> return SyncOutcome.Failed("$name: " + r.reason)
            }
            if (bytes.size.toLong() != entry.bytes) return SyncOutcome.Failed("$name: ${bytes.size} bytes, expected ${entry.bytes}")
            if (DataManifest.sha256(bytes) != entry.sha256) return SyncOutcome.Failed("$name: sha256 mismatch")
            File(staging, name).writeBytes(bytes)
        }
        File(staging, DataManifest.FILE).writeBytes(body.body)

        // Parse and cross-check the whole set before anything changes.
        val repo = try {
            Repository.fromDirectory(staging).also { it.details } // details.json too, before the folder moves
        } catch (e: Exception) {
            remember(body.etag, remote.version, rejected = true)
            return SyncOutcome.Rejected("parse: " + e.message)
        }
        DataValidator.problems(repo, files = remote.files.keys).takeIf { it.isNotEmpty() }?.let {
            remember(body.etag, remote.version, rejected = true)
            return SyncOutcome.Rejected("invalid: $it")
        }

        // Commit: folder rename, then the pointer flip (the atomic step).
        val dir = File(root, "v${remote.version}")
        if (dir.exists() && !dir.deleteRecursively()) return SyncOutcome.Failed("can't clear $dir")
        if (!staging.renameTo(dir)) return SyncOutcome.Failed("can't rename $staging")
        val tmp = File(root, "$POINTER.tmp")
        tmp.writeText(dir.name)
        if (!tmp.renameTo(File(root, POINTER))) {
            dir.deleteRecursively()
            return SyncOutcome.Failed("can't update $POINTER")
        }

        val next = ActiveData(repo, remote, ActiveData.Source.GITHUB, dir)
        prefs.edit()
            .putInt(KEY_PROBATION_VERSION, remote.version)
            .putLong(KEY_PROBATION_SINCE, nowMillis())
            .putInt(KEY_CRASHES, 0)
            .apply()
        _active.value = next
        remember(body.etag, remote.version, rejected = false)
        try {
            onSwapped(next)
        } catch (e: Exception) {
            debug("onSwapped failed", e)
        }
        return SyncOutcome.Updated(remote.version)
    }

    /** [name]'s bytes from the set in use (or the bundled assets) if identical to [entry]; else null. */
    private fun reusable(active: ActiveData, name: String, entry: ManifestEntry): ByteArray? {
        fun ByteArray.matches() = size.toLong() == entry.bytes && DataManifest.sha256(this) == entry.sha256
        active.dir?.let { d -> File(d, name).takeIf { it.isFile }?.readBytes()?.takeIf { it.matches() }?.let { return it } }
        val b = try {
            bundled(name).use { it.readBytes() }
        } catch (_: Exception) {
            null // not bundled
        }
        return b?.takeIf { it.matches() }
    }

    private fun remember(etag: String?, version: Int, rejected: Boolean) {
        val e = prefs.edit()
        if (etag == null) e.remove(KEY_ETAG) else e.putString(KEY_ETAG, etag)
        e.putInt(KEY_ETAG_VERSION, version).putBoolean(KEY_ETAG_REJECTED, rejected).putInt(KEY_REJECTED_BY, appVersion).apply()
    }

    /** The downloaded version this app version rolled back after crashes, or 0. */
    private fun badVersion(): Int =
        if (prefs.getInt(KEY_BAD_VERSION_APP, -1) == appVersion) prefs.getInt(KEY_BAD_VERSION, 0) else 0

    // ------------------------------------------------------------------ crash guard

    /** Chains a default uncaught-exception handler that calls [onCrash] first. Call once, from Application.onCreate. */
    fun installCrashGuard() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, e ->
            try {
                onCrash()
            } catch (_: Throwable) {
                // Never get in the way of the real crash report.
            }
            if (previous != null) previous.uncaughtException(thread, e) else exitProcess(10)
        }
    }

    /**
     * The process is about to die from an uncaught exception. If a downloaded set on probation is
     * in use, count it; at [MAX_CRASHES] drop the set, so the next start uses the bundled assets.
     * Synchronous (commit), since the process ends right after. Returns true if it rolled back.
     */
    internal fun onCrash(): Boolean {
        val a = _active.value ?: return false
        if (a.source != ActiveData.Source.GITHUB || prefs.getInt(KEY_PROBATION_VERSION, 0) != a.version) return false
        if (nowMillis() - prefs.getLong(KEY_PROBATION_SINCE, 0) > PROBATION_MS) return false
        val crashes = prefs.getInt(KEY_CRASHES, 0) + 1
        if (crashes < MAX_CRASHES) {
            prefs.edit().putInt(KEY_CRASHES, crashes).commit()
            return false
        }
        File(root, POINTER).delete()
        prefs.edit()
            .putInt(KEY_BAD_VERSION, a.version)
            .putInt(KEY_BAD_VERSION_APP, appVersion)
            .remove(KEY_PROBATION_VERSION)
            .putInt(KEY_CRASHES, 0)
            .commit()
        debug("rolled back v${a.version} after $crashes crashes")
        return true
    }

    // ------------------------------------------------------------------ files

    private fun currentDir(): File? =
        try {
            val name = File(root, POINTER).takeIf { it.isFile }?.readText()?.trim().orEmpty()
            if (VERSION_DIR.matches(name)) File(root, name).takeIf { it.isDirectory } else null
        } catch (e: Exception) {
            debug("no current pointer", e)
            null
        }

    /** Deletes every downloaded set except [keep] (and the pointer if nothing is kept). */
    private fun prune(keep: File?) {
        val children = root.listFiles() ?: return
        for (f in children) {
            val keepIt = (keep != null && (f == keep || f.name == POINTER))
            if (!keepIt) f.deleteRecursively()
        }
    }

    private fun debug(msg: String, e: Throwable? = null) {
        Log.d(TAG, "data sync: $msg" + (e?.let { " ($it)" } ?: ""))
    }

    companion object {
        const val TAG = "kcna26"
        const val PREFS = "kcna26.sync"

        /** Foreground checks at most this often (app start always checks). */
        const val FOREGROUND_INTERVAL_MS = 15L * 60 * 1000

        const val MAX_MANIFEST_BYTES = 256L * 1024

        /** How long a newly downloaded set is on probation for the crash guard. */
        const val PROBATION_MS = 24L * 60 * 60 * 1000

        /** Crashes with a set on probation before it is rolled back (one could be unrelated). */
        const val MAX_CRASHES = 2

        internal const val POINTER = "current"
        internal const val STAGING = ".staging"
        private val VERSION_DIR = Regex("^v[0-9]+$")
        private const val KEY_ETAG = "manifestEtag"
        private const val KEY_ETAG_VERSION = "manifestEtagVersion"
        private const val KEY_ETAG_REJECTED = "manifestEtagRejected"
        private const val KEY_REJECTED_BY = "rejectedByAppVersion"
        private const val KEY_PROBATION_VERSION = "probationVersion"
        private const val KEY_PROBATION_SINCE = "probationSince"
        private const val KEY_CRASHES = "probationCrashes"
        private const val KEY_BAD_VERSION = "rolledBackVersion"
        private const val KEY_BAD_VERSION_APP = "rolledBackByAppVersion"
    }
}
