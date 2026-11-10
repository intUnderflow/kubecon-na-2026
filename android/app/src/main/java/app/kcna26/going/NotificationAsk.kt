package app.kcna26.going

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import app.kcna26.AppGraph
import app.kcna26.KcnaApp
import app.kcna26.LocalAppGraph
import app.kcna26.appGraph
import app.kcna26.data.Room
import app.kcna26.data.Session
import app.kcna26.reminders.ReminderNotifier
import app.kcna26.reminders.ReminderPlanner
import app.kcna26.settings.SettingsStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * POST_NOTIFICATIONS is asked for in context, not at launch: the first time the user stars
 * a session, picks a name in "I’m speaking as" (Settings or the first-run picker), or turns
 * the "Going" reminders on; or, when reminders are already planned (a talk of mine or a
 * star still to come, e.g. the default speaker) and the app has never asked, when the
 * activity starts. MainActivity owns the request launcher and asks at most once
 * (`settings.notificationPermissionAsked`); after that, a refused permission shows the
 * inline [rememberNotificationsBlocked] hint with a button to the app's notification settings.
 */
object NotificationAsk {

    private val _asking = MutableStateFlow(false)

    /** True while the system permission dialog is up (between [requestStarted] and [requestFinished]). */
    val asking: StateFlow<Boolean> = _asking.asStateFlow()

    /** MainActivity: the permission dialog is about to show. */
    fun requestStarted() {
        _asking.value = true
    }

    /** MainActivity: the permission dialog has answered (granted or not). */
    fun requestFinished() {
        _asking.value = false
    }

    /**
     * Emits each time the user does something that needs notifications. Only changes made
     * after collection starts count (the current values are skipped).
     */
    fun triggers(settings: SettingsStore, going: GoingStore): Flow<Unit> = merge(
        going.ids.drop(1).filter { it.isNotEmpty() }.map { },
        settings.speakingAs.drop(1).filter { it != null }.map { },
        going.remindMinutes.drop(1).filter { it > 0 }.map { },
    )

    /**
     * True when at least one reminder is planned from [now] on (my talks under [me], or a
     * star in [going] with [goingMinutes] on): the app has something to deliver, so a
     * pending permission is worth asking for at start.
     */
    fun remindersToCome(
        sessions: List<Session>,
        rooms: Map<String, Room>,
        me: String?,
        now: Instant,
        going: Set<String>,
        goingMinutes: Int,
    ): Boolean = ReminderPlanner.plan(sessions, rooms, me, now, going, goingMinutes).isNotEmpty()

    /**
     * Calls [ask] (on the main thread) for every [triggers] emission while [activity] is
     * started, and once per start when reminders are already planned but the app has never
     * asked ([remindersToCome]).
     */
    fun watch(activity: ComponentActivity, ask: () -> Unit) {
        val graph = activity.appGraph
        activity.lifecycleScope.launch {
            activity.repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch { if (remindersWaiting(activity, graph)) ask() }
                triggers(graph.settings, graph.going).collect { ask() }
            }
        }
    }

    private suspend fun remindersWaiting(context: Context, graph: AppGraph): Boolean {
        if (hasPermission(context) || graph.settings.notificationPermissionAsked) return false
        val repo = graph.awaitRepository()
        val going = graph.going
        return remindersToCome(
            repo.sessions, repo.rooms, graph.settings.speakingAs.value, graph.clock.now(),
            going.ids.value, going.remindMinutes.value,
        )
    }

    /**
     * Why reminders on one channel can't be shown, as far as the user should be told:
     * [APP] the permission was refused or the app's notifications are off; [CHANNEL] only
     * that channel is off (a deliberate choice, so only Settings mentions it).
     */
    enum class Block { NONE, APP, CHANNEL }

    /**
     * Pure rule behind [blocked]. Nothing is said while the system dialog is up ([asking]),
     * or on Android 13+ while the contextual ask is still to come ([needsRuntimeAsk], not [asked]).
     */
    fun blockOf(
        permission: Boolean,
        appOn: Boolean,
        channelOn: Boolean,
        needsRuntimeAsk: Boolean,
        asked: Boolean,
        asking: Boolean,
    ): Block = when {
        asking -> Block.NONE
        !permission -> if (needsRuntimeAsk && !asked) Block.NONE else Block.APP
        !appOn -> Block.APP
        !channelOn -> Block.CHANNEL
        else -> Block.NONE
    }

    /** [blockOf] for [channelId] on this device, now. */
    fun blocked(context: Context, settings: SettingsStore, channelId: String): Block {
        val nm = NotificationManagerCompat.from(context)
        val channel = nm.getNotificationChannelCompat(channelId)
        return blockOf(
            permission = hasPermission(context),
            appOn = nm.areNotificationsEnabled(),
            channelOn = channel == null || channel.importance != NotificationManagerCompat.IMPORTANCE_NONE,
            needsRuntimeAsk = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
            asked = settings.notificationPermissionAsked,
            asking = _asking.value,
        )
    }

    private fun hasPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /**
     * Opens the system notification settings: the [channelId] page when only that channel
     * is off, otherwise the app's page (falling back to the app info screen).
     */
    fun openSettings(context: Context, channelId: String) {
        val pkg = context.packageName
        val appOn = hasPermission(context) && NotificationManagerCompat.from(context).areNotificationsEnabled()
        val intent = if (appOn) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                .putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
        } else {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
        }
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: ActivityNotFoundException) {
            try {
                context.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", pkg, null))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (e2: ActivityNotFoundException) {
                Log.w(KcnaApp.TAG, "going: no notification settings screen", e2)
            }
        }
    }
}

/**
 * [NotificationAsk.blocked] for [channelId], re-checked whenever the screen resumes (back
 * from the permission dialog or the system settings) and when the dialog opens or answers.
 */
@Composable
fun rememberNotificationsBlocked(channelId: String = ReminderNotifier.GOING_CHANNEL_ID): NotificationAsk.Block {
    val context = LocalContext.current
    val settings = LocalAppGraph.current.settings
    val asking by NotificationAsk.asking.collectAsStateWithLifecycle()
    var blocked by remember(channelId, asking) { mutableStateOf(NotificationAsk.blocked(context, settings, channelId)) }
    LifecycleResumeEffect(channelId, asking) {
        blocked = NotificationAsk.blocked(context, settings, channelId)
        onPauseOrDispose { }
    }
    return blocked
}
