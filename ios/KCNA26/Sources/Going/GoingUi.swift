import SwiftUI

// Kotlin ui/going/GoingUi.kt: the RSVP ("Going") UI. The star toggle on cards, the day header's
// RSVP'd chip, the "Up next" row, the details' RSVP button and clash note, the Settings reminder
// choice and the inline notifications-off hint. Quiet ink accents, never the pink "You"
// treatment. Strings are Core's `GoingText`, rules `GoingLogic` / `GoingUiLogic`; the Going
// accent colours are `AppColors.goingCardBg` … `clashBorder` (Theme/Color.swift).

// MARK: - StarToggle

/// The 48 pt star toggle (Kotlin `StarToggle`). Outlined in muted ink when not going, filled ink
/// when going; white on my own pink cards (`onCard`, 80% when not going). VoiceOver: "RSVP:
/// <label>" / "RSVP’d: <label>" (``GoingText/starDescription(_:_:)``) as a toggle, so each star
/// in a list says which session it is for. A selection haptic on every tap.
///
///     StarToggle(going: ids.contains(s.id), onToggle: { going.toggle(s.id) }, label: s.title)
///     StarToggle(going: g, onToggle: t, label: kid.title, onCard: mine, iconSize: 21)   // kid rows
struct StarToggle: View {
    let going: Bool
    let onToggle: () -> Void
    var label: String?
    var onCard: Bool
    var iconSize: CGFloat

    @Environment(\.appColors) private var colors
    @State private var taps = 0

    init(going: Bool, onToggle: @escaping () -> Void, label: String? = nil, onCard: Bool = false, iconSize: CGFloat = 23) {
        self.going = going
        self.onToggle = onToggle
        self.label = label
        self.onCard = onCard
        self.iconSize = iconSize
    }

    var body: some View {
        let tint: Color = colors.color(GoingUiLogic.starTint(going: going, onCard: onCard))
        let side = CGFloat(Dimens.touchTarget)
        Button {
            taps += 1
            onToggle()
        } label: {
            AppIconImage(going ? .star : .starBorder, size: iconSize)
                .foregroundStyle(tint)
                .frame(width: side, height: side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityLabel(Text(verbatim: GoingText.starDescription(going, label)))
        .accessibilityAddTraits(going ? [.isToggle, .isSelected] : .isToggle)
    }
}

/// A session card with the star toggle over its top-right corner (Kotlin `GoingStarFrame`);
/// `content` keeps `GoingUiLogic.STAR_RESERVE` (34 pt, Kotlin `StarReserve`) free at its
/// trailing edge (the card's meta row and title).
struct GoingStarFrame<Content: View>: View {
    let going: Bool
    let onToggle: () -> Void
    let onCard: Bool
    let label: String
    private let content: Content

    init(going: Bool, onToggle: @escaping () -> Void, onCard: Bool, label: String, @ViewBuilder content: () -> Content) {
        self.going = going
        self.onToggle = onToggle
        self.onCard = onCard
        self.label = label
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
            StarToggle(going: going, onToggle: onToggle, label: label, onCard: onCard)
        }
    }
}

// MARK: - GoingMark

/// Small non-interactive filled star (Kotlin `GoingMark`): a group card header says one of its
/// sessions is starred. `description` is read by VoiceOver ("RSVP’d to 2 of these").
struct GoingMark: View {
    let description: String

    @Environment(\.appColors) private var colors

    init(_ description: String) {
        self.description = description
    }

    var body: some View {
        AppIconImage(.star, size: 17, label: description)
            .foregroundStyle(colors.ink)
    }
}

// MARK: - GoingChip

/// The day header's "RSVP’d" filter chip (Kotlin `GoingChip`): only starred sessions and my
/// talks. Ink when on (filled star, `bg` text), surface with a hairline when off. The visible
/// chip is its natural size, centred in a 48 pt touch area (Kotlin
/// `minimumInteractiveComponentSize`). VoiceOver: ``GoingText/CHIP_DESCRIPTION``, a toggle.
struct GoingChip: View {
    let on: Bool
    let onToggle: () -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type
    @State private var taps = 0

    init(on: Bool, onToggle: @escaping () -> Void) {
        self.on = on
        self.onToggle = onToggle
    }

    var body: some View {
        let roles = GoingUiLogic.chipColors(on: on)
        let fg: Color = colors.color(roles.content)
        let side = CGFloat(Dimens.touchTarget)
        Button {
            taps += 1
            onToggle()
        } label: {
            HStack(spacing: 5) {
                AppIconImage(on ? .star : .starBorder, size: 17)
                    .foregroundStyle(fg)
                CapsText(GoingText.CHIP, style: type.button.copy(size: 14, lineHeight: 16), color: fg, lineLimit: 1)
            }
            .padding(.leading, 9)
            .padding(.trailing, 11)
            .padding(.vertical, 6)
            .tileSurface(selected: on, radius: 8)
            .frame(minWidth: side, minHeight: side)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: GoingText.CHIP_DESCRIPTION))
        .accessibilityAddTraits(on ? [.isButton, .isToggle, .isSelected] : [.isButton, .isToggle])
    }
}

// MARK: - GoingNextCard

/// My next (or live) starred session today (Kotlin `GoingNextCard`), compact enough for a phone:
/// "★ YOUR NEXT  IN 12 MIN" or "★ ON NOW  8 MIN LEFT" (not "Up next", which is the timeline
/// line's name), the title (2 lines), "**10:30–11:00 AM** · **251 A–C** · Level 2". Tapping the
/// text opens the session (`onOpen`); the ink walk button (when the room is on the map) opens
/// Directions. Has its own 12 pt top margin, like Kotlin.
struct GoingNextCard: View {
    let next: GoingNext
    let onOpen: () -> Void
    let onDirections: () -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(_ next: GoingNext, onOpen: @escaping () -> Void, onDirections: @escaping () -> Void) {
        self.next = next
        self.onOpen = onOpen
        self.onDirections = onDirections
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: onOpen) {
                text
                    .padding(.leading, CGFloat(Dimens.categoryStripe) + 12)
                    .padding(.trailing, 8)
                    .padding(.top, 9)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(verbatim: ScheduleCardsLogic.OPEN_DETAILS))
            if next.canRoute {
                walkButton
                    .padding(.trailing, 10)
            }
        }
        .cardSurface(fill: colors.goingCardBg, border: colors.goingCardBorder, stripe: colors.ink)
        .padding(.top, 12)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                AppIconImage(.star, size: 15)
                    .foregroundStyle(colors.ink)
                CapsText(next.label, style: type.bannerLabel, color: colors.ink, lineLimit: 1)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.leading, 5)
                    .layoutPriority(1)
                // Kotlin weight(1f, fill = false): takes what is left and ends with "…".
                CapsText(next.countdown, style: type.bannerLabel,
                         color: colors.color(GoingUiLogic.goingNextCountdownColor(next)), lineLimit: 1)
                    .padding(.leading, 8)
            }
            Text(verbatim: next.session.title)
                .appTextStyle(type.cardTitle)
                .foregroundStyle(colors.ink)
                .lineLimit(2)
                .padding(.top, 3)
            runsText(GoingUiLogic.goingNextWhere(next), style: type.small, colors: colors)
                .appTextStyle(type.small)
                .foregroundStyle(colors.muted)
                .lineLimit(2)
                .padding(.top, 3)
        }
    }

    private var walkButton: some View {
        let side = CGFloat(Dimens.touchTarget)
        let shape = RoundedRectangle(cornerRadius: CGFloat(Dimens.cardRadius), style: .circular)
        return Button(action: onDirections) {
            AppIconImage(.directionsWalk, size: 24)
                .foregroundStyle(colors.bg)
                .frame(width: side, height: side)
                .background { shape.fill(colors.ink) }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: GoingUiLogic.goingNextDirectionsLabel(next)))
    }
}

// MARK: - GoingToggleButton

/// The details' RSVP toggle (Kotlin `GoingToggleButton`), as tall as the Directions button
/// beside it (56 pt): outlined star and "RSVP" when not going; filled star, "RSVP’d", an
/// ink-tinted fill and a 2 pt ink border when going. Reads and writes `graph.going` itself.
/// Nothing for break rows (``GoingUiLogic/showsToggle(_:_:)``). Natural width; put it first in
/// the details' button row (`HStack(spacing: 8) { GoingToggleButton(session: s); directions }`).
struct GoingToggleButton: View {
    let session: Session

    @Environment(AppGraph.self) private var graph
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type
    @State private var taps = 0

    init(session: Session) {
        self.session = session
    }

    var body: some View {
        let index: ScheduleIndex = ScheduleIndex.of(graph.repository)
        if GoingUiLogic.showsToggle(index, session) {
            button
        }
    }

    private var button: some View {
        let store: GoingStore = graph.going
        let going: Bool = store.ids.contains(session.id)
        let look = GoingUiLogic.toggleColors(going)
        let shape = RoundedRectangle(cornerRadius: CGFloat(Dimens.cardRadius), style: .circular)
        let label: String = GoingUiLogic.toggleLabel(going)
        let id: String = session.id
        return Button {
            taps += 1
            store.setGoing(id, !going)
        } label: {
            HStack(spacing: 8) {
                AppIconImage(going ? .star : .starBorder, size: 22)
                    .foregroundStyle(colors.ink)
                CapsText(label, style: type.button.copy(size: 18), color: colors.ink, lineLimit: 1)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background { shape.fill(colors.color(look.fill)) }
            .overlay { shape.strokeBorder(colors.color(look.border), lineWidth: CGFloat(look.borderWidth)) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(going ? [.isButton, .isToggle, .isSelected] : [.isButton, .isToggle])
    }
}

// MARK: - Clash note and tag

/// The details' "Clash" note (Kotlin `GoingClashNote`): what this starred session overlaps
/// (other starred sessions, my talks), re-evaluated every minute. Nothing when the session isn't
/// starred or clashes with nothing; when shown it has its own 12 pt top margin.
struct GoingClashNote: View {
    let session: Session

    @Environment(AppGraph.self) private var graph

    init(session: Session) {
        self.session = session
    }

    var body: some View {
        let index: ScheduleIndex = ScheduleIndex.of(graph.repository)
        let ids: Set<String> = graph.going.ids
        let me: String? = graph.settings.speakingAs
        let s: Session = session
        NowReader { now in
            if let lines = GoingUiLogic.clashNote(index, s, ids, me, ScheduleLogic.minuteOf(now)) {
                ClashNote(lines: lines)
            }
        }
    }
}

/// The clash note's box (Kotlin `ClashNote`): the "Clash" tag and "CLASHES WITH", then one line
/// per clash ("**Wed 2:20–2:50 PM** · **Your talk**: Title · Room") on the clash tint.
struct ClashNote: View {
    let lines: [GoingUiLogic.ClashLine]

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(lines: [GoingUiLogic.ClashLine]) {
        self.lines = lines
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(Dimens.cardRadius), style: .circular)
        let lineStyle: AppTextStyle = type.small.copy(size: 14.5, lineHeight: 19)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                ClashTag()
                SectionLabel(GoingText.CLASHES_WITH, lineLimit: 1)
            }
            ForEach(lines, id: \.session.id) { line in
                runsText(line.runs, style: lineStyle, colors: colors)
                    .appTextStyle(lineStyle)
                    .foregroundStyle(colors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { shape.fill(colors.clashBg) }
        .overlay { shape.strokeBorder(colors.clashBorder, lineWidth: 1) }
        .padding(.top, 12)
    }
}

/// The "Clash" tag (Kotlin `ClashTag`): amber like the web's notes, for cards and the details;
/// white with pink text on my own pink cards (`onCard`).
struct ClashTag: View {
    var onCard: Bool

    init(onCard: Bool = false) {
        self.onCard = onCard
    }

    var body: some View {
        Pill(GoingText.CLASH, tone: onCard ? .onYou : .clash)
    }
}

// MARK: - Reminder hints

/// Under the details' buttons (Kotlin `GoingReminderHint`): the notifications-off hint when this
/// session has a reminder to come (mine, or starred with reminders on, and not started yet) and
/// the app's notifications are off. `padding` is applied only while the hint shows (Kotlin passes
/// `Modifier.padding(bottom = 8.dp)`); hidden it takes no space (in a `VStack(spacing: 0)`).
struct GoingReminderHint: View {
    let session: Session
    var padding: EdgeInsets

    @Environment(AppGraph.self) private var graph

    init(session: Session, padding: EdgeInsets = EdgeInsets()) {
        self.session = session
        self.padding = padding
    }

    var body: some View {
        let ids: Set<String> = graph.going.ids
        let minutes: Int = graph.going.remindMinutes
        let me: String? = graph.settings.speakingAs
        let s: Session = session
        let pad: EdgeInsets = padding
        NowReader { now in
            if let kind = GoingUiLogic.reminderHint(s, me, ids, minutes, now) {
                NotificationsOffHint(channel: kind, padding: pad)
            }
        }
    }
}

/// "Notifications are off for this app, so reminders can’t reach you." with a "Turn on" button
/// (Kotlin `NotificationsOffHint`); nothing when they're on, while the permission is still to be
/// asked, or while its dialog is up (``NotificationAsk/blocked(_:_:)``). `channel`: whose
/// reminders the hint is about; `channelLevel` (Settings) would also mention a turned-off
/// channel, which iOS never reports. The status is re-read whenever the scene becomes active
/// (back from Settings or the dialog) and when the system dialog opens or answers.
///
/// "Turn on": the system dialog while it can still show, else the app's notification settings
/// (``SystemLinks/turnOnNotifications(_:)``). `padding` applies only while the hint shows;
/// hidden it is an empty zero-size view (keep it in a `VStack(spacing: 0)`).
struct NotificationsOffHint: View {
    let channel: ReminderKind
    var padding: EdgeInsets
    var channelLevel: Bool

    @Environment(AppGraph.self) private var graph
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type
    @State private var status: NotificationAsk.Authorization?

    init(channel: ReminderKind, padding: EdgeInsets = EdgeInsets(), channelLevel: Bool = false) {
        self.channel = channel
        self.padding = padding
        self.channelLevel = channelLevel
    }

    /// What makes the status worth re-reading.
    private struct Refresh: Equatable {
        let asking: Bool
        let active: Bool
    }

    var body: some View {
        let asking: Bool = NotificationAsk.asking
        let block: NotificationAsk.Block = status.map { NotificationAsk.blocked($0, graph.settings) } ?? .nothing
        let text: String? = GoingUiLogic.notificationsOffText(block, channel, channelLevel: channelLevel)
        ZStack(alignment: .topLeading) {
            if let text {
                hint(text)
                    .padding(padding)
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .task(id: Refresh(asking: asking, active: scenePhase == .active)) {
            status = await graph.notificationPermission.status()
        }
    }

    private func hint(_ text: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .circular)
        let app: AppGraph = graph
        return HStack(alignment: .center, spacing: 0) {
            AppIconImage(.notificationsOff, size: 18)
                .foregroundStyle(colors.clash)
            Text(verbatim: text)
                .appTextStyle(type.small)
                .foregroundStyle(colors.ink)
                .padding(.vertical, 8)
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Material TextButton: 12 / 8 padding, a 48 pt touch target.
            Button {
                Task { @MainActor in
                    await SystemLinks.turnOnNotifications(app)
                }
            } label: {
                CapsText(GoingText.TURN_ON, style: type.button, color: colors.ink, lineLimit: 1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: CGFloat(Dimens.touchTarget))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { shape.fill(colors.clashBg) }
    }
}

// MARK: - Settings: GoingReminderSetting

/// Settings' RSVP section (Kotlin `GoingReminderSetting`): "RSVPS", "Remind me before sessions
/// I’ve RSVP’d to", the Off / 5 / 10 / 15 min choice (a radio group on `graph.going`), the
/// summary, and the notifications-off hint for the reminders that apply (RSVP reminders when on,
/// else my talks' when I'm speaking as someone). Padding around it is the caller's.
struct GoingReminderSetting: View {
    @Environment(AppGraph.self) private var graph
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init() {}

    var body: some View {
        let store: GoingStore = graph.going
        let minutes: Int = store.remindMinutes
        let me: String? = graph.settings.speakingAs
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(GoingUiLogic.SETTING_HEADING)
            Text(verbatim: GoingText.SETTING_TITLE)
                .appTextStyle(type.body.bold)
                .foregroundStyle(colors.ink)
                .padding(.top, 8)
            HStack(spacing: 6) {
                ForEach(GoingStore.REMIND_OPTIONS, id: \.self) { m in
                    option(m, selected: m == minutes, store: store)
                }
            }
            .padding(.top, 10)
            .accessibilityElement(children: .contain)
            Text(verbatim: GoingText.settingSummary(minutes, me))
                .appTextStyle(type.small)
                .foregroundStyle(colors.muted)
                .padding(.top, 8)
            if let channel = GoingUiLogic.reminderSettingChannel(minutes, me) {
                NotificationsOffHint(channel: channel, padding: EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0), channelLevel: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func option(_ m: Int, selected: Bool, store: GoingStore) -> some View {
        Button {
            store.setRemindMinutes(m)
        } label: {
            CapsText(GoingText.optionLabel(m), style: type.button, color: selected ? colors.bg : colors.ink, lineLimit: 1)
                .frame(maxWidth: .infinity, minHeight: CGFloat(Dimens.touchTarget))
                .tileSurface(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Previews

#Preview("Going chip, stars, tags") {
    ThemePreview {
        GoingSpecimen()
    }
}

private struct GoingSpecimen: View {
    @Environment(\.appColors) private var colors
    @State private var on = true
    @State private var starred = false

    var body: some View {
        HStack(spacing: 12) {
            GoingChip(on: on, onToggle: { on.toggle() })
            GoingChip(on: !on, onToggle: { on.toggle() })
            StarToggle(going: starred, onToggle: { starred.toggle() }, label: "A talk")
            GoingMark("RSVP’d to 2 of these")
            ClashTag()
        }
        HStack(spacing: 12) {
            StarToggle(going: true, onToggle: {}, onCard: true)
            StarToggle(going: false, onToggle: {}, onCard: true)
            ClashTag(onCard: true)
        }
        .padding(8)
        .background(colors.you)
    }
}
