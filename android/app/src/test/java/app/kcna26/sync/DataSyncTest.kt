package app.kcna26.sync

import app.kcna26.InMemoryPrefs
import app.kcna26.TestData
import app.kcna26.data.Repository
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class DataSyncTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private lateinit var bundledDir: File
    private lateinit var root: File
    private val prefs = InMemoryPrefs()
    private val fetcher = FakeFetcher()
    private var now = 1_000_000L
    private val swapped = mutableListOf<ActiveData>()

    @Before
    fun setUp() {
        bundledDir = tmp.newFolder("assets")
        for (name in BUNDLED_NAMES) File(TestData.assetsDir, name).copyTo(File(bundledDir, name))
        File(bundledDir, DataManifest.FILE).writeText(manifestJson(bundledFiles(), version = 1))
        root = File(tmp.root, "files/data")
    }

    // ------------------------------------------------------------------ helpers

    private fun newSync(appVersion: Int = 1) = DataSync(
        root = root,
        bundled = { name -> File(bundledDir, name).inputStream() },
        fetcher = fetcher,
        prefs = prefs,
        baseUrl = BASE,
        onSwapped = { swapped += it },
        nowMillis = { now },
        appVersion = appVersion,
    )

    private fun bundledFiles(): Map<String, ByteArray> =
        BUNDLED_NAMES.associateWith { File(bundledDir, it).readBytes() }

    private fun manifestJson(files: Map<String, ByteArray>, version: Int): String {
        val m = DataManifest(
            version = version,
            updatedAt = "2026-11-08T21:15:00Z",
            files = files.mapValues { (_, b) -> ManifestEntry(DataManifest.sha256(b), b.size.toLong()) },
        )
        return Json.encodeToString(DataManifest.serializer(), m)
    }

    /** Publishes the bundled files with [changes] applied, as manifest [version]. Returns the served files. */
    private fun publish(version: Int, etag: String, changes: Map<String, ByteArray> = emptyMap()): Map<String, ByteArray> {
        val files = bundledFiles() + changes
        fetcher.served.clear()
        for ((name, b) in files) fetcher.served[BASE + name] = b
        fetcher.served[BASE + DataManifest.FILE] = manifestJson(files, version).toByteArray()
        fetcher.etag = etag
        return files
    }

    /** schedule.json with the first session edited by [edit]. */
    private fun scheduleWithFirstSession(edit: (JsonObject) -> JsonObject): ByteArray {
        val doc = Json.parseToJsonElement(File(bundledDir, "schedule.json").readText()).jsonObject
        val sessions = doc.getValue("sessions").jsonArray
        val first = edit(sessions[0].jsonObject)
        return JsonObject(doc + ("sessions" to JsonArray(listOf(first) + sessions.drop(1)))).toString().toByteArray()
    }

    private fun JsonObject.with(key: String, value: String) = JsonObject(this + (key to JsonPrimitive(value)))

    /** The bundled [name] with its top-level object edited by [edit]. */
    private fun edited(name: String, edit: (JsonObject) -> JsonObject): ByteArray =
        edit(Json.parseToJsonElement(File(bundledDir, name).readText()).jsonObject).toString().toByteArray()

    private fun assertRejected(outcome: SyncOutcome, why: String) =
        assertTrue(outcome.toString(), outcome is SyncOutcome.Rejected && why in outcome.reason)

    private fun check(sync: DataSync): SyncOutcome = runBlocking { sync.check() }

    private fun downloads(): List<String> =
        fetcher.requests.map { it.first }.filter { it != BASE + DataManifest.FILE }.map { it.removePrefix(BASE) }

    private fun assertStillBundled(sync: DataSync) {
        val a = sync.active.value!!
        assertEquals(ActiveData.Source.BUNDLED, a.source)
        assertEquals(1, a.version)
        assertEquals(TestData.repo.sessions[0].title, a.repository.sessions[0].title)
        assertTrue(swapped.isEmpty())
        assertFalse(File(root, DataSync.POINTER).exists())
        assertFalse(File(root, DataSync.STAGING).exists())
        assertTrue(root.listFiles().orEmpty().none { it.name.startsWith("v") })
        // A restart still uses the bundled data.
        assertEquals(ActiveData.Source.BUNDLED, newSync().loadActive().source)
    }

    // ------------------------------------------------------------------ tests

    @Test
    fun startsFromTheBundledData() {
        val a = newSync().loadActive()
        assertEquals(ActiveData.Source.BUNDLED, a.source)
        assertEquals(1, a.version)
        assertEquals(TestData.repo.sessions.size, a.repository.sessions.size)
    }

    @Test
    fun happyPathDownloadsOnlyChangedFilesVerifiesAndSwaps() {
        val sync = newSync()
        sync.loadActive()
        publish(2, "\"e2\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "Moved to Ballroom B") }))

        assertEquals(SyncOutcome.Updated(2), check(sync))

        assertEquals(listOf("schedule.json"), downloads()) // everything else reused from the bundled copy
        val a = sync.active.value!!
        assertEquals(ActiveData.Source.GITHUB, a.source)
        assertEquals(2, a.version)
        assertEquals("Moved to Ballroom B", a.repository.sessions[0].title)
        assertEquals(listOf(2), swapped.map { it.version })
        assertEquals("v2", File(root, DataSync.POINTER).readText())
        assertTrue(File(root, "v2/schedule.json").isFile)
        assertTrue(File(root, "v2/manifest.json").isFile)
        assertFalse(File(root, DataSync.STAGING).exists())

        // After a restart the downloaded set is used, since it is newer than the bundled one.
        val restarted = newSync().loadActive()
        assertEquals(ActiveData.Source.GITHUB, restarted.source)
        assertEquals("Moved to Ballroom B", restarted.repository.sessions[0].title)
        assertEquals(TestData.repo.details.size, restarted.repository.details.size)
    }

    @Test
    fun notModifiedSendsTheEtagAndDownloadsNothing() {
        val sync = newSync()
        publish(2, "\"e2\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "X") }))
        assertEquals(SyncOutcome.Updated(2), check(sync))
        fetcher.requests.clear()

        assertEquals(SyncOutcome.NotModified, check(sync))
        assertEquals(listOf(BASE + DataManifest.FILE to "\"e2\""), fetcher.requests)
        assertEquals(listOf(2), swapped.map { it.version })
    }

    @Test
    fun hashMismatchLeavesDataUntouchedAndRetriesNextTime() {
        val sync = newSync()
        sync.loadActive()
        publish(2, "\"e2\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "New") }))
        // The CDN still serves the old schedule.json for a few minutes.
        fetcher.served[BASE + "schedule.json"] = File(bundledDir, "schedule.json").readBytes() + " ".toByteArray()

        val outcome = check(sync)
        assertTrue(outcome.toString(), outcome is SyncOutcome.Failed && "schedule.json" in outcome.reason)
        assertStillBundled(sync)

        // Not remembered as handled: the next check fetches the manifest again (no If-None-Match) and succeeds.
        publish(2, "\"e2\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "New") }))
        fetcher.requests.clear()
        assertEquals(SyncOutcome.Updated(2), check(sync))
        assertNull(fetcher.requests.first().second)
    }

    @Test
    fun badJsonIsRejectedAndNotDownloadedAgain() {
        val sync = newSync()
        sync.loadActive()
        publish(2, "\"bad\"", mapOf("schedule.json" to "{ \"sessions\": [ oops".toByteArray()))

        val outcome = check(sync)
        assertTrue(outcome.toString(), outcome is SyncOutcome.Rejected)
        assertStillBundled(sync)

        // Same broken manifest: a 304, so it isn't downloaded again.
        fetcher.requests.clear()
        assertEquals(SyncOutcome.NotModified, check(sync))
        assertEquals(emptyList<String>(), downloads())
    }

    @Test
    fun missingRoomReferenceIsRejected() {
        val sync = newSync()
        sync.loadActive()
        publish(2, "\"e2\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("room", "NOPE") }))

        val outcome = check(sync)
        assertTrue(outcome.toString(), outcome is SyncOutcome.Rejected && "unknown room 'NOPE'" in outcome.reason)
        assertStillBundled(sync)
    }

    @Test
    fun missingWayfindingNodeIsRejected() {
        val sync = newSync()
        sync.loadActive()
        val rooms = Json.parseToJsonElement(File(bundledDir, "rooms.json").readText()).jsonObject
        val all = rooms.getValue("rooms").jsonObject
        val (code, room) = all.entries.first { (_, r) -> "attachNode" in r.jsonObject }
        val broken = JsonObject(rooms + ("rooms" to JsonObject(all + (code to room.jsonObject.with("attachNode", "NOWHERE")))))
        publish(2, "\"e2\"", mapOf("rooms.json" to broken.toString().toByteArray()))

        val outcome = check(sync)
        assertTrue(outcome.toString(), outcome is SyncOutcome.Rejected && "unknown node 'NOWHERE'" in outcome.reason)
        assertStillBundled(sync)
    }

    @Test
    fun olderOrSameVersionIsIgnored() {
        val sync = newSync()
        sync.loadActive()
        publish(1, "\"same\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "Same version") }))
        assertEquals(SyncOutcome.NotNewer(1), check(sync))
        assertEquals(emptyList<String>(), downloads())
        assertStillBundled(sync)

        publish(3, "\"e3\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "Three") }))
        assertEquals(SyncOutcome.Updated(3), check(sync))
        fetcher.requests.clear()
        publish(2, "\"e2\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "Two") }))
        assertEquals(SyncOutcome.NotNewer(2), check(sync))
        assertEquals(emptyList<String>(), downloads())
        assertEquals("Three", sync.active.value!!.repository.sessions[0].title)
    }

    @Test
    fun partialDownloadIsNotSwapped() {
        val sync = newSync()
        sync.loadActive()
        val rooms = File(bundledDir, "rooms.json").readText().replaceFirst("{", "{ ").toByteArray()
        publish(
            2, "\"e2\"",
            mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "Half") }, "rooms.json" to rooms),
        )
        fetcher.failing += BASE + "schedule.json" // rooms.json downloads, schedule.json doesn't

        val outcome = check(sync)
        assertTrue(outcome.toString(), outcome is SyncOutcome.Failed)
        assertStillBundled(sync)
    }

    @Test
    fun offlineOr404IsAQuietFailure() {
        val sync = newSync()
        sync.loadActive()
        assertEquals(SyncOutcome.Failed("manifest: HTTP 404"), check(sync)) // repo not published yet
        assertStillBundled(sync)
    }

    @Test
    fun unsafeFileNamesAreRejected() {
        val sync = newSync()
        sync.loadActive()
        val files = bundledFiles() + ("../evil.json" to "{}".toByteArray())
        fetcher.served[BASE + DataManifest.FILE] = manifestJson(files, 2).toByteArray()
        val outcome = check(sync)
        assertTrue(outcome.toString(), outcome is SyncOutcome.Rejected)
        assertEquals(emptyList<String>(), downloads())
        assertStillBundled(sync)
    }

    @Test
    fun newerBundledDataWinsOverAnOlderDownload() {
        val sync = newSync()
        publish(2, "\"e2\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "Downloaded") }))
        assertEquals(SyncOutcome.Updated(2), check(sync))

        // An app update bundles version 3.
        File(bundledDir, DataManifest.FILE).writeText(manifestJson(bundledFiles(), version = 3))
        val restarted = newSync().loadActive()
        assertEquals(ActiveData.Source.BUNDLED, restarted.source)
        assertEquals(3, restarted.version)
        assertFalse(File(root, "v2").exists()) // the stale download is cleaned up
    }

    @Test
    fun corruptedDownloadFallsBackToBundled() {
        publish(2, "\"e2\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "Downloaded") }))
        assertEquals(SyncOutcome.Updated(2), check(newSync()))
        File(root, "v2/rooms.json").appendText(" ")

        val restarted = newSync().loadActive()
        assertEquals(ActiveData.Source.BUNDLED, restarted.source)
        assertEquals(1, restarted.version)
    }

    @Test
    fun foregroundChecksAreThrottledTo15Minutes() {
        val sync = newSync()
        assertTrue(sync.isDue()) // app start
        check(sync)
        now += DataSync.FOREGROUND_INTERVAL_MS - 1
        assertFalse(sync.isDue())
        now += 1
        assertTrue(sync.isDue())
    }

    @Test
    fun duplicateDayKeysAreRejected() {
        val sync = newSync()
        sync.loadActive()
        val schedule = edited("schedule.json") { doc ->
            val days = doc.getValue("days").jsonArray
            JsonObject(doc + ("days" to JsonArray(days + days[0])))
        }
        publish(2, "\"e2\"", mapOf("schedule.json" to schedule))
        assertRejected(check(sync), "duplicate day keys")
        assertStillBundled(sync)
    }

    @Test
    fun emptyBuildingOutlineIsRejected() {
        val sync = newSync()
        sync.loadActive()
        val venue = edited("venue.json") { doc ->
            val buildings = doc.getValue("buildings").jsonObject
            val hy = JsonObject(buildings.getValue("HY").jsonObject + ("outline" to JsonArray(emptyList())))
            JsonObject(doc + ("buildings" to JsonObject(buildings + ("HY" to hy))))
        }
        publish(2, "\"e2\"", mapOf("venue.json" to venue))
        assertRejected(check(sync), "building HY: outline has 0 points")
        assertStillBundled(sync)
    }

    @Test
    fun noEntrancesIsRejected() {
        val sync = newSync()
        sync.loadActive()
        publish(2, "\"e2\"", mapOf("wayfinding.json" to edited("wayfinding.json") { JsonObject(it + ("entrances" to JsonObject(emptyMap()))) }))
        assertRejected(check(sync), "no entrances")
        assertStillBundled(sync)
    }

    @Test
    fun theBundledSetWithItsCoLocatedEventsIsValid() {
        // colocated.json uses places rooms.json doesn't have (foyers, lunch hall): still valid.
        assertTrue("colocated.json" in BUNDLED_NAMES && "colocated_details.json" in BUNDLED_NAMES)
        val repo = Repository.fromDirectory(bundledDir)
        assertTrue(repo.coloEvents.isNotEmpty())
        assertEquals(emptyList<String>(), DataValidator.problems(repo, files = BUNDLED_NAMES))
    }

    @Test
    fun anUnreadableColocatedFileIsRejected() {
        // Repository.load would quietly drop it (no event cards): the published set must not.
        val sync = newSync()
        sync.loadActive()
        publish(2, "\"e2\"", mapOf("colocated.json" to "{ \"events\": [ oops".toByteArray()))
        assertRejected(check(sync), "colocated.json: no usable events")
        assertStillBundled(sync)
    }

    @Test
    fun aCoLocatedTalkInAnUnknownRoomIsRejected() {
        val sync = newSync()
        sync.loadActive()
        val colo = edited("colocated.json") { doc ->
            val sessions = doc.getValue("sessions").jsonArray
            JsonObject(doc + ("sessions" to JsonArray(listOf(sessions[0].jsonObject.with("room", "NOPE")) + sessions.drop(1))))
        }
        publish(2, "\"e2\"", mapOf("colocated.json" to colo))
        assertRejected(check(sync), "unknown room 'NOPE'")
        assertStillBundled(sync)
    }

    @Test
    fun aManifestWithoutABundledFileIsRejected() {
        val sync = newSync()
        sync.loadActive()
        val files = bundledFiles() - "rooms.json"
        for ((name, b) in files) fetcher.served[BASE + name] = b
        fetcher.served[BASE + DataManifest.FILE] = manifestJson(files, 2).toByteArray()
        assertRejected(check(sync), "missing rooms.json")
        assertEquals(emptyList<String>(), downloads())
        assertStillBundled(sync)
    }

    @Test
    fun aRejectionByAnOlderAppVersionIsRetried() {
        val v1 = newSync(appVersion = 1)
        publish(2, "\"bad\"", mapOf("schedule.json" to "{ \"sessions\": [ oops".toByteArray()))
        assertTrue(check(v1) is SyncOutcome.Rejected)
        fetcher.requests.clear()
        assertEquals(SyncOutcome.NotModified, check(v1)) // same app: remembered

        // An app update that might accept it: no If-None-Match, so it is fetched and checked again.
        val v2 = newSync(appVersion = 2)
        fetcher.requests.clear()
        assertTrue(check(v2) is SyncOutcome.Rejected)
        assertNull(fetcher.requests.first().second)
        fetcher.requests.clear()
        assertEquals(SyncOutcome.NotModified, check(v2))
    }

    @Test
    fun crashGuardRollsBackADownloadedSetThatKeepsCrashing() {
        val sync = newSync()
        publish(2, "\"e2\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "Crashy") }))
        assertEquals(SyncOutcome.Updated(2), check(sync))

        assertFalse(sync.onCrash()) // one crash could be anything
        assertTrue(File(root, DataSync.POINTER).exists())
        val restarted = newSync()
        assertEquals(ActiveData.Source.GITHUB, restarted.loadActive().source)
        assertTrue(restarted.onCrash()) // the second: roll back
        assertFalse(File(root, DataSync.POINTER).exists())

        // The next start uses the bundled data, and the same version isn't downloaded again.
        val safe = newSync()
        assertEquals(ActiveData.Source.BUNDLED, safe.loadActive().source)
        fetcher.requests.clear()
        assertRejected(check(safe), "rolled back")
        assertEquals(emptyList<String>(), downloads())
        assertEquals(SyncOutcome.NotModified, check(safe))

        // Fixed forward with a new version: downloaded as usual.
        publish(3, "\"e3\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "Fixed") }))
        assertEquals(SyncOutcome.Updated(3), check(safe))
        assertEquals("Fixed", safe.active.value!!.repository.sessions[0].title)
        assertFalse(safe.onCrash()) // v3 starts its own probation from zero
    }

    @Test
    fun crashGuardLeavesSetsAloneAfterProbationAndTheBundledData() {
        val bundled = newSync()
        bundled.loadActive()
        assertFalse(bundled.onCrash())
        assertFalse(bundled.onCrash())

        val sync = newSync()
        publish(2, "\"e2\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "Fine") }))
        assertEquals(SyncOutcome.Updated(2), check(sync))
        now += DataSync.PROBATION_MS + 1
        assertFalse(sync.onCrash())
        assertFalse(sync.onCrash())
        assertTrue(File(root, DataSync.POINTER).exists())
        assertEquals(ActiveData.Source.GITHUB, newSync().loadActive().source)
    }

    @Test
    fun aRollbackByAnOlderAppVersionDoesNotBlockAnUpdate() {
        val v1 = newSync(appVersion = 1)
        publish(2, "\"e2\"", mapOf("schedule.json" to scheduleWithFirstSession { it.with("title", "Crashy in 1") }))
        assertEquals(SyncOutcome.Updated(2), check(v1))
        v1.onCrash()
        assertTrue(v1.onCrash())

        val v2 = newSync(appVersion = 2)
        assertEquals(ActiveData.Source.BUNDLED, v2.loadActive().source)
        assertEquals(SyncOutcome.Updated(2), check(v2))
    }

    @Test
    fun theBundledDataSetPassesValidation() {
        assertEquals(emptyList<String>(), DataValidator.problems(TestData.repo))
    }

    private class FakeFetcher : DataFetcher {
        val served = HashMap<String, ByteArray>()
        val failing = HashSet<String>()
        var etag: String? = null
        val requests = mutableListOf<Pair<String, String?>>()

        override fun get(url: String, ifNoneMatch: String?, maxBytes: Long): HttpResult {
            requests += url to ifNoneMatch
            if (url in failing) return HttpResult.Failed("offline")
            val isManifest = url.endsWith("/" + DataManifest.FILE)
            if (isManifest && ifNoneMatch != null && ifNoneMatch == etag) return HttpResult.NotModified
            val body = served[url] ?: return HttpResult.Failed("HTTP 404")
            return HttpResult.Ok(body.copyOf(minOf(body.size.toLong(), maxBytes + 1).toInt()), if (isManifest) etag else null)
        }
    }

    private companion object {
        const val BASE = "https://example.test/data/"

        /** What the bundled manifest lists (make_manifest.py): the files a published set must have. */
        val BUNDLED_NAMES: Set<String> =
            DataManifest.parse(File(TestData.assetsDir, DataManifest.FILE).readBytes()).files.keys
    }
}
