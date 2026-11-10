package app.kcna26.sync

import app.kcna26.TestData
import app.kcna26.data.Repository
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** The APK's assets/manifest.json must describe the bundled files (run scripts/make_manifest.py after editing data). */
class BundledManifestTest {
    private val manifest = DataManifest.parse(File(TestData.assetsDir, DataManifest.FILE).readBytes())

    @Test
    fun bundledManifestMatchesTheBundledFiles() {
        assertEquals(emptyList<String>(), manifest.problems())
        for ((name, e) in manifest.files) {
            val b = File(TestData.assetsDir, name).readBytes()
            assertEquals("$name size (run scripts/make_manifest.py)", e.bytes, b.size.toLong())
            assertEquals("$name sha256 (run scripts/make_manifest.py)", e.sha256, DataManifest.sha256(b))
        }
        assertTrue(manifest.updatedInstant != null)
    }

    @Test
    fun manifestCoversEveryFileTheAppLoads() {
        val loaded = setOf(
            Repository.SCHEDULE, Repository.ROOMS, Repository.WAYFINDING, Repository.VENUE, Repository.DETAILS,
            Repository.SUMMIT_DETAILS, Repository.COLOCATED, Repository.COLOCATED_DETAILS,
        )
        assertEquals(loaded, manifest.files.keys)
        assertFalse(Repository.TEST_VECTORS in manifest.files)
    }

    @Test
    fun publishedManifestIsTheBundledOne() {
        val published = listOf(File("../../data"), File("../data")).map { File(it, DataManifest.FILE) }.firstOrNull { it.isFile } ?: return
        assertEquals(manifest, DataManifest.parse(published.readBytes()))
    }
}
