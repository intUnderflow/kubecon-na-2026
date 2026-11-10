import Foundation

/// Text of the Settings "Schedule data" row (Kotlin ui/settings/DataSourceRow.kt
/// `DataSourceText`; the composable `DataSourceRow` is the app's). Pure, unit-tested. Times are
/// Denver time, like the rest of the app.
///
/// The row: ``HEADING`` (a heading), then ``updated(_:_:)`` + " ·" + a ``CHECK_NOW`` button
/// (`sync.checkInBackground()`, disabled while `status.checking`), with ``source(_:_:_:)``
/// underneath (a polite live region: `.accessibilityAddTraits(.updatesFrequently)` or an
/// announcement). Failures are never shown: the row just stays as it was. Pass the WALL clock
/// as `now` (`Date()`, like `SyncStatus.lastCheckedAt`), not the app clock, which may be faked.
enum DataSourceText {
    /// The section heading ("SCHEDULE DATA" in caps).
    static let HEADING = "Schedule data"
    /// The check button.
    static let CHECK_NOW = "Check now"
    /// Between the updated line and the button.
    static let SEPARATOR = " ·"

    /// "Just now" lasts this long (seconds) after a download; then it says when.
    private static let JUST_NOW: TimeInterval = 2 * 60

    /// Java `DateTimeFormatter.ofPattern("MMM", Locale.US)` month names.
    private static let MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "Updated Nov 8, 2:15 PM": when the data was published (or its version when the manifest has no time).
    static func updated(_ at: Date?, _ version: Int) -> String {
        if let at { return "Updated \(dateTime(at))" }
        return "Version \(version)"
    }

    /// "Bundled with the app" / "From GitHub", plus "Checking…", "Up to date", or when this
    /// phone downloaded it: "Downloaded just now", "Downloaded at 9:00 AM" (today) or
    /// "Downloaded Nov 8, 9:00 AM".
    static func source(_ source: ActiveData.Source, _ status: SyncStatus, _ now: Date) -> String {
        let from: String
        switch source {
        case .bundled: from = "Bundled with the app"
        case .github: from = "From GitHub"
        }
        let at = status.lastCheckedAt
        let state: String?
        if status.checking {
            state = "Checking…"
        } else if case .updated? = status.last {
            if let at, !(now.timeIntervalSince(at) < JUST_NOW) {
                state = at.localDate == now.localDate ? "Downloaded at \(TimeFormat.hma(at))" : "Downloaded \(dateTime(at))"
            } else {
                state = "Downloaded just now"
            }
        } else if status.last == .notModified {
            state = "Up to date"
        } else if case .notNewer? = status.last {
            state = "Up to date"
        } else {
            state = nil // never checked, or it failed: say nothing
        }
        if let state { return "\(from) · \(state)" }
        return from
    }

    /// "Nov 8, 2:15 PM" (Kotlin `"MMM d"` in Denver, Locale.US, then `TimeFormat.hma`).
    private static func dateTime(_ at: Date) -> String {
        let d = at.localDate
        return "\(MONTHS[d.monthValue - 1]) \(d.dayOfMonth), \(TimeFormat.hma(at))"
    }
}
