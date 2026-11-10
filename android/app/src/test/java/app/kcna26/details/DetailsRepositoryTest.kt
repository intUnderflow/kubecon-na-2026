package app.kcna26.details

import app.kcna26.TestData
import app.kcna26.data.SpeakerTagline
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

@OptIn(ExperimentalCoroutinesApi::class)
class DetailsRepositoryTest {

    private val dir: File = Files.createTempDirectory("kcna26-details").toFile()
    private var nowMs = 1_000_000L

    /** Scripted fetcher: answers from [script] (last answer repeats) and counts calls per id. */
    private class FakeFetcher(vararg script: FetchResult) : DetailsFetcher {
        val answers = ArrayDeque(script.toList())
        val calls = ArrayList<String>()
        override fun fetch(sessionId: String): FetchResult {
            calls += sessionId
            return if (answers.size > 1) answers.removeFirst() else answers.first()
        }
    }

    private fun TestScope.repo(fetcher: DetailsFetcher) = DetailsRepository(
        repo = TestData.repo,
        cacheDir = dir,
        fetcher = fetcher,
        ioDispatcher = StandardTestDispatcher(testScheduler),
        elapsedMillis = { nowMs },
    )

    @After
    fun cleanUp() {
        dir.deleteRecursively()
    }

    // A KubeCon session that details.json lacks.
    private val missing = "1302802"
    private val sampleMd = SessionizeSamples.byId.getValue("1289660")

    @Test
    fun bundledDetailsNeedNoFetch() = runTest {
        val f = FakeFetcher(FetchResult.Failed("must not be called"))
        val r = repo(f)
        val res = r.load("1289660") as DetailsResult.Found
        assertEquals(DetailInfo.Source.BUNDLED, res.info.source)
        assertTrue(res.info.description!!.isNotBlank())
        assertEquals(
            listOf("Lucy Sweet", "Ryan Hallisey", "Filip Křepinský"),
            res.info.speakers.map { it.name },
        )
        assertEquals("Member of Technical Staff at Anthropic", res.info.speakers[0].tagline)
        assertTrue(f.calls.isEmpty())
        // Now in memory: peek is synchronous.
        assertEquals(res.info, r.peek("1289660"))
        assertEquals(res.info, r.get("1289660"))
    }

    @Test
    fun peekNeedsNoIoAndKnowsBundledOnceWarmed() = runTest {
        val r = repo(FakeFetcher(FetchResult.NotFound))
        assertNull(r.peekResult("1202489"))
        r.warmBundled()
        val info = r.peek("1202489")
        assertNotNull(info)
        assertEquals(DetailInfo.Source.BUNDLED, info!!.source)
        assertEquals(listOf(SpeakerTagline("Maciej Wal", "Cybersecurity Platform Architect, The Cybersecurity Center at MSU Denver")), info.speakers)
    }

    @Test
    fun maintainerSummitComesFromScheduleJsonWithoutFetching() = runTest {
        val f = FakeFetcher(FetchResult.Failed("must not be called"))
        val r = repo(f)

        // Synchronous: no warm-up needed.
        val talk = r.peek("m1290687")!!
        assertEquals(DetailInfo.Source.SUMMIT, talk.source)
        assertTrue(talk.description!!.isNotBlank())
        assertTrue(talk.slidesUrl!!.startsWith("https://sessionize.com/download/"))
        assertNull(talk.link)
        assertTrue(talk.speakers.isEmpty())

        // Unconference sessions (Sunday updates): their own description, and no "See and vote" link
        // (the unconference feature went once voting was over). The GitHub discussion is on the Session.
        val unconf = r.peek("m1318474")!!
        assertTrue(unconf.description!!.startsWith("containerd has had over 100 times more vulnerability reports"))
        assertNull(unconf.link)
        assertNull(unconf.linkText)
        for (id in listOf("m1318479", "m1318483")) {
            val info = r.peek(id)!!
            assertNull(id, info.link)
            assertFalse(id, info.description!!.contains("vote on GitHub"))
        }

        // A summit break: found, but nothing to describe.
        val coffee = r.load("m1318416") as DetailsResult.Found
        assertNull(coffee.info.description)
        assertTrue(f.calls.isEmpty())
    }

    @Test
    fun liveFetchIsParsedCachedOnDiskAndServedOfflineLater() = runTest {
        val f = FakeFetcher(FetchResult.Ok(sampleMd))
        val first = repo(f).load(missing) as DetailsResult.Found
        assertEquals(DetailInfo.Source.LIVE, first.info.source)
        assertEquals(TestData.repo.details.getValue("1289660").speakers, first.info.speakers)
        assertEquals(listOf(missing), f.calls)
        assertTrue(File(dir, "$missing.json").isFile)

        // A new process, offline: the disk cache answers.
        val offline = FakeFetcher(FetchResult.Failed("offline"))
        val second = repo(offline).load(missing) as DetailsResult.Found
        assertEquals(DetailInfo.Source.DISK_CACHE, second.info.source)
        assertEquals(first.info.description, second.info.description)
        assertEquals(first.info.speakers, second.info.speakers)
        assertTrue(offline.calls.isEmpty())
    }

    @Test
    fun failureIsQuietAndBacksOffInsteadOfStormingRetries() = runTest {
        val f = FakeFetcher(FetchResult.Failed("offline"), FetchResult.Failed("offline"), FetchResult.Ok(sampleMd))
        val r = repo(f)
        assertEquals(DetailsResult.Unavailable, r.load(missing))
        assertNull(r.get(missing))
        assertEquals(DetailsResult.Unavailable, r.load(missing))
        assertEquals(DetailsResult.Unavailable, r.peekResult(missing))
        assertEquals(1, f.calls.size)

        nowMs += DetailsRepository.FAIL_BACKOFF_MS - 1
        assertEquals(DetailsResult.Unavailable, r.load(missing))
        assertEquals(1, f.calls.size)

        nowMs += 1
        assertEquals(DetailsResult.Unavailable, r.load(missing))
        assertEquals(2, f.calls.size)

        nowMs += DetailsRepository.FAIL_BACKOFF_MS
        val ok = r.load(missing) as DetailsResult.Found
        assertEquals(DetailInfo.Source.LIVE, ok.info.source)
        assertEquals(3, f.calls.size)
        assertEquals(ok, r.peekResult(missing))
    }

    @Test
    fun concurrentRequestsShareOneFetch() = runTest {
        val f = FakeFetcher(FetchResult.Ok(sampleMd))
        val r = repo(f)
        val results = (1..5).map { async { r.load(missing) } }.awaitAll()
        assertTrue(results.all { it is DetailsResult.Found })
        assertEquals(1, f.calls.size)
    }

    @Test
    fun emptyAnswersAndNotFoundShowNothingAndAreNotRefetched() = runTest {
        val f = FakeFetcher(FetchResult.Ok(SessionizeSamples.byId.getValue("1342434").replace("## Description", "## Notes")))
        val r = repo(f)
        // "Closing Remarks": Sessionize has no description and no speakers.
        assertEquals(DetailsResult.None, r.load("1302802"))
        assertEquals(DetailsResult.None, r.load("1302802"))
        assertEquals(1, f.calls.size)
        assertFalse(File(dir, "1302802.json").exists())

        val nf = FakeFetcher(FetchResult.NotFound)
        val r2 = repo(nf)
        assertEquals(DetailsResult.None, r2.load("1370503"))
        assertEquals(DetailsResult.None, r2.load("1370503"))
        assertEquals(1, nf.calls.size)
    }

    @Test
    fun coLocatedDetailsAreBundledAndNeverFetchedOrCached() = runTest {
        val f = FakeFetcher(FetchResult.Ok(sampleMd))
        val r = repo(f)
        // Jiazhou Gao's Cloud Native AI + Inference Day talk: description and taglines from colocated_details.json.
        val res = r.load("1245135") as DetailsResult.Found
        assertEquals(DetailInfo.Source.BUNDLED, res.info.source)
        assertTrue(res.info.description!!.startsWith("As LLM inference moves from demos to production"))
        assertEquals(SpeakerTagline("Jiazhou Gao", "Member of Technical Staff at Anthropic"), res.info.speakers[0])
        // Slides come from the session; a lunch carries its menu.
        val withSlides = TestData.repo.sessions.first { it.isColocated && it.slidesUrl != null }
        assertEquals(withSlides.slidesUrl, (r.load(withSlides.id) as DetailsResult.Found).info.slidesUrl)
        assertTrue((r.load("1309415") as DetailsResult.Found).info.description!!.contains("Lunch Menu"))
        assertTrue(f.calls.isEmpty())
        assertFalse(dir.exists() && dir.list()!!.isNotEmpty())
    }

    @Test
    fun aCoLocatedSessionWithoutBundledDetailsIsNoneNotFetched() = runTest {
        // Their ids are plain digits but belong to another Sessionize event: never ask the main one.
        val details = app.kcna26.data.Repository.COLOCATED_DETAILS
        val text = TestData.text(details).replace("\"1245135\": {", "\"x1245135\": {")
        assertTrue(text != TestData.text(details))
        val base = app.kcna26.data.Repository.load { name ->
            if (name == details) text.byteInputStream() else File(TestData.assetsDir, name).inputStream()
        }
        assertFalse("1245135" in base.details)
        val f = FakeFetcher(FetchResult.Ok(sampleMd))
        val r = DetailsRepository(base, dir, f, StandardTestDispatcher(testScheduler), { nowMs })
        assertEquals(DetailsResult.None, r.load("1245135"))
        assertTrue(DetailsRepository.isKubeConId("1245135"))
        assertTrue(f.calls.isEmpty())
        // A stray cache file for it is ignored too.
        dir.mkdirs()
        File(dir, "1245135.json").writeText("{\"description\":\"stale\",\"speakers\":[]}")
        assertEquals(DetailsResult.None, DetailsRepository(base, dir, f, StandardTestDispatcher(testScheduler), { nowMs }).load("1245135"))
    }

    @Test
    fun unknownSessionsAreNoneWithoutAnyFetch() = runTest {
        val f = FakeFetcher(FetchResult.Ok(sampleMd))
        val r = repo(f)
        assertEquals(DetailsResult.None, r.load("999"))
        assertEquals(DetailsResult.None, r.load("m999"))
        assertEquals(DetailsResult.None, r.load("../../etc/passwd"))
        assertTrue(f.calls.isEmpty())
    }

    @Test
    fun corruptCacheFileIsReplaced() = runTest {
        dir.mkdirs()
        File(dir, "$missing.json").writeText("{not json")
        val f = FakeFetcher(FetchResult.Ok(sampleMd))
        val res = repo(f).load(missing) as DetailsResult.Found
        assertEquals(DetailInfo.Source.LIVE, res.info.source)
        assertEquals(1, f.calls.size)
        val again = repo(FakeFetcher(FetchResult.Failed("offline"))).load(missing) as DetailsResult.Found
        assertEquals(DetailInfo.Source.DISK_CACHE, again.info.source)
    }

    @Test
    fun aThrowingFetcherNeverCrashes() = runTest {
        val r = repo { throw IllegalStateException("boom") }
        assertEquals(DetailsResult.Unavailable, r.load(missing))
    }

    @Test
    fun onlyPlainNumericIdsAreFetchable() {
        assertTrue(DetailsRepository.isKubeConId("1302802"))
        assertFalse(DetailsRepository.isKubeConId("m1318474"))
        assertFalse(DetailsRepository.isKubeConId(""))
        assertFalse(DetailsRepository.isKubeConId("12/../3"))
    }
}
