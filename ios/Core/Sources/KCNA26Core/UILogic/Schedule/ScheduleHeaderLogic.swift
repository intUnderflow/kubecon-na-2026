import Foundation

/// The pure parts of Kotlin ui/schedule/ScheduleHeader.kt (web `header.top`, `.days`,
/// `.search`, `.dayhead`, `.mine`): texts and rules of `ScheduleHeader`, `DayTabs`,
/// `ScheduleSearchField`, `DayHeading`, `SearchHeading` and `MineBannerCard`.
enum ScheduleHeaderLogic {
    /// "KUBECON NA 2026" with "NA" in pink (the brand line; Barlow, ink). A VoiceOver heading.
    static let BRAND: [TextRun] = [TextRun("KUBECON "), TextRun("NA", role: .you), TextRun(" 2026")]

    /// The Settings button's label.
    static let SETTINGS = "Settings"

    static let SEARCH_PLACEHOLDER = "Search talks, speakers, rooms"
    static let CLEAR_SEARCH = "Clear search"

    /// The day tabs' "YOU" badge (pink; hidden from VoiceOver: the tab's description says it).
    static let YOU_BADGE = "You"

    /// The banner's label ("YOU’RE SPEAKING").
    static let BANNER_LABEL = "You’re speaking"

    /// The brand row's trailing padding: the Settings button's 12 pt inset taken off the side padding.
    static func headerTrailingPadding(_ sidePadding: Double) -> Double { max(sidePadding - 12, 0) }

    /// The selected tab: none while searching (search covers every day).
    static func dayTabsCurrent(_ currentDay: String?, searching: Bool) -> String? { searching ? nil : currentDay }

    /// A day tab's VoiceOver label: "Today, Wednesday, Nov 11, you’re speaking".
    static func dayTabDescription(_ tab: DayTab) -> String {
        (tab.label == "Today" ? "Today, " : "") + tab.title + (tab.hasMine ? ", you’re speaking" : "")
    }

    /// Today's status line under the day heading: "**3** ON NOW · NEXT AT **10:15 AM**" (count
    /// bold pink, time bold ink, the rest muted, already in caps).
    static func dayStatusLine(_ st: DayStatus) -> [TextRun] {
        var runs = [TextRun(String(st.onNow), bold: true, role: .you), TextRun(" ON NOW")]
        if let next = st.nextStart {
            runs.append(TextRun(" · NEXT AT "))
            runs.append(TextRun(TimeFormat.hma(next).caps(), bold: true, role: .ink))
        }
        return runs
    }

    /// A banner "later" row's text: the title, a space, then the room at 80% white.
    static func bannerLaterText(_ x: LaterTalk) -> (title: String, room: String) { (x.session.title + " ", x.roomName) }
}
