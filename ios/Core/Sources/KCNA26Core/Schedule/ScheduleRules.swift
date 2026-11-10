import Foundation

/// Port of the web version's `catOf` and `seriesOf` (schedule_app.js).
///
/// schedule.json already carries the web's precomputed `category` and `group`, and the app
/// uses those. The one exception: the web's break regex `/^(☕|🍲|Break|Lunch|Coffee)/` also
/// matches talk titles that start with "Breaking…", so three real talks (with speakers) arrive
/// as category "log" (quiet break rows that can't be opened or searched). ``ScheduleIndex``
/// re-runs these rules with the word-bounded regex for exactly those rows; for every other
/// session the result equals the JSON (ScheduleRulesTests checks both).
enum ScheduleRules {
    /// The web's LOG_RE, verbatim (matches "Breaking…" too).
    private static let LOG_RE_WEB = KRegex("^(☕|🍲|Break|Lunch|Coffee)")

    /// LOG_RE with "Break" as a whole word, so "Breaking up Is Hard…" stays a talk.
    private static let LOG_RE_FIXED = KRegex("^(☕|🍲|Break(?!\\p{L})|Lunch|Coffee)")

    private static let SOC_RE = KRegex(
        "KubeCrawl|ClashLoopBackOff|Trivia|Fun Run|Puppy Yoga|Pet-a-Pup|Documentary|Reception|Group Photo",
        options: .ignoreCase
    )
    private static let CTF_RE = KRegex("Capture The Flag", options: .ignoreCase)
    private static let DEMOS_RE = KRegex("In-Booth Demos")

    private static let MNT_ROOMS: Set<String> = ["250AC", "250DF", "251AC", "251DF", "254"]
    private static let HANDS_ROOMS: Set<String> = ["255A", "255D", "RA"]
    private static let SHOW_ROOMS: Set<String> = ["PP", "CC", "DT", "NN", "SSZ"]
    private static let COM_ROOMS: Set<String> = ["J", "CR", "UM"]

    /// Web `catOf`. `webExact` = true uses the web's regex unchanged (for tests).
    static func catOf(_ s: Session, webExact: Bool = false) -> String {
        let t = s.title
        let r = s.room
        let logRe = webExact ? LOG_RE_WEB : LOG_RE_FIXED
        if logRe.containsMatchIn(t) { return "log" }
        if s.isMaintainerSummit {
            if s.note == "Keynote" { return "key" }
            if s.note == "Unconference" { return "com" }
            if s.note == "Project Meeting" { return "mnt" }
            if s.note == "Workshop" { return "hands" }
            if SOC_RE.containsMatchIn(t) { return "soc" }
            return "talk"
        }
        if r == "OFF" || s.note == "All-Access pass" { return "colo" }
        if SOC_RE.containsMatchIn(t) { return "soc" }
        if r == "DE" { return "key" }
        if CTF_RE.containsMatchIn(t) { return "hands" }
        if MNT_ROOMS.contains(r) { return "mnt" }
        if HANDS_ROOMS.contains(r) { return "hands" }
        if SHOW_ROOMS.contains(r) || DEMOS_RE.containsMatchIn(t) { return "show" }
        if COM_ROOMS.contains(r) { return "com" }
        return "talk"
    }

    /// Web `seriesOf` for a session whose category is `cat`.
    static func seriesOf(_ s: Session, _ cat: String) -> SessionGroup? {
        if cat == "log" { return nil }
        let r = s.room
        let d = s.day
        let st = TimeFormat.minuteOfDay(s.start)
        let len = durationMinutes(from: s.start, to: s.effectiveEnd)
        if r == "DE" { return SessionGroup("\(d)-key", d == "tue" ? "Opening keynotes" : "Morning keynotes") }
        if d == "mon" && r == "RBD" { return SessionGroup("mon-plt", "Project Lightning Talks") }
        if d == "wed" && r == "RCD" && len <= 10 { return SessionGroup("wed-lt", "Lightning talks") }
        if r == "CC" {
            switch d {
            case "tue":
                if st < 770 { return SessionGroup("tue-cnu", "Cloud Native University") }
                if st < 890 { return SessionGroup("tue-envoy", "EnvoyCon") }
                return SessionGroup("tue-kyv", "KyvernoCon")
            case "wed":
                if st < 755 { return SessionGroup("wed-kv", "KubeVirt Summit") }
                if st < 880 { return SessionGroup("wed-kf", "Kubeflow Summit") }
                return SessionGroup("wed-istio", "Istio Day")
            case "thu":
                return SessionGroup("thu-llmd", "llm-d sessions")
            default:
                break
            }
        }
        if d == "wed" && r == "SHOW" && cat == "talk" { return SessionGroup("wed-posters", "Poster sessions") }
        return nil
    }

    /// True for a JSON "log" row that is really a talk: it has speakers. Break rows (coffee,
    /// lunch, networking) never list speakers.
    static func isMisfiledBreak(_ s: Session) -> Bool { s.category == "log" && !s.speakers.isEmpty }
}
