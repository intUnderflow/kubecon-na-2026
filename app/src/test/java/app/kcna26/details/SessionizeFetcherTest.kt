package app.kcna26.details

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionizeFetcherTest {

    @Test
    fun classifiesResponses() {
        val md = "# T\n\n## Description\n\nHi"
        assertEquals(FetchResult.Ok(md), SessionizeFetcher.classify(200, "text/plain; charset=utf-8", md))
        assertEquals(FetchResult.NotFound, SessionizeFetcher.classify(404, "text/html; charset=utf-8", "<!DOCTYPE html>"))
        assertEquals(FetchResult.NotFound, SessionizeFetcher.classify(410, null, ""))
        assertTrue(SessionizeFetcher.classify(500, "text/plain", "") is FetchResult.Failed)
        assertTrue(SessionizeFetcher.classify(429, "text/plain", "") is FetchResult.Failed)
        // A hotel Wi-Fi login page is a failure (retry later), not "no description".
        assertTrue(SessionizeFetcher.classify(200, "text/html", "<html><body>Sign in</body></html>") is FetchResult.Failed)
        assertTrue(SessionizeFetcher.classify(200, null, "  <!doctype html><html>") is FetchResult.Failed)
    }

    @Test
    fun usesTheSessionizeEndpointAndAPoliteUserAgent() {
        assertEquals("https://sessionize.com/api/v2/uo948i5p/view/markdown/session/", SessionizeFetcher.URL_PREFIX)
        assertTrue(SessionizeFetcher.USER_AGENT.startsWith("kubecon-schedule-app/1.0 (personal schedule app"))
    }

    @Test
    fun refusesNonKubeConIdsWithoutNetwork() {
        assertEquals(FetchResult.NotFound, SessionizeFetcher().fetch("m1318474"))
        assertEquals(FetchResult.NotFound, SessionizeFetcher().fetch("../x"))
    }
}
