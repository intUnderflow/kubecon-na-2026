package app.kcna26.time

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeParseException

/** All conference times are in this zone (MST, UTC−7 during the event). */
val ZONE: ZoneId = ZoneId.of("America/Denver")

/** Source of "now". Inject it everywhere instead of calling Instant.now(). */
fun interface AppClock {
    fun now(): Instant
}

/** The real wall clock. */
object SystemAppClock : AppClock {
    override fun now(): Instant = Instant.now()
}

/** A clock frozen at [instant] (unit tests). `FixedClock.parse("2026-11-11T09:00:00-07:00")`. */
class FixedClock(var instant: Instant) : AppClock {
    override fun now(): Instant = instant

    companion object {
        fun parse(iso: String): FixedClock = FixedClock(parseFakeNow(iso))
    }
}

/** "Now" in Denver. */
fun AppClock.nowLocal(): ZonedDateTime = now().atZone(ZONE)

/**
 * Converts an instant on this clock's timeline to real `System.currentTimeMillis()`
 * time, e.g. to arm an AlarmManager alarm while a debug fake time is active:
 * `realEpochMillis(talkStart - 10 min)`. Equals `at.toEpochMilli()` on the real clock.
 */
fun AppClock.realEpochMillis(at: Instant): Long =
    at.toEpochMilli() - (now().toEpochMilli() - System.currentTimeMillis())

/**
 * The app's clock: the real clock plus a debug-only offset stored in prefs, so a
 * fake time survives restarts and keeps ticking.
 *
 * Set with `adb shell am start -n app.kcna26/.MainActivity --es fakeNow 2026-11-11T09:00:00-07:00`
 * and reset with `--es fakeNow clear` (MainActivity calls [applyFakeNowArg]; debug builds only).
 */
class FakeableClock(
    private val prefs: SharedPreferences,
    /** False in release builds: the offset is ignored and cannot be set. */
    private val allowFake: Boolean,
) : AppClock {
    private val _offsetMillis = MutableStateFlow(if (allowFake) prefs.getLong(KEY_OFFSET, 0L) else 0L)

    /** Current fake offset (0 = real time). Collect it to react immediately when the fake time changes. */
    val offsetMillis: StateFlow<Long> = _offsetMillis.asStateFlow()

    val isFaked: Boolean get() = _offsetMillis.value != 0L

    override fun now(): Instant = Instant.ofEpochMilli(System.currentTimeMillis() + _offsetMillis.value)

    /** Makes [now] run from [instant] from this moment on. */
    fun setFakeNow(instant: Instant) {
        if (!allowFake) return
        setOffset(instant.toEpochMilli() - System.currentTimeMillis())
    }

    fun clearFakeNow() = setOffset(0L)

    /**
     * Handles the `fakeNow` launch extra: "clear" (or "off"/"none"/"real") resets;
     * otherwise an ISO date-time ("2026-11-11T09:00:00-07:00", "2026-11-11T09:00"
     * as Denver local time, or an instant ending in Z). Returns true if applied.
     */
    fun applyFakeNowArg(arg: String?): Boolean {
        if (!allowFake || arg.isNullOrBlank()) return false
        val a = arg.trim()
        if (a.lowercase() in setOf("clear", "off", "none", "real", "0")) {
            clearFakeNow()
            return true
        }
        return try {
            setFakeNow(parseFakeNow(a))
            true
        } catch (_: DateTimeParseException) {
            false
        }
    }

    private fun setOffset(ms: Long) {
        _offsetMillis.value = ms
        prefs.edit().apply { if (ms == 0L) remove(KEY_OFFSET) else putLong(KEY_OFFSET, ms) }.apply()
    }

    companion object {
        const val PREFS = "kcna26.debug"
        const val KEY_OFFSET = "fakeNowOffsetMs"
        /** Launch extra name for MainActivity. */
        const val EXTRA_FAKE_NOW = "fakeNow"
    }
}

/** Parses an offset date-time, an instant ("…Z") or a Denver local date-time. */
fun parseFakeNow(s: String): Instant =
    try {
        OffsetDateTime.parse(s).toInstant()
    } catch (_: DateTimeParseException) {
        try {
            Instant.parse(s)
        } catch (_: DateTimeParseException) {
            LocalDateTime.parse(s).atZone(ZONE).toInstant()
        }
    }
