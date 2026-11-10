import Foundation

/// The pure parts of Kotlin ui/settings/SettingsScreen.kt: Settings = the RSVP reminder choice
/// (``GoingUiLogic``), the schedule data row (``DataSourceText``), then "I’m speaking as"
/// (default None; any speaker in the schedule, searchable). Choosing a speaker updates
/// everything "mine" at once (banner, highlights, "You" labels, day-tab badges follow
/// `settings.speakingAs`) and the app reschedules the reminders whenever it changes. The theme
/// follows the system, so there is no control for it.
///
/// List order: ``SpeakerPicker`` options filtered by the search field (sticky), after a "None"
/// row: ``NONE`` / ``NONE_SUBTITLE`` (selected when `me` is nil), then one row per
/// ``shown(_:_:)`` option (name, summary; selected = `me`), then ``noMatchText(_:)`` when
/// ``showsNoMatch(_:_:)``, then ``THEME_NOTE``. Content: one column of at most
/// `Dimens.maxTextWidth` (`PageLayout.sidePadding(forWidth:maxContent:)`).
enum SettingsScreenLogic {
    static let TITLE = "Settings"
    static let BACK = "Back"
    /// The section heading.
    static let SPEAKING_AS = "I’m speaking as"
    static let NONE = "None"
    static let NONE_SUBTITLE = "Don’t mark any talks as mine"
    static let SEARCH_PLACEHOLDER = "Search speakers"
    static let INTRO = "Your talks get the pinned banner, the pink highlight, “You” in speaker lists, " +
        "a mark on the day tab, and reminders 30 and 10 minutes before."
    static let THEME_NOTE = "Light and dark theme follow your system setting."

    /// The current choice in big type: the name (pink) or "None" (ink).
    static func speakingAsName(_ me: String?) -> String { me ?? NONE }

    /// The option for `me`, or nil (None, or a name no longer on the schedule).
    static func current(_ options: [SpeakerOption], _ me: String?) -> SpeakerOption? {
        guard let me else { return nil }
        return options.first { kotlinEquals($0.name, me) }
    }

    /// The line under the name.
    static func speakingAsSummary(_ me: String?, _ current: SpeakerOption?) -> String {
        if me == nil { return "No talks are marked as yours, so there are no talk reminders." }
        if let current { return current.summary }
        return "Not on the schedule."
    }

    /// The listed options for the search field's text (Settings lists the default speaker with the rest: no pin).
    static func shown(_ options: [SpeakerOption], _ searchText: String) -> [SpeakerOption] {
        SpeakerPicker.filter(options, SpeakerPicker.terms(searchText), nil)
    }

    /// Settings shows the note only for a search that matches nobody.
    static func showsNoMatch(_ shown: [SpeakerOption], _ terms: [String]) -> Bool { shown.isEmpty && !terms.isEmpty }

    /// "No speaker matches “zzz”." (the search text, trimmed).
    static func noMatchText(_ searchText: String) -> String { "No speaker matches “\(searchText.kotlinTrim())”." }

    /// Kotlin `choose`: set "I’m speaking as" only when it changes (nil = None).
    static func shouldChoose(_ name: String?, _ me: String?) -> Bool {
        switch (name, me) {
        case (nil, nil): return false
        case let (a?, b?): return !kotlinEquals(a, b)
        default: return true
        }
    }
}
