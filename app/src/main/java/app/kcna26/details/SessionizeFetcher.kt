package app.kcna26.details

import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI

/** Outcome of one live fetch. */
sealed interface FetchResult {
    /** HTTP 2xx with a markdown body. */
    data class Ok(val body: String) : FetchResult

    /** Sessionize has no such session (404/410): nothing to show, not worth retrying soon. */
    data object NotFound : FetchResult

    /** Offline, timeout, server error, or a captive-portal HTML page: try again later. */
    data class Failed(val reason: String) : FetchResult
}

/** Fetches one session's markdown. Blocking: [DetailsRepository] calls it on its IO dispatcher. */
fun interface DetailsFetcher {
    fun fetch(sessionId: String): FetchResult
}

/**
 * Live Sessionize fetch over HttpURLConnection, with the same User-Agent and Accept headers as
 * scripts/fetch_details.py. One attempt per call (the repository decides when to retry).
 */
class SessionizeFetcher(
    private val connectTimeoutMs: Int = 10_000,
    private val readTimeoutMs: Int = 15_000,
) : DetailsFetcher {

    override fun fetch(sessionId: String): FetchResult {
        if (!DetailsRepository.isKubeConId(sessionId)) return FetchResult.NotFound
        var conn: HttpURLConnection? = null
        return try {
            conn = (URI(URL_PREFIX + sessionId).toURL().openConnection() as HttpURLConnection).apply {
                connectTimeout = connectTimeoutMs
                readTimeout = readTimeoutMs
                instanceFollowRedirects = true
                useCaches = false
                setRequestProperty("User-Agent", USER_AGENT)
                setRequestProperty("Accept", ACCEPT)
            }
            val code = conn.responseCode
            val body = if (code in 200..299) conn.inputStream.use { readCapped(it) } else ""
            classify(code, conn.contentType, body)
        } catch (e: IOException) {
            FetchResult.Failed(e.javaClass.simpleName + ": " + e.message)
        } catch (e: RuntimeException) {
            // SecurityException (no INTERNET), IllegalArgumentException, ...: never crash the sheet.
            FetchResult.Failed(e.javaClass.simpleName + ": " + e.message)
        } finally {
            conn?.disconnect()
        }
    }

    companion object {
        const val URL_PREFIX = "https://sessionize.com/api/v2/uo948i5p/view/markdown/session/"

        /** Like scripts/fetch_details.py's UA, so Sessionize sees the same polite client. */
        const val USER_AGENT = "kubecon-schedule-app/1.0 (personal schedule app; Android)"
        const val ACCEPT = "text/markdown, text/plain, */*"

        /** A session page is a few KB; refuse anything absurd. */
        private const val MAX_BYTES = 512 * 1024

        /** Maps an HTTP response to a [FetchResult]. Pure, for tests. */
        fun classify(code: Int, contentType: String?, body: String): FetchResult = when {
            code == 404 || code == 410 -> FetchResult.NotFound
            code !in 200..299 -> FetchResult.Failed("HTTP $code")
            looksLikeHtml(contentType, body) -> FetchResult.Failed("HTML response (captive portal?)")
            else -> FetchResult.Ok(body)
        }

        /** Sessionize serves text/plain markdown; an HTML page means a login wall or captive portal. */
        internal fun looksLikeHtml(contentType: String?, body: String): Boolean {
            if (contentType != null && contentType.contains("html", ignoreCase = true)) return true
            val head = body.trimStart().take(64).lowercase()
            return head.startsWith("<!doctype html") || head.startsWith("<html")
        }

        private fun readCapped(input: InputStream): String {
            val bytes = input.readNBytesCompat(MAX_BYTES)
            return bytes.toString(Charsets.UTF_8) // malformed sequences become U+FFFD, like decode("utf-8", "replace")
        }

        private fun InputStream.readNBytesCompat(max: Int): ByteArray {
            val out = java.io.ByteArrayOutputStream()
            val buf = ByteArray(8192)
            while (out.size() < max) {
                val n = read(buf, 0, minOf(buf.size, max - out.size()))
                if (n < 0) break
                out.write(buf, 0, n)
            }
            return out.toByteArray()
        }
    }
}
