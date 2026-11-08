package app.kcna26.sync

import app.kcna26.BuildConfig
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI

/** Outcome of one HTTP GET. */
sealed interface HttpResult {
    /** 2xx. [body] is at most maxBytes + 1 bytes (one more means "too big"). */
    class Ok(val body: ByteArray, val etag: String?) : HttpResult

    /** 304: the If-None-Match ETag still matches. */
    data object NotModified : HttpResult

    /** Offline, timeout, 404 (repo not published yet), 5xx, …: try again later. */
    data class Failed(val reason: String) : HttpResult
}

/** Blocking GET. [DataSync] calls it on its IO dispatcher; tests pass a fake. */
fun interface DataFetcher {
    fun get(url: String, ifNoneMatch: String?, maxBytes: Long): HttpResult
}

/** [DataFetcher] over HttpURLConnection with short timeouts. Never throws. */
class HttpDataFetcher(
    private val connectTimeoutMs: Int = 5_000,
    private val readTimeoutMs: Int = 10_000,
) : DataFetcher {

    override fun get(url: String, ifNoneMatch: String?, maxBytes: Long): HttpResult {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URI(url).toURL().openConnection() as HttpURLConnection).apply {
                connectTimeout = connectTimeoutMs
                readTimeout = readTimeoutMs
                instanceFollowRedirects = true
                useCaches = false
                setRequestProperty("User-Agent", USER_AGENT)
                if (ifNoneMatch != null) setRequestProperty("If-None-Match", ifNoneMatch)
            }
            when (val code = conn.responseCode) {
                HttpURLConnection.HTTP_NOT_MODIFIED -> HttpResult.NotModified
                in 200..299 -> HttpResult.Ok(conn.inputStream.use { readCapped(it, maxBytes + 1) }, conn.getHeaderField("ETag"))
                else -> HttpResult.Failed("HTTP $code")
            }
        } catch (e: IOException) {
            HttpResult.Failed(e.javaClass.simpleName + ": " + e.message)
        } catch (e: RuntimeException) {
            // SecurityException, IllegalArgumentException (bad URL), …
            HttpResult.Failed(e.javaClass.simpleName + ": " + e.message)
        } finally {
            conn?.disconnect()
        }
    }

    private fun readCapped(input: InputStream, max: Long): ByteArray {
        val out = ByteArrayOutputStream()
        val buf = ByteArray(16 * 1024)
        while (out.size() < max) {
            val n = input.read(buf, 0, minOf(buf.size.toLong(), max - out.size()).toInt())
            if (n < 0) break
            out.write(buf, 0, n)
        }
        return out.toByteArray()
    }

    companion object {
        val USER_AGENT = "kcna26-android/${BuildConfig.VERSION_NAME} (+https://github.com/intUnderflow/kubecon-na-2026)"
    }
}
