import Foundation

/// The pure parts of Kotlin ui/settings/FirstRunSheet.kt: the first-run picker "Speaking at
/// KubeCon? Pick your name", over the schedule while `settings.firstRunPending`. The same
/// searchable speaker list as Settings (``SettingsScreenLogic/shown(_:_:)``); picking a name
/// calls `settings.finishFirstRun(name)` (and so the reminders), ``SKIP`` calls
/// `finishFirstRun(nil)` (None). Either way it never shows again. Swiping it away only hides it
/// until the next cold start (`settings.dismissFirstRunForNow()`), since that is easy to do by
/// accident.
///
/// One-handed: the search field and Skip sit at the bottom, under the list; VoiceOver reads the
/// title, the text, search and Skip first, then the list (`accessibilitySortPriority`). While
/// the keyboard is up the title and text are hidden, so the list keeps its room. The rows are
/// buttons (name, summary), not radio buttons. Sheet: `bg` background, 90% of the height.
enum FirstRunSheetLogic {
    static let TITLE = "Speaking at KubeCon? Pick your name"
    static let TEXT = "Your talks get the pinned banner, the pink highlight and reminders 30 and 10 minutes " +
        "before. You can change this any time in Settings."
    static let SKIP = "Skip"

    /// The sheet shows the no-match note whenever the list is empty (unlike Settings).
    static func showsNoMatch(_ shown: [SpeakerOption]) -> Bool { shown.isEmpty }
}
