import Foundation

/// The pure parts of Kotlin ui/going/GoingUi.kt ("Going"/RSVP UI): the star toggle on cards,
/// the day header's RSVP'd chip, the "Up next" row, the details' RSVP button and clash note, the
/// Settings reminder choice and the inline notifications-off hint. Quiet ink accents, never the
/// pink "You" treatment. Strings are ``GoingText``'s; the rules are ``GoingLogic``'s.
///
/// The Going accent colours (`goingCardBg`, `goingCardBorder`, `goingRowBg`, `goingRule`,
/// `clash`, `clashBg`, `clashBorder`) are ``PaletteRole`` cases (their Kotlin formulas in
/// ``PaletteRole/argb(in:)``); the app's `AppColors` has them as `Color`s too.
enum GoingUiLogic {
    /// Space a card keeps free at its top-right corner for the star (Kotlin `StarReserve`, points).
    static let STAR_RESERVE: Double = 34

    // MARK: - StarToggle

    /// The 48 pt star's tint: filled ink when going, outlined muted otherwise; white on my own
    /// pink cards (80% when not going). VoiceOver: ``GoingText/starDescription(_:_:)`` as a toggle.
    static func starTint(going: Bool, onCard: Bool) -> PaletteRole {
        if onCard { return going ? .onYou : .onYouFaded }
        return going ? .ink : .muted
    }

    // MARK: - GoingChip

    /// The day header's RSVP'd filter chip (``GoingText/CHIP``, VoiceOver
    /// ``GoingText/CHIP_DESCRIPTION``, a toggle): ink fill and `bg` text when on; surface, a
    /// hairline border and ink text when off. Filled star when on.
    static func chipColors(on: Bool) -> (fill: PaletteRole, border: PaletteRole, content: PaletteRole) {
        on ? (.ink, .ink, .bg) : (.surface, .line, .ink)
    }

    // MARK: - GoingNextCard

    /// The "Up next" card's lines: "★ YOUR NEXT  in 12 min" (``GoingNext/label``, then
    /// ``GoingNext/countdown`` in pink when live, else muted), the title (2 lines), then
    /// ``goingNextWhere(_:)``; a walk button (``goingNextDirectionsLabel(_:)``) when `canRoute`.
    static func goingNextCountdownColor(_ next: GoingNext) -> PaletteRole { next.live ? .you : .muted }

    /// "**10:30–11:00 AM** · **251 A–C** · Level 2" (bold ink, the rest muted).
    static func goingNextWhere(_ next: GoingNext) -> [TextRun] {
        var runs = [TextRun(next.time, bold: true, role: .ink), TextRun(" · "), TextRun(next.roomName, bold: true, role: .ink)]
        if let level = next.level {
            runs.append(TextRun(" · "))
            runs.append(TextRun(level))
        }
        return runs
    }

    /// The walk button's label: "Directions to 251 A–C".
    static func goingNextDirectionsLabel(_ next: GoingNext) -> String { "Directions to \(next.roomName)" }

    // MARK: - GoingToggleButton

    /// The details' RSVP toggle (as tall as the Directions button): nothing for break rows.
    static func showsToggle(_ index: ScheduleIndex, _ s: Session) -> Bool { !index.isBreak(s) }

    /// "RSVP’d" (filled star, ink-tinted fill, 2 pt ink border) / "RSVP" (outlined star, surface, hairline).
    static func toggleLabel(_ going: Bool) -> String { going ? GoingText.GOING : GoingText.MARK }

    static func toggleColors(_ going: Bool) -> (fill: PaletteRole, border: PaletteRole, borderWidth: Double) {
        going ? (.goingButtonBg, .ink, 2) : (.surface, .line, 1)
    }

    // MARK: - GoingClashNote

    /// One line of the details' "Clash" note: "**Wed 2:20–2:50 PM** · **Your talk**: Title · Room".
    struct ClashLine: Sendable, Hashable {
        let session: Session
        /// "2:20–2:50 PM", with the day ("Thu 9:00–9:30 AM") when it's on another day. Bold.
        let when: String
        /// One of my talks: "Your talk" (bold pink) and ": " before the title.
        let mine: Bool
        let title: String
        /// Muted, after " · ".
        let roomName: String

        /// The line as runs (the line's colour: ink).
        var runs: [TextRun] {
            var out = [TextRun(when, bold: true), TextRun(" · ")]
            if mine {
                out.append(TextRun(GoingText.YOUR_TALK, bold: true, role: .you))
                out.append(TextRun(": "))
            }
            out.append(TextRun(title))
            out.append(TextRun(" · " + roomName, role: .muted))
            return out
        }
    }

    /// The details' clash note (Kotlin `GoingClashNote` + `ClashNote`): what this starred
    /// session overlaps (other starred sessions, my talks), under ``GoingText/CLASH`` and
    /// ``GoingText/CLASHES_WITH``; nil when it isn't starred or clashes with nothing. `now`: the minute.
    static func clashNote(_ index: ScheduleIndex, _ s: Session, _ going: Set<String>, _ me: String?, _ now: Date) -> [ClashLine]? {
        if !going.contains(s.id) { return nil }
        let clashes = GoingLogic.clashesFor(index, s, going, me, now)
        if clashes.isEmpty { return nil }
        return clashLines(clashes, index, s.day)
    }

    /// The note's lines for `clashes` of a session on `day`.
    static func clashLines(_ clashes: [Clash], _ index: ScheduleIndex, _ day: String) -> [ClashLine] {
        let dows: [String: String] = Dictionary(index.days.map { ($0.key, $0.dow) }, uniquingKeysWith: { _, last in last })
        return clashes.map { cl in
            let s = cl.session
            let prefix = s.day != day ? dows[s.day].map { "\($0) " } ?? "" : ""
            return ClashLine(session: s, when: prefix + TimeFormat.range(s), mine: cl.mine, title: s.title, roomName: index.roomName(s.room))
        }
    }

    // MARK: - GoingReminderHint / NotificationsOffHint

    /// Under the details' buttons: whether this session has a reminder to come (mine, or starred
    /// with reminders on, and not started yet), so the notifications-off hint applies; the
    /// reminder's kind, or nil. Show ``notificationsOffText(_:_:channelLevel:)`` for it.
    static func reminderHint(_ s: Session, _ me: String?, _ going: Set<String>, _ remindMinutes: Int, _ now: Date) -> ReminderKind? {
        guard let spec = ReminderPlanner.specFor(s, me, going, remindMinutes) else { return nil }
        return s.start.isAfter(now) ? spec.kind : nil
    }

    /// The hint's text for `block` (``NotificationAsk/blocked(_:_:)``), or nil to show nothing
    /// (notifications on, the permission still to be asked, or its dialog up). `channelLevel`
    /// (Settings only) also mentions a turned-off channel: Android only; iOS never reports
    /// ``NotificationAsk/Block/channel``. The hint: a bell-slash icon (clash amber), the text,
    /// and ``GoingText/TURN_ON`` (``NotificationAsk/turnOn(_:)``) on a ``PaletteRole/clashBg`` strip.
    static func notificationsOffText(_ block: NotificationAsk.Block, _ channel: ReminderKind, channelLevel: Bool = false) -> String? {
        switch block {
        case .app: return GoingText.NOTIFICATIONS_OFF
        case .channel:
            if !channelLevel { return nil }
            return channel == .going ? GoingText.GOING_CHANNEL_OFF : GoingText.TALKS_CHANNEL_OFF
        case .nothing: return nil
        }
    }

    // MARK: - GoingReminderSetting

    /// The Settings section's heading.
    static let SETTING_HEADING = "RSVPs"

    /// Settings: which reminders the notifications-off hint is about (RSVP reminders when on,
    /// else my talks' when I'm speaking as someone), or nil for no hint. The section:
    /// ``SETTING_HEADING``, ``GoingText/SETTING_TITLE``, one option per
    /// ``GoingStore/REMIND_OPTIONS`` (``GoingText/optionLabel(_:)``, a radio group), then
    /// ``GoingText/settingSummary(_:_:)``.
    static func reminderSettingChannel(_ remindMinutes: Int, _ me: String?) -> ReminderKind? {
        if remindMinutes > 0 { return .going }
        if me != nil { return .mine }
        return nil
    }
}
