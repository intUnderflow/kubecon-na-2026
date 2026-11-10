import Foundation

/// The details sheet's strings, ported from schedule_app.js `sheetHTML` / `wayHTML` (Kotlin
/// ui/session/SessionText.kt). Pure (no UI, no platform) so it is unit-tested.
///
/// Kotlin -> Swift: string comparisons of names are UTF-16 exact (`kotlinEquals`,
/// ``matchScheduleName(_:_:)`` per unit, like Kotlin's `==` / `equals(ignoreCase)` /
/// `startsWith(ignoreCase)`); `trim()` is ``Swift/String/kotlinTrim()``.
enum SessionText {
    static let OFF_SITE = "Off-site event. The official listing has the address and registration details."
    static let NO_POSITION = "No map position for this room."
    static let LOADING = "Loading the description…"

    /// Quiet note when a description that should exist couldn't be fetched (the web shows nothing).
    static let UNAVAILABLE = "Couldn’t load the description. The official listing has it."

    static let YOU_SPEAKING = "You’re speaking"
    static let ANTHROPIC = "Anthropic"
    static let YOU = "You"
    static let GETTING_THERE = "Getting there"
    static let ABOUT = "About"
    static let DIRECTIONS = "Directions"
    static let SLIDES = "Slides ↗"
    static let OFFICIAL = "Official listing ↗"

    /// A session's GitHub discussion (``Session/discussionUrl``, unconference sessions), opened in the browser.
    static let DISCUSSION = "Proposal and replies on GitHub ↗"

    /// Tag on a sponsored co-located talk.
    static let SPONSORED = "Sponsored"

    /// Eyebrow of a break shared by several co-located events.
    static let COLOCATED_EVENTS = "Co-located events"

    /// "Speaker" / "Speakers" (web: `spkList.length===1`).
    static func speakersHeading(_ count: Int) -> String { count == 1 ? "Speaker" : "Speakers" }

    /// The web's `CATS[x.cat]`: the category label, empty for break rows ("log").
    static func categoryLabel(_ repo: Repository, _ s: Session) -> String {
        s.category == "log" ? "" : (repo.category(s.category)?.label ?? "")
    }

    /// The co-located event a session belongs to, as the details' eyebrow (in place of the
    /// category label): "ArgoCon" for its talks and its own breaks, "Co-located events" for a
    /// break several events share; nil for everything else (including the Evening Reception).
    static func coloEyebrow(_ repo: Repository, _ s: Session) -> String? {
        if !s.isColocated { return nil }
        let key: String? = s.coloEvent ?? (s.coloEvents.count == 1 ? s.coloEvents[0] : nil)
        if let key, let one = repo.coloEvent(key) { return one.name }
        return s.coloEvents.count { repo.coloEvent($0) != nil } > 1 ? COLOCATED_EVENTS : nil
    }

    /// A co-located talk's tags: format ("Lightning talk"), level ("Intermediate"), "Sponsored".
    static func coloTags(_ s: Session) -> [String] {
        if !s.isColocated { return [] }
        return [s.format, s.level, s.sponsored ? SPONSORED : nil].compactMap { $0 }
    }

    /// A shared co-located break: "For ArgoCon, BackstageCon, FluxCon and Observability Day".
    static func servesLine(_ repo: Repository, _ s: Session) -> String? {
        if !s.isColocated { return nil }
        let names = s.coloEvents.compactMap { repo.coloEvent($0)?.name }
        if names.count < 2 { return nil }
        return "For " + names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    /// The official listing: the session's own link, else (co-located) its event's page; nil if neither.
    static func officialUrl(_ repo: Repository, _ s: Session) -> String? {
        if s.officialUrl.isNotBlank { return s.officialUrl }
        guard let key = s.coloEvent, let e = repo.coloEvent(key) else { return nil }
        return e.pageUrl ?? e.infoUrl
    }

    /// "Wed 5:00–5:30 PM", "Sun from 5:30 PM" (web: `${d.dow} ${range(x)}`).
    static func dayAndTime(_ day: Day?, _ s: Session) -> String {
        [day?.dow, TimeFormat.range(s)].compactMap { $0 }.joined(separator: " ")
    }

    /// "45 min", "~1h 30m"; nil when the session has no end (open-ended).
    static func duration(_ s: Session) -> String? { TimeFormat.dur(s) }

    /// Maintainer Summit tag in the meta row ("Unconference", "Project Meeting"; not "Keynote").
    static func tag(_ s: Session) -> String? {
        guard let note = s.note, s.isMaintainerSummit, note.isNotBlank, !kotlinEquals(note, "Keynote") else { return nil }
        return note
    }

    /// KubeCon note in the where row ("Sold out", "All-Access pass").
    static func whereNote(_ s: Session) -> String? {
        guard let note = s.note, !s.isMaintainerSummit, note.isNotBlank else { return nil }
        return note
    }

    /// "Live · 12 min left" while the session is on (the sheet always counts down, like the web).
    static func liveLabel(_ s: Session, _ now: Date) -> String? {
        ScheduleLogic.isLive(s, now) ? "Live · \(TimeFormat.minutesBetween(now, s.effectiveEnd)) min left" : nil
    }

    /// Room name for the where row (the web's `rname`).
    static func roomName(_ room: Room?, _ s: Session) -> String { room?.name ?? s.room }

    /// The where row's muted building label ("Salt Palace L2"); nil for HL and OFF.
    static func buildingLabel(_ room: Room?) -> String? { room?.buildingLabel?.takeIfNotBlank() }

    /// "Level 2" (the web's `.wf .lv`); nil without a position.
    static func levelLabel(_ room: Room?) -> String? {
        guard let room, room.hasPosition, let level = room.level else { return nil }
        return "Level \(level)"
    }

    /// "Salt Palace · 251 A–C" / "Hyatt Regency · Park City" (the web's `.wf .bd`).
    static func buildingAndRoom(_ room: Room?) -> String? {
        guard let room, room.hasPosition else { return nil }
        let building = room.venueCode == "HY" ? "Hyatt Regency" : "Salt Palace"
        return "\(building) · \(room.name)"
    }

    /// "Level 2 · Salt Palace · 251 A–C"; nil for OFF or a room without a position.
    static func locationLine(_ room: Room?) -> String? {
        // A level implies a position, so buildingAndRoom is never nil here.
        guard let lv = levelLabel(room), let place = buildingAndRoom(room) else { return nil }
        return "\(lv) · \(place)"
    }

    /// Why Directions is unavailable (the web's wayHTML fallback), or nil if it is available. A
    /// place without a position that says where it is (the co-located foyers and lunch hall)
    /// leads with that sentence.
    static func directionsUnavailable(_ room: Room?, _ s: Session) -> String? {
        if let room, room.hasPosition { return nil }
        if s.room == "OFF" { return OFF_SITE }
        let place = room?.whereText?.kotlinTrim()
        guard let place, !place.isEmpty else { return NO_POSITION }
        return "\(place) \(NO_POSITION)"
    }

    /// One row of the speakers list.
    struct SpeakerRow: Sendable, Hashable {
        /// "You" for me, otherwise the name (cleaned of stray marks).
        let label: String
        let tagline: String
        let isMe: Bool
        /// An Anthropic colleague (never me).
        let isAnthropic: Bool

        init(label: String, tagline: String, isMe: Bool, isAnthropic: Bool) {
            self.label = label
            self.tagline = tagline
            self.isMe = isMe
            self.isAnthropic = isAnthropic
        }

        /// Kotlin `SpeakerRow(label, tagline, isMe = …, isAnthropic = …)`.
        init(_ label: String, _ tagline: String, isMe: Bool, isAnthropic: Bool) {
            self.init(label: label, tagline: tagline, isMe: isMe, isAnthropic: isAnthropic)
        }

        static func == (a: SpeakerRow, b: SpeakerRow) -> Bool {
            kotlinEquals(a.label, b.label) && kotlinEquals(a.tagline, b.tagline) && a.isMe == b.isMe && a.isAnthropic == b.isAnthropic
        }

        func hash(into hasher: inout Hasher) {
            for u in label.utf16 { hasher.combine(u) }
            hasher.combine(0xFFFF as UInt16) // separator: not a valid unit inside text
            for u in tagline.utf16 { hasher.combine(u) }
            hasher.combine(isMe)
            hasher.combine(isAnthropic)
        }
    }

    /// Speakers with taglines (the web's `spkList`): the details list when it has any, otherwise
    /// the schedule names. "You" follows the current "I'm speaking as" `me`; Anthropic is anyone
    /// in `anthropicSpeakers` other than me (so with me = None, Lucy Sweet shows as Anthropic).
    /// Sessionize names can differ slightly from the agenda's ("Suhani‎", "Smit Jain (he/him)"),
    /// so each is matched back to its schedule name before comparing.
    static func speakerRows(
        _ detailSpeakers: [SpeakerTagline],
        _ scheduleSpeakers: [String],
        _ me: String?,
        _ anthropicSpeakers: Set<String>
    ) -> [SpeakerRow] {
        let list = detailSpeakers.isEmpty ? scheduleSpeakers.map { SpeakerTagline($0, "") } : detailSpeakers
        return list.compactMap { sp in
            let name = cleanName(sp.name)
            if name.isEmpty { return nil }
            let canonical = matchScheduleName(name, scheduleSpeakers) ?? name
            let isMe = me.map { kotlinEquals(canonical, $0) } ?? false
            // Kotlin `canonical in anthropicSpeakers`: UTF-16 equality, not Swift's canonical equivalence.
            let inAnthropic = anthropicSpeakers.contains { kotlinEquals($0, canonical) }
            return SpeakerRow(
                label: isMe ? YOU : name,
                tagline: sp.tagline.kotlinTrim(),
                isMe: isMe,
                isAnthropic: !isMe && inAnthropic
            )
        }
    }

    private static let TRAILING_DASH = KRegex("[\\s]*[-–—]+\\s*$")

    /// Drops invisible format characters (LRM, ZWSP, BOM…) and a dangling trailing dash.
    ///
    /// Kotlin tests `Character.getType(c) == FORMAT` per UTF-16 unit, so a supplementary format
    /// character (its two surrogate halves are type SURROGATE) is kept; so it is here.
    static func cleanName(_ name: String) -> String {
        var visible = String.UnicodeScalarView()
        for u in name.unicodeScalars where !(u.value <= 0xFFFF && u.properties.generalCategory == .format) {
            visible.append(u)
        }
        return TRAILING_DASH.replace(String(visible).kotlinTrim(), "").kotlinTrim()
    }

    /// The schedule's spelling of `name`: exact, case-insensitive, or a prefix ("Smit Jain (he/him)").
    static func matchScheduleName(_ name: String, _ scheduleSpeakers: [String]) -> String? {
        if let exact = scheduleSpeakers.first(where: { kotlinEquals($0, name) }) { return exact }
        if let folded = scheduleSpeakers.first(where: { kotlinEqualsIgnoreCase($0, name) }) { return folded }
        let units = Array(name.utf16)
        return scheduleSpeakers.filter { $0.isNotBlank }.first { sp in
            startsWithIgnoreCase(units, Array((sp + " ").utf16)) || startsWithIgnoreCase(units, Array((sp + "(").utf16))
        }
    }

    /// Kotlin `startsWith(prefix, ignoreCase = true)`: per UTF-16 unit, a unit matches when equal,
    /// or equal after `Character.toUpperCase`, or after `toUpperCase` then `toLowerCase`.
    private static func startsWithIgnoreCase(_ s: [UInt16], _ prefix: [UInt16]) -> Bool {
        if prefix.count > s.count { return false }
        for i in 0..<prefix.count {
            let a = s[i]
            let b = prefix[i]
            if a == b { continue }
            let ua = javaToUpperCase(a)
            let ub = javaToUpperCase(b)
            if ua == ub || javaToLowerCase(ua) == javaToLowerCase(ub) { continue }
            return false
        }
        return true
    }
}
