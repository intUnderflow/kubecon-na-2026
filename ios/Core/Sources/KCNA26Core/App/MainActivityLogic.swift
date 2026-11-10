import Foundation

/// The non-UI logic of Kotlin MainActivity.kt (the app's root view and delegate call it):
///
/// - Debug builds: the `-fakeNow <iso>` launch argument sets the fake clock, `-fakeNow clear`
///   resets it (Android: the `fakeNow` intent extra; see ``FakeableClock/applyFakeNowArg(_:)``):
///   `xcrun simctl launch booted <bundle id> -fakeNow 2026-11-11T09:00:00-07:00`, or the
///   scheme's "Arguments Passed On Launch". ``AppGraph/start(arguments:)`` applies it.
/// - A tapped reminder opens Directions for its session (``ReminderContent/directionsSessionId(_:)``,
///   ``AppGraph/notificationTapped(userInfo:)``).
/// - The root shows nothing until the data is loaded, then the navigation shell and, on a fresh
///   install, the first-run speaker sheet; or the error text if the bundled data can't load
///   (``RootState``).
enum MainActivityLogic {
    /// The launch argument (`-fakeNow`; `--fakeNow` also works). Its name is
    /// ``FakeableClock/EXTRA_FAKE_NOW``.
    static let FAKE_NOW_ARGUMENT = "-" + FakeableClock.EXTRA_FAKE_NOW

    /// The value of the `-fakeNow` launch argument in `arguments` (`ProcessInfo.processInfo.arguments`):
    /// the argument after the last `-fakeNow` / `--fakeNow`; nil if there is none (or nothing follows it).
    static func fakeNowArgument(_ arguments: [String]) -> String? {
        var value: String?
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == FAKE_NOW_ARGUMENT || a == "-" + FAKE_NOW_ARGUMENT {
                if i + 1 < arguments.count {
                    value = arguments[i + 1]
                    i += 2
                    continue
                }
            }
            i += 1
        }
        return value
    }

    /// Kotlin `handleIntent`'s debug branch: applies the `-fakeNow` argument to `clock` in debug
    /// builds only (`isDebug`; the clock also refuses in release builds). Returns the log line
    /// ("fakeNow=… applied=… now=…"), or nil when there was no argument to apply.
    @discardableResult
    static func applyFakeNow(_ arguments: [String], to clock: FakeableClock, isDebug: Bool) -> String? {
        guard isDebug, let arg = fakeNowArgument(arguments) else { return nil }
        let ok = clock.applyFakeNowArg(arg)
        return "fakeNow=\(arg) applied=\(ok) now=\(clock.now())"
    }

    /// The root's text when the bundled data can't be loaded (Kotlin `e.toString()`: the error's
    /// type and message).
    static func loadErrorText(_ error: any Error) -> String {
        "Couldn’t load the schedule data: " + DataSync.describe(error)
    }

    /// What the root view shows (Kotlin `Root`).
    enum RootState: Sendable, Hashable {
        /// The data is still loading: the plain background (the launch screen just went).
        case loading
        /// The navigation shell, with the first-run sheet over it while
        /// `settings.firstRunPending` (``AppGraph/showsFirstRunSheet``).
        case ready
        /// ``loadErrorText(_:)``, padded 24 points inside the safe area.
        case failed(String)
    }
}
