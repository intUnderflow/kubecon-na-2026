package app.kcna26.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.kcna26.LocalAppGraph
import app.kcna26.sync.ActiveData
import app.kcna26.sync.SyncOutcome
import app.kcna26.sync.SyncStatus
import app.kcna26.theme.AppTheme
import app.kcna26.theme.CapsText
import app.kcna26.theme.Dimens
import app.kcna26.time.TimeFormat
import app.kcna26.time.ZONE
import java.time.Duration
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Its own small Settings section: "SCHEDULE DATA" (a heading), then "Updated Nov 8, 2:15 PM ·
 * Check now", with the source (bundled or GitHub) underneath. Failures are never shown: the row
 * just stays as it was.
 */
@Composable
internal fun DataSourceRow(modifier: Modifier = Modifier) {
    val sync = LocalAppGraph.current.dataSync
    val active by sync.active.collectAsStateWithLifecycle()
    val status by sync.status.collectAsStateWithLifecycle()
    val a = active ?: return
    val c = AppTheme.colors
    val t = AppTheme.type
    Column(modifier.fillMaxWidth()) {
        CapsText("Schedule data", t.sectionLabel, Modifier.semantics { heading() }, color = c.muted)
        Row(
            Modifier
                .fillMaxWidth()
                .padding(top = 4.dp)
                .heightIn(min = Dimens.touchTarget),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(DataSourceText.updated(a.updatedAt, a.version), style = t.small, color = c.ink, modifier = Modifier.weight(1f, fill = false))
            Text(" ·", style = t.small, color = c.muted)
            TextButton(
                onClick = sync::checkInBackground,
                enabled = !status.checking,
                colors = ButtonDefaults.textButtonColors(contentColor = c.you, disabledContentColor = c.muted),
                contentPadding = PaddingValues(horizontal = 8.dp),
                modifier = Modifier.heightIn(min = Dimens.touchTarget),
            ) {
                Text("Check now", style = t.button)
            }
        }
        Text(
            // Wall clock, like SyncStatus.lastCheckedAt (not the app clock, which may be faked).
            DataSourceText.source(a.source, status, Instant.now()),
            style = t.tiny,
            color = c.muted,
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
        )
    }
}

/** Text of [DataSourceRow] (pure, unit-tested). Times are Denver time, like the rest of the app. */
internal object DataSourceText {
    private val DATE = DateTimeFormatter.ofPattern("MMM d", Locale.US)

    /** "Just now" lasts this long after a download; then it says when. */
    private val JUST_NOW: Duration = Duration.ofMinutes(2)

    /** "Updated Nov 8, 2:15 PM": when the data was published (or its version when the manifest has no time). */
    fun updated(at: Instant?, version: Int): String =
        if (at != null) "Updated ${dateTime(at)}" else "Version $version"

    /**
     * "Bundled with the app" / "From GitHub", plus "Checking…", "Up to date", or when this
     * phone downloaded it: "Downloaded just now", "Downloaded at 9:00 AM" (today) or
     * "Downloaded Nov 8, 9:00 AM".
     */
    fun source(source: ActiveData.Source, status: SyncStatus, now: Instant): String {
        val from = when (source) {
            ActiveData.Source.BUNDLED -> "Bundled with the app"
            ActiveData.Source.GITHUB -> "From GitHub"
        }
        val at = status.lastCheckedAt
        val state = when {
            status.checking -> "Checking…"
            status.last is SyncOutcome.Updated -> when {
                at == null || Duration.between(at, now) < JUST_NOW -> "Downloaded just now"
                at.atZone(ZONE).toLocalDate() == now.atZone(ZONE).toLocalDate() -> "Downloaded at ${TimeFormat.hma(at)}"
                else -> "Downloaded ${dateTime(at)}"
            }
            status.last is SyncOutcome.NotModified || status.last is SyncOutcome.NotNewer -> "Up to date"
            else -> null // never checked, or it failed: say nothing
        }
        return if (state != null) "$from · $state" else from
    }

    private fun dateTime(at: Instant): String = "${DATE.format(at.atZone(ZONE))}, ${TimeFormat.hma(at)}"
}
