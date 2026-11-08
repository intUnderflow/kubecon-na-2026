package app.kcna26

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.View
import android.view.ViewTreeObserver
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import app.kcna26.going.NotificationAsk
import app.kcna26.nav.AppNav
import app.kcna26.nav.NavViewModel
import app.kcna26.reminders.ReminderScheduler
import app.kcna26.theme.AppTheme
import app.kcna26.theme.KcnaTheme
import app.kcna26.time.FakeableClock
import app.kcna26.ui.adaptive.LocalWidthClass
import app.kcna26.ui.adaptive.currentWidthClass
import app.kcna26.ui.settings.FirstRunSpeakerSheet

/**
 * The only activity (singleTop). Never locks orientation; fold/unfold recreates
 * it and all navigation state is restored from [NavViewModel]'s SavedStateHandle.
 *
 * Intents:
 * - [directionsIntent] (reminder notifications): opens Directions for a session.
 * - Debug builds: `--es fakeNow 2026-11-11T09:00:00-07:00` sets the fake clock,
 *   `--es fakeNow clear` resets it (see FakeableClock).
 */
class MainActivity : ComponentActivity() {

    private val nav: NavViewModel by viewModels()

    private val requestNotifications =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            NotificationAsk.requestFinished()
            if (granted) ReminderScheduler.reschedule(this)
        }

    private val app: KcnaApp get() = application as KcnaApp

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val fromHistory = intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        // Only a fresh launch handles its intent: a recreated activity (fold/unfold,
        // process restore) keeps the intent but must not re-apply it.
        if (savedInstanceState == null && !fromHistory) handleIntent(intent)

        keepSplashUntilDataLoaded()

        if (savedInstanceState == null) {
            ReminderScheduler.reschedule(this)
        }
        // POST_NOTIFICATIONS is asked in context (first star, name picked, reminders on, or reminders
        // already planned when never asked), not unconditionally at launch.
        NotificationAsk.watch(this) { askForNotificationsOnce() }

        setContent { Root(app, nav) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        intent ?: return
        if (BuildConfig.DEBUG) {
            intent.getStringExtra(FakeableClock.EXTRA_FAKE_NOW)?.let { arg ->
                val ok = app.fakeableClock.applyFakeNowArg(arg)
                Log.i(KcnaApp.TAG, "fakeNow=$arg applied=$ok now=${app.clock.now()}")
            }
        }
        if (intent.action == ACTION_OPEN_DIRECTIONS) {
            intent.getStringExtra(EXTRA_SESSION_ID)?.let { nav.openDirectionsFromNotification(it) }
        }
    }

    private fun askForNotificationsOnce() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted || app.settings.notificationPermissionAsked) return
        app.settings.notificationPermissionAsked = true
        NotificationAsk.requestStarted()
        requestNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
    }

    /** Holds the system splash screen until the bundled JSON is parsed (usually a few hundred ms on a cold start). */
    private fun keepSplashUntilDataLoaded() {
        if (app.isRepositoryLoaded) return
        val content: View = findViewById(android.R.id.content)
        val started = System.nanoTime()
        content.viewTreeObserver.addOnPreDrawListener(object : ViewTreeObserver.OnPreDrawListener {
            override fun onPreDraw(): Boolean {
                val timedOut = System.nanoTime() - started > 5_000_000_000L
                return if (app.isRepositoryLoaded || timedOut) {
                    content.viewTreeObserver.removeOnPreDrawListener(this)
                    true
                } else {
                    false
                }
            }
        })
    }

    companion object {
        /** Action of [directionsIntent]. */
        const val ACTION_OPEN_DIRECTIONS = "app.kcna26.action.OPEN_DIRECTIONS"

        /** String extra: session id. */
        const val EXTRA_SESSION_ID = "app.kcna26.extra.SESSION_ID"

        /**
         * Intent that opens Directions for [sessionId] (for reminder notifications).
         * Its data URI is unique per session, so PendingIntents for different sessions
         * don't collide. Wrap with PendingIntent.getActivity(..., FLAG_IMMUTABLE or FLAG_UPDATE_CURRENT).
         */
        fun directionsIntent(context: Context, sessionId: String): Intent =
            Intent(context, MainActivity::class.java)
                .setAction(ACTION_OPEN_DIRECTIONS)
                .setData(Uri.parse("kcna26://directions/" + Uri.encode(sessionId)))
                .putExtra(EXTRA_SESSION_ID, sessionId)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
}

@Composable
private fun Root(app: KcnaApp, nav: NavViewModel) {
    KcnaTheme {
        var ready by remember { mutableStateOf(app.isRepositoryLoaded) }
        var error by remember { mutableStateOf<String?>(null) }
        if (!ready) {
            LaunchedEffect(Unit) {
                try {
                    app.awaitRepository()
                    ready = true
                } catch (e: Exception) {
                    Log.e(KcnaApp.TAG, "Repository failed to load", e)
                    error = e.toString()
                }
            }
        }
        val widthClass = currentWidthClass()
        Surface(color = AppTheme.colors.bg, contentColor = AppTheme.colors.ink, modifier = Modifier.fillMaxSize()) {
            CompositionLocalProvider(LocalAppGraph provides app, LocalWidthClass provides widthClass) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal)),
                ) {
                    val err = error
                    when {
                        ready -> {
                            AppNav(nav)
                            FirstRunSpeakerSheet() // fresh installs: "Speaking at KubeCon? Pick your name"
                        }
                        err != null -> Text(
                            "Couldn’t load the schedule data: $err",
                            modifier = Modifier
                                .windowInsetsPadding(WindowInsets.safeDrawing)
                                .padding(24.dp),
                        )
                    }
                }
            }
        }
    }
}
