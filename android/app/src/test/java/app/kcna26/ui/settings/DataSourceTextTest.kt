package app.kcna26.ui.settings

import app.kcna26.sync.ActiveData
import app.kcna26.sync.SyncOutcome
import app.kcna26.sync.SyncStatus
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Instant

class DataSourceTextTest {
    private val now = Instant.parse("2026-11-08T18:30:00Z") // 11:30 AM in Denver

    @Test
    fun updatedLineIsDenverTime() {
        assertEquals("Updated Nov 8, 2:15 PM", DataSourceText.updated(Instant.parse("2026-11-08T21:15:00Z"), 3))
        assertEquals("Version 3", DataSourceText.updated(null, 3))
    }

    @Test
    fun sourceLineNeverShowsErrors() {
        val b = ActiveData.Source.BUNDLED
        assertEquals("Bundled with the app", DataSourceText.source(b, SyncStatus(), now))
        assertEquals("Bundled with the app · Checking…", DataSourceText.source(b, SyncStatus(checking = true), now))
        assertEquals("Bundled with the app · Up to date", DataSourceText.source(b, SyncStatus(last = SyncOutcome.NotModified), now))
        assertEquals("Bundled with the app", DataSourceText.source(b, SyncStatus(last = SyncOutcome.Failed("HTTP 404")), now))
        assertEquals("Bundled with the app", DataSourceText.source(b, SyncStatus(last = SyncOutcome.Rejected("bad")), now))
    }

    @Test
    fun justNowOnlyRightAfterTheDownload() {
        val g = ActiveData.Source.GITHUB
        fun downloaded(at: String) = SyncStatus(last = SyncOutcome.Updated(2), lastCheckedAt = Instant.parse(at))
        assertEquals("From GitHub · Downloaded just now", DataSourceText.source(g, downloaded("2026-11-08T18:29:00Z"), now))
        // Opened Settings hours later in the same process: say when.
        assertEquals("From GitHub · Downloaded at 9:00 AM", DataSourceText.source(g, downloaded("2026-11-08T16:00:00Z"), now))
        assertEquals("From GitHub · Downloaded Nov 7, 9:00 AM", DataSourceText.source(g, downloaded("2026-11-07T16:00:00Z"), now))
    }
}
