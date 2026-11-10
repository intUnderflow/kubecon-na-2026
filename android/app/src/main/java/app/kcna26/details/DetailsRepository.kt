package app.kcna26.details

import android.util.Log
import app.kcna26.data.Repository
import app.kcna26.data.Session
import app.kcna26.data.SessionDetail
import app.kcna26.data.SpeakerTagline
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * Session descriptions and speaker taglines (port of schedule_app.js loadDetails / parseMd /
 * fetchOne). Sources, in order:
 *
 * 1. in memory (everything resolved so far this process, including "nothing there"),
 * 2. the bundled details.json ([Repository.details], 558 of 579 KubeCon sessions, plus every
 *    co-located session from colocated.json),
 * 3. Maintainer Summit sessions ("m…" ids): [Session.description] / [Session.slidesUrl] from
 *    schedule.json (maintainer_summit_details.json by id as a fallback),
 * 4. a disk cache under [cacheDir] (one `<id>.json` per session, details.json's entry shape),
 * 5. a live Sessionize fetch, KubeCon ids only, parsed by [SessionizeMarkdown] and written to (4).
 *    Co-located sessions ([Session.isColocated]) have plain numeric ids too, but they belong to
 *    another Sessionize event: they are never fetched or disk-cached (the bundle is complete).
 *
 * Offline-safe: nothing here throws. A failed fetch is reported as [DetailsResult.Unavailable] and
 * is not retried for [failBackoffMillis] (re-opening the sheet after that tries once more).
 * Concurrent requests for one id share a single fetch, and a fetch keeps running (and caches) even
 * if the screen that asked for it goes away. Disk and network work runs on [ioDispatcher].
 *
 * The App constructs it as `DetailsRepository(repository, File(filesDir or cacheDir, "details"))`.
 */
class DetailsRepository(
    private val repo: Repository,
    private val cacheDir: File,
    private val fetcher: DetailsFetcher = SessionizeFetcher(),
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    /** Monotonic milliseconds, for the retry backoff only (not app "now", which may be faked). */
    private val elapsedMillis: () -> Long = { System.nanoTime() / 1_000_000L },
    private val failBackoffMillis: Long = FAIL_BACKOFF_MS,
) {
    private val memory = ConcurrentHashMap<String, DetailsResult>()
    private val failedAt = ConcurrentHashMap<String, Long>()
    private val inFlight = HashMap<String, Deferred<DetailsResult>>()
    private val lock = Any()
    private val scope = CoroutineScope(SupervisorJob() + ioDispatcher)

    /** details.json, once something has touched it off the main thread (see [warmBundled]). */
    @Volatile
    private var bundled: Map<String, SessionDetail>? = null

    /** Synchronous lookup without I/O or network. Null if not available (yet). */
    fun peek(sessionId: String): DetailInfo? = (peekResult(sessionId) as? DetailsResult.Found)?.info

    /** Full lookup: [load], keeping only the details themselves. Main-safe. Null if none. */
    suspend fun get(sessionId: String): DetailInfo? = (load(sessionId) as? DetailsResult.Found)?.info

    /**
     * What is known without any I/O: memory, Maintainer Summit data, and details.json if it has
     * already been parsed. [DetailsResult.Unavailable] while a recent failure is backing off.
     * Null means "unknown until [load] runs".
     */
    fun peekResult(sessionId: String): DetailsResult? {
        memory[sessionId]?.let { return it }
        val s = repo.session(sessionId) ?: return DetailsResult.None
        if (s.isMaintainerSummit) return keep(sessionId, summit(s))
        val b = bundled ?: return null
        b[sessionId]?.let { return keep(sessionId, found(s, it, DetailInfo.Source.BUNDLED)) }
        return if (isBackingOff(sessionId)) DetailsResult.Unavailable else null
    }

    /** Resolves a session's details from every source, fetching live if needed. Main-safe; never throws. */
    suspend fun load(sessionId: String): DetailsResult {
        peekResult(sessionId)?.let { if (it != DetailsResult.Unavailable) return it }
        val s = repo.session(sessionId) ?: return DetailsResult.None
        withContext(ioDispatcher) { local(s) }?.let { return it }
        if (!isFetchable(s)) return keep(sessionId, DetailsResult.None)
        return fetchShared(sessionId).await()
    }

    /** Parses details.json now. Blocking: call off the main thread (e.g. at app start). */
    fun warmBundled() {
        bundledMap()
    }

    // ------------------------------------------------------------------ sources

    private fun bundledMap(): Map<String, SessionDetail> =
        bundled ?: try {
            repo.details
        } catch (e: Exception) {
            Log.w(TAG, "details.json unreadable", e)
            emptyMap()
        }.also { bundled = it }

    /** Bundled, then disk. Runs on [ioDispatcher]. */
    private fun local(s: Session): DetailsResult? {
        bundledMap()[s.id]?.let { return keep(s.id, found(s, it, DetailInfo.Source.BUNDLED)) }
        readDisk(s.id)?.let { return keep(s.id, found(s, it, DetailInfo.Source.DISK_CACHE)) }
        return null
    }

    private fun fetchShared(id: String): Deferred<DetailsResult> = synchronized(lock) {
        inFlight[id]?.let { return it }
        if (isBackingOff(id)) return CompletableDeferred(DetailsResult.Unavailable)
        val job = scope.async(start = CoroutineStart.LAZY) { fetchNow(id) }
        inFlight[id] = job
        job.invokeOnCompletion { synchronized(lock) { if (inFlight[id] === job) inFlight.remove(id) } }
        job.start()
        job
    }

    private fun fetchNow(id: String): DetailsResult {
        val s = repo.session(id) ?: return DetailsResult.None
        if (!isFetchable(s)) return keep(id, DetailsResult.None)
        // Another caller may have cached it while this one was queued.
        memory[id]?.let { return it }
        readDisk(id)?.let { return keep(id, found(s, it, DetailInfo.Source.DISK_CACHE)) }
        val r = try {
            fetcher.fetch(id)
        } catch (e: Exception) {
            FetchResult.Failed(e.toString())
        }
        return when (r) {
            is FetchResult.Ok -> {
                failedAt.remove(id)
                val d = try {
                    SessionizeMarkdown.parse(r.body)
                } catch (e: Exception) {
                    SessionDetail("", emptyList())
                }
                if (d.description.isNotEmpty() || d.speakers.isNotEmpty()) {
                    writeDisk(id, d)
                    keep(id, found(s, d, DetailInfo.Source.LIVE))
                } else {
                    // Like the web: remember "nothing there" in memory only.
                    keep(id, DetailsResult.None)
                }
            }
            FetchResult.NotFound -> {
                failedAt.remove(id)
                keep(id, DetailsResult.None)
            }
            is FetchResult.Failed -> {
                Log.i(TAG, "details $id: ${r.reason}")
                failedAt[id] = elapsedMillis()
                DetailsResult.Unavailable
            }
        }
    }

    private fun isBackingOff(id: String): Boolean {
        val t = failedAt[id] ?: return false
        return elapsedMillis() - t < failBackoffMillis
    }

    private fun keep(id: String, r: DetailsResult): DetailsResult {
        if (r != DetailsResult.Unavailable) memory[id] = r
        return r
    }

    // ------------------------------------------------------------------ disk cache

    private fun cacheFile(id: String) = File(cacheDir, "$id.json")

    /** Live-fetchable from the main KubeCon Sessionize event (and so disk-cached). */
    private fun isFetchable(s: Session): Boolean = !s.isColocated && isKubeConId(s.id)

    private fun isCacheable(id: String): Boolean = isKubeConId(id) && repo.session(id)?.isColocated != true

    private fun readDisk(id: String): SessionDetail? {
        if (!isCacheable(id)) return null
        val f = cacheFile(id)
        return try {
            if (!f.isFile) return null
            val e = Repository.json.decodeFromString(CachedDetail.serializer(), f.readText())
            SessionDetail(e.description, e.speakers.map { SpeakerTagline(it.name, it.tagline) })
                .takeIf { it.description.isNotEmpty() || it.speakers.isNotEmpty() }
        } catch (e: Exception) {
            Log.w(TAG, "dropping unreadable cache $f", e)
            f.delete()
            null
        }
    }

    private fun writeDisk(id: String, d: SessionDetail) {
        if (!isCacheable(id)) return
        try {
            cacheDir.mkdirs()
            val tmp = File(cacheDir, "$id.json.tmp")
            tmp.writeText(
                Repository.json.encodeToString(
                    CachedDetail.serializer(),
                    CachedDetail(d.description, d.speakers.map { CachedSpeaker(it.name, it.tagline) }),
                ),
            )
            if (!tmp.renameTo(cacheFile(id))) {
                cacheFile(id).delete()
                tmp.renameTo(cacheFile(id))
            }
        } catch (e: Exception) {
            Log.w(TAG, "can't cache details $id", e)
        }
    }

    // ------------------------------------------------------------------ mapping

    private fun found(s: Session, d: SessionDetail, source: DetailInfo.Source) = DetailsResult.Found(
        DetailInfo(
            description = d.description.takeIf { it.isNotBlank() },
            speakers = d.speakers,
            slidesUrl = s.slidesUrl,
            link = null,
            linkText = null,
            source = source,
        ),
    )

    /**
     * The web's `MSD[x.id]`. (Its `MSD.UNCONF` fallback for "Unconference…" sessions, the "See and
     * vote on the topics" link, went with the unconference feature: voting is over.)
     */
    private fun summit(s: Session): DetailsResult {
        val md = repo.summitDetails[s.id]
        return DetailsResult.Found(
            DetailInfo(
                description = (s.description ?: md?.description)?.takeIf { it.isNotBlank() },
                speakers = emptyList(),
                slidesUrl = s.slidesUrl ?: md?.slides,
                link = md?.link,
                linkText = md?.linkText,
                source = DetailInfo.Source.SUMMIT,
            ),
        )
    }

    @Serializable
    private data class CachedDetail(val description: String = "", val speakers: List<CachedSpeaker> = emptyList())

    @Serializable
    private data class CachedSpeaker(val name: String, val tagline: String = "")

    companion object {
        private const val TAG = "kcna26"

        /** How long a failed fetch for one session is not retried. */
        const val FAIL_BACKOFF_MS = 30_000L

        private val KUBECON_ID = Regex("\\d{1,12}")

        /** KubeCon (Sessionize) ids are plain digits; Maintainer Summit ids start with "m". */
        fun isKubeConId(id: String): Boolean = KUBECON_ID.matches(id)
    }
}

/** Outcome of [DetailsRepository.load]. */
sealed interface DetailsResult {
    /** Details to show (the description may still be null, e.g. a Maintainer Summit break). */
    data class Found(val info: DetailInfo) : DetailsResult

    /** Nothing anywhere: the sheet shows no About section (the web's `desc=''`). */
    data object None : DetailsResult

    /** Not bundled or cached and the live fetch failed (offline?). Show a quiet note; retry later. */
    data object Unavailable : DetailsResult
}

/**
 * Everything the details sheet shows beyond the schedule fields.
 * @property description markdown-ish text with blank-line paragraphs (see [DescriptionFormat]); null if none.
 * @property speakers names with taglines, in order; empty means use Session.speakers.
 * @property link/linkText an optional extra link from maintainer_summit_details.json (opened in the browser).
 */
data class DetailInfo(
    val description: String?,
    val speakers: List<SpeakerTagline>,
    val slidesUrl: String?,
    val link: String?,
    val linkText: String?,
    val source: Source,
) {
    enum class Source { BUNDLED, SUMMIT, DISK_CACHE, LIVE }
}
