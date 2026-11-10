package app.kcna26.sync

import app.kcna26.data.Repository
import kotlinx.serialization.Serializable
import java.security.MessageDigest
import java.time.Instant

/**
 * data/manifest.json (written by scripts/make_manifest.py). The APK bundles one in its assets,
 * and the published copy on GitHub says which data set is newest:
 *
 * ```
 * {"version": 7, "updatedAt": "2026-11-08T21:15:00Z",
 *  "files": {"schedule.json": {"sha256": "…", "bytes": 364257}, …}}
 * ```
 */
@Serializable
data class DataManifest(
    /** Goes up by one whenever any file changes. 0 means "unknown" (no manifest). */
    val version: Int = 0,
    /** ISO-8601 instant, e.g. "2026-11-08T21:15:00Z". */
    val updatedAt: String = "",
    val files: Map<String, ManifestEntry> = emptyMap(),
) {
    val updatedInstant: Instant? get() = runCatching { Instant.parse(updatedAt) }.getOrNull()

    /**
     * Why this manifest can't describe a usable data set (empty = fine). [required]: file names it
     * must list; DataSync passes the bundled manifest's, which make_manifest.py writes from the
     * same data/ folder the app's assets come from (so there is no list to keep in step here).
     */
    fun problems(required: Collection<String> = emptyList()): List<String> {
        val out = mutableListOf<String>()
        if (version < 1) out += "version $version"
        for (name in required) if (name !in files) out += "missing $name"
        var total = 0L
        for ((name, e) in files) {
            if (!isSafeName(name)) out += "bad file name '$name'"
            if (!SHA256_HEX.matches(e.sha256)) out += "$name: bad sha256"
            if (e.bytes !in 1..MAX_FILE_BYTES) out += "$name: bad size ${e.bytes}"
            total += e.bytes
        }
        if (total > MAX_TOTAL_BYTES) out += "total size $total"
        return out
    }

    companion object {
        const val FILE = "manifest.json"

        const val MAX_FILE_BYTES = 8L * 1024 * 1024
        const val MAX_TOTAL_BYTES = 32L * 1024 * 1024

        private val SHA256_HEX = Regex("^[0-9a-f]{64}$")
        private val SAFE_NAME = Regex("^[a-z0-9][a-z0-9_-]*\\.json$")

        /** A plain "name.json": no paths, never the manifest or the test vectors. */
        fun isSafeName(name: String): Boolean =
            SAFE_NAME.matches(name) && name != FILE && name != Repository.TEST_VECTORS

        fun parse(bytes: ByteArray): DataManifest =
            Repository.json.decodeFromString(serializer(), bytes.toString(Charsets.UTF_8))

        fun sha256(bytes: ByteArray): String =
            MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    }
}

@Serializable
data class ManifestEntry(val sha256: String, val bytes: Long)
