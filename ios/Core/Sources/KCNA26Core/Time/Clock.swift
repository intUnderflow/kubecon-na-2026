import Foundation
import Observation

/// Source of "now". Inject it everywhere instead of calling `Date()` (Kotlin `AppClock`).
protocol AppClock: Sendable {
    func now() -> Date
}

/// The real wall clock (Kotlin `object SystemAppClock`): `SystemAppClock.shared` or `SystemAppClock()`.
struct SystemAppClock: AppClock {
    static let shared = SystemAppClock()

    init() {}

    func now() -> Date { Date() }
}

/// A clock frozen at ``instant`` (unit tests): `try FixedClock.parse("2026-11-11T09:00:00-07:00")`.
/// ``instant`` can be moved; reads and writes are thread-safe.
final class FixedClock: AppClock, @unchecked Sendable {
    private let box: Locked<Date>

    init(_ instant: Date) {
        box = Locked(instant)
    }

    /// The frozen time.
    var instant: Date {
        get { box.value }
        set { box.value = newValue }
    }

    func now() -> Date { instant }

    /// A clock at ``parseFakeNow(_:)`` of `iso`.
    static func parse(_ iso: String) throws -> FixedClock { FixedClock(try parseFakeNow(iso)) }
}

/// A clock backed by a closure (tests that need a moving clock).
struct ClosureAppClock: AppClock {
    let nowProvider: @Sendable () -> Date

    init(_ now: @escaping @Sendable () -> Date) {
        nowProvider = now
    }

    func now() -> Date { nowProvider() }
}

extension AppClock {
    /// "Now" in Denver (Kotlin `nowLocal()`, a ZonedDateTime).
    func nowLocal() -> LocalDateTime { now().localDateTime }

    /// Converts an instant on this clock's timeline to real wall-clock epoch millis, e.g. to
    /// schedule a notification while a debug fake time is active:
    /// `clock.realEpochMillis(talkStart.minusMinutes(10))`. Equals `at.epochMillis` on the
    /// real clock.
    func realEpochMillis(_ at: Date) -> Int64 {
        at.epochMillis - (now().epochMillis - Date().epochMillis)
    }
}

/// The app's clock: the real clock plus a debug-only offset stored in a ``KeyValueStore``
/// ([PREFS] "kcna26.debug", key "fakeNowOffsetMs", as on Android), so a fake time survives
/// restarts and keeps ticking.
///
/// iOS: set it with a launch argument, e.g. `xcrun simctl launch booted <bundle id> -fakeNow
/// 2026-11-11T09:00:00-07:00`, and reset with `-fakeNow clear` (the app calls
/// ``applyFakeNowArg(_:)``; debug builds only).
///
/// Thread-safe (``now()`` is called from any thread) and `Observable`: reading
/// ``offsetMillis`` inside SwiftUI or `withObservationTracking` reacts at once when the fake
/// time changes (Kotlin's `offsetMillis` StateFlow).
final class FakeableClock: AppClock, Observable, @unchecked Sendable {
    static let PREFS = "kcna26.debug"
    static let KEY_OFFSET = "fakeNowOffsetMs"
    /// Launch argument name (Android: the MainActivity extra).
    static let EXTRA_FAKE_NOW = "fakeNow"

    private let prefs: KeyValueStore
    /// False in release builds: the offset is ignored and cannot be set.
    private let allowFake: Bool
    private let offset: Locked<Int64>
    private let registrar = ObservationRegistrar()

    init(_ prefs: KeyValueStore, allowFake: Bool) {
        self.prefs = prefs
        self.allowFake = allowFake
        offset = Locked(allowFake ? (prefs.int64(forKey: FakeableClock.KEY_OFFSET) ?? 0) : 0)
    }

    /// Current fake offset in ms (0 = real time). Observable.
    var offsetMillis: Int64 {
        registrar.access(self, keyPath: \.offsetMillis)
        return offset.value
    }

    var isFaked: Bool { offsetMillis != 0 }

    func now() -> Date { Date(epochMillis: Date().epochMillis + offset.value) }

    /// Makes ``now()`` run from `instant` from this moment on.
    func setFakeNow(_ instant: Date) {
        guard allowFake else { return }
        setOffset(instant.epochMillis - Date().epochMillis)
    }

    func clearFakeNow() { setOffset(0) }

    /// Handles the `fakeNow` launch argument: "clear" (or "off"/"none"/"real"/"0") resets;
    /// otherwise an ISO date-time ("2026-11-11T09:00:00-07:00", "2026-11-11T09:00" as Denver
    /// local time, or an instant ending in Z). Returns true if applied.
    @discardableResult
    func applyFakeNowArg(_ arg: String?) -> Bool {
        guard allowFake, let arg, !arg.isBlank else { return false }
        let a = arg.kotlinTrim()
        if ["clear", "off", "none", "real", "0"].contains(a.lowercased()) {
            clearFakeNow()
            return true
        }
        do {
            setFakeNow(try parseFakeNow(a))
            return true
        } catch {
            return false
        }
    }

    private func setOffset(_ ms: Int64) {
        registrar.withMutation(of: self, keyPath: \.offsetMillis) {
            offset.value = ms
        }
        if ms == 0 {
            prefs.removeValue(forKey: FakeableClock.KEY_OFFSET)
        } else {
            prefs.set(ms, forKey: FakeableClock.KEY_OFFSET)
        }
    }
}

/// Parses an offset date-time, an instant ("…Z") or a Denver local date-time (Kotlin
/// `parseFakeNow`: OffsetDateTime, then Instant, then LocalDateTime at ZONE).
func parseFakeNow(_ s: String) throws(DateTimeParseError) -> Date {
    do {
        return try parseOffsetDateTime(s)
    } catch {
        do {
            return try parseInstant(s)
        } catch {
            return try parseLocalDateTime(s).atZone(ZONE)
        }
    }
}
