package app.kcna26.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.util.Log
import app.kcna26.KcnaApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

/** Only used if the Application isn't [KcnaApp] (never in the app itself). */
private val fallbackScope by lazy { CoroutineScope(SupervisorJob() + Dispatchers.Default) }

/** The process-lifetime scope for reminder work: [KcnaApp.appScope]. */
internal fun reminderScope(context: Context): CoroutineScope =
    (context.applicationContext as? KcnaApp)?.appScope ?: fallbackScope

/** Receivers get about 10 s with goAsync(); stop a little before that. */
private const val RECEIVER_BUDGET_MS = 9_000L

/**
 * Runs [block] off the main thread while keeping the broadcast (and so the process)
 * alive until it finishes, then calls `finish()`. Never throws.
 */
internal fun BroadcastReceiver.goAsyncWork(context: Context, block: suspend () -> Unit) {
    val pending = goAsync()
    reminderScope(context).launch {
        try {
            withTimeout(RECEIVER_BUDGET_MS) { block() }
        } catch (e: Exception) {
            Log.e(KcnaApp.TAG, "reminders: receiver work failed", e)
        } finally {
            pending.finish()
        }
    }
}
