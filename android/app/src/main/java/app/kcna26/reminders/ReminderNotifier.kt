package app.kcna26.reminders

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import app.kcna26.KcnaApp
import app.kcna26.MainActivity
import app.kcna26.R

/**
 * The "Your talks" and "Sessions you’re going to" notification channels and the reminder
 * notifications.
 *
 * One notification per session (tag = session id), so the 10-minute reminder replaces
 * the 30-minute one instead of stacking under it.
 */
internal object ReminderNotifier {

    const val CHANNEL_ID = "your_talks"
    private const val CHANNEL_NAME = "Your talks"

    /** Reminders for starred ("Going") sessions, separate so they can be silenced on their own. */
    const val GOING_CHANNEL_ID = "going"
    private const val GOING_CHANNEL_NAME = "Sessions you’ve RSVP’d to"
    private const val NOTIFICATION_ID = 1
    private const val TAG_PREFIX = "talk:"

    /** Creates (or refreshes the names of) the high-importance reminder channels. Idempotent. */
    fun ensureChannel(context: Context) {
        val channels = listOf(
            NotificationChannelCompat.Builder(CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_HIGH)
                .setName(CHANNEL_NAME)
                .build(),
            NotificationChannelCompat.Builder(GOING_CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_HIGH)
                .setName(GOING_CHANNEL_NAME)
                .build(),
        )
        try {
            NotificationManagerCompat.from(context).createNotificationChannelsCompat(channels)
        } catch (e: RuntimeException) {
            Log.w(KcnaApp.TAG, "reminders: can't create the notification channels", e)
        }
    }

    /** The channel for a reminder of [kind]. */
    fun channelFor(kind: ReminderKind): String = if (kind == ReminderKind.GOING) GOING_CHANNEL_ID else CHANNEL_ID

    /** True when a reminder would actually be shown: permission granted, app and [channelId] not blocked. */
    fun canPost(context: Context, channelId: String = CHANNEL_ID): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val nm = NotificationManagerCompat.from(context)
        if (!nm.areNotificationsEnabled()) return false
        val channel = nm.getNotificationChannelCompat(channelId)
        return channel == null || channel.importance != NotificationManagerCompat.IMPORTANCE_NONE
    }

    /**
     * Posts "[title]" / "[text]" for [sessionId] on [channelId]. Tapping opens MainActivity, then
     * Directions for the session ([MainActivity.directionsIntent]). The notification
     * removes itself after [timeoutAfterMs] (the end of the talk). Returns false if it
     * could not be posted.
     */
    fun post(
        context: Context,
        sessionId: String,
        minutesBefore: Int,
        title: String,
        text: String,
        timeoutAfterMs: Long,
        channelId: String = CHANNEL_ID,
    ): Boolean {
        ensureChannel(context)
        if (!canPost(context, channelId)) return false
        val tap = PendingIntent.getActivity(
            context,
            ReminderPlanner.requestCode(sessionId, minutesBefore),
            MainActivity.directionsIntent(context, sessionId),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_pin)
            .setColor(ContextCompat.getColor(context, R.color.kcna_you))
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(tap)
            .setAutoCancel(true)
            .apply { if (timeoutAfterMs > 0) setTimeoutAfter(timeoutAfterMs) }
            .build()
        return try {
            NotificationManagerCompat.from(context).notify(TAG_PREFIX + sessionId, NOTIFICATION_ID, notification)
            true
        } catch (e: SecurityException) {
            Log.w(KcnaApp.TAG, "reminders: notification permission revoked", e)
            false
        }
    }

    /** Session ids of the reminder notifications currently showing. */
    fun shownSessionIds(context: Context): List<String> =
        try {
            context.getSystemService(NotificationManager::class.java)?.activeNotifications.orEmpty()
                .mapNotNull { sbn -> sbn.tag?.takeIf { sbn.id == NOTIFICATION_ID && it.startsWith(TAG_PREFIX) }?.removePrefix(TAG_PREFIX) }
        } catch (e: RuntimeException) {
            emptyList()
        }

    /** Removes the reminder notification for [sessionId], if one is showing. */
    fun cancel(context: Context, sessionId: String) {
        try {
            NotificationManagerCompat.from(context).cancel(TAG_PREFIX + sessionId, NOTIFICATION_ID)
        } catch (e: RuntimeException) {
            Log.w(KcnaApp.TAG, "reminders: can't cancel a notification", e)
        }
    }
}
