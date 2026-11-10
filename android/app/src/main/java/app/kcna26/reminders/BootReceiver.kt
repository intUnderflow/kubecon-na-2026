package app.kcna26.reminders

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-arms the reminders after a reboot or an app update (alarms don't survive either).
 * Declared in the manifest as `.reminders.BootReceiver` for BOOT_COMPLETED and
 * MY_PACKAGE_REPLACED. Also handles SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED, so
 * alarms switch to exact as soon as that access is granted, if the manifest lists it.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED,
            -> {
                val app = context.applicationContext
                goAsyncWork(app) { ReminderScheduler.rescheduleNow(app) }
            }
        }
    }
}
