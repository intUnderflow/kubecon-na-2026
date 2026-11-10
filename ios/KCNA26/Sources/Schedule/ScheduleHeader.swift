import SwiftUI

// Kotlin ui/schedule/ScheduleHeader.kt: the header (brand, clock, Settings, day tabs), the
// search field, the day and search headings and the "You’re speaking" banner. Texts and rules:
// Core's `ScheduleHeaderLogic`.

// MARK: - ScheduleHeader

/// Web `header.top` (Kotlin `ScheduleHeader`): brand + clock (+ Settings), then the day tabs and
/// a hairline. Stays put above the list; the page background runs under the status bar.
struct ScheduleHeader: View {
    let clock: String
    let tabs: [DayTab]
    let currentDay: String?
    let searching: Bool
    let sidePadding: CGFloat
    let onDay: (String) -> Void
    let onSettings: () -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(
        clock: String,
        tabs: [DayTab],
        currentDay: String?,
        searching: Bool,
        sidePadding: CGFloat,
        onDay: @escaping (String) -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.clock = clock
        self.tabs = tabs
        self.currentDay = currentDay
        self.searching = searching
        self.sidePadding = sidePadding
        self.onDay = onDay
        self.onSettings = onSettings
    }

    var body: some View {
        let side = CGFloat(Dimens.touchTarget)
        let trailing = CGFloat(ScheduleHeaderLogic.headerTrailingPadding(Double(sidePadding)))
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                runsText(ScheduleHeaderLogic.BRAND, style: type.brand, colors: colors)
                    .appTextStyle(type.brand)
                    .foregroundStyle(colors.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                CapsText(clock, style: type.clock, color: colors.muted, lineLimit: 1)
                Button(action: onSettings) {
                    AppIconImage(.settings, size: 24)
                        .foregroundStyle(colors.muted)
                        .frame(width: side, height: side)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: ScheduleHeaderLogic.SETTINGS))
            }
            .padding(.leading, sidePadding)
            .padding(.trailing, trailing)
            .frame(minHeight: side)
            DayTabs(tabs: tabs, currentDay: ScheduleHeaderLogic.dayTabsCurrent(currentDay, searching: searching), onDay: onDay)
                .padding(.horizontal, sidePadding)
                .padding(.top, 6)
                .padding(.bottom, 10)
            HairlineDivider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.bg)
    }
}

/// Web `.days` (Kotlin `DayTabs`): equal-width tabs; the current one inverted; a pink "YOU"
/// badge on days I still speak. VoiceOver: "Today, Wednesday, Nov 11, you’re speaking".
private struct DayTabs: View {
    let tabs: [DayTab]
    let currentDay: String?
    let onDay: (String) -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(tabs, id: \.key) { tab in
                tabButton(tab, on: tab.key == currentDay)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tabButton(_ tab: DayTab, on: Bool) -> some View {
        let key: String = tab.key
        return Button {
            onDay(key)
        } label: {
            VStack(alignment: .center, spacing: 2) {
                CapsText(tab.label, style: type.dayTabLabel, color: on ? colors.bg.opacity(0.75) : colors.muted, lineLimit: 1)
                CapsText(String(tab.number), style: type.dayTabNumber, color: on ? colors.bg : colors.ink, lineLimit: 1)
            }
            .padding(.top, 7)
            .padding(.bottom, 6)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 50)
            .tileSurface(selected: on)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if tab.hasMine {
                // Part of the tab's description, so hidden from VoiceOver.
                Pill(ScheduleHeaderLogic.YOU_BADGE, tone: .you, size: .badge)
                    .offset(x: 4, y: -7)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ScheduleHeaderLogic.dayTabDescription(tab)))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Search field

/// Web `.search` (Kotlin `ScheduleSearchField`): "Search talks, speakers, rooms" with a clear
/// button, 14 pt below the banner area.
struct ScheduleSearchField: View {
    @Binding var text: String
    let focus: FocusState<Bool>.Binding

    init(text: Binding<String>, focus: FocusState<Bool>.Binding) {
        _text = text
        self.focus = focus
    }

    var body: some View {
        SearchField(text: $text, placeholder: ScheduleHeaderLogic.SEARCH_PLACEHOLDER, focus: focus)
            .padding(.top, 14)
    }
}

// MARK: - Headings

/// Web `.dayhead` (Kotlin `DayHeading`): the day name (36 pt when `large`), its subtitle, and
/// today's "**3** ON NOW · NEXT AT **10:15 AM**". `trailing` sits at the end of the name's line
/// (the RSVP'd filter chip).
struct DayHeading<Trailing: View>: View {
    let view: DayView
    let large: Bool
    private let trailing: Trailing?

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(_ view: DayView, large: Bool, @ViewBuilder trailing: () -> Trailing) {
        self.view = view
        self.large = large
        self.trailing = trailing()
    }

    var body: some View {
        let style: AppTextStyle = large ? type.dayHeading.copy(size: 36, lineHeight: 37) : type.dayHeading
        VStack(alignment: .leading, spacing: 0) {
            HeadingLine(trailing: trailing) {
                CapsText(view.day.label, style: style, color: colors.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(verbatim: view.day.subtitle)
                .appTextStyle(type.body)
                .foregroundStyle(colors.muted)
                .padding(.top, 4)
                .widthIn(max: CGFloat(Dimens.maxTextWidth))
            if let st = view.status {
                runsText(ScheduleHeaderLogic.dayStatusLine(st), style: type.status, colors: colors)
                    .appTextStyle(type.status)
                    .foregroundStyle(colors.muted)
                    .padding(.top, 10)
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DayHeading where Trailing == EmptyView {
    /// A day heading without a trailing item.
    init(_ view: DayView, large: Bool) {
        self.view = view
        self.large = large
        self.trailing = nil
    }
}

/// Web search heading (Kotlin `SearchHeading`): "12 MATCHES", with an optional `trailing` chip
/// at the end of the line.
struct SearchHeading<Trailing: View>: View {
    let text: String
    let large: Bool
    private let trailing: Trailing?

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(_ text: String, large: Bool, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.large = large
        self.trailing = trailing()
    }

    var body: some View {
        let style: AppTextStyle = large ? type.dayHeading.copy(size: 36, lineHeight: 37) : type.dayHeading
        HeadingLine(trailing: trailing) {
            CapsText(text, style: style, color: colors.ink)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 18)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SearchHeading where Trailing == EmptyView {
    init(_ text: String, large: Bool) {
        self.text = text
        self.large = large
        self.trailing = nil
    }
}

/// A heading with an optional `trailing` item at the end of its line (Kotlin `HeadingLine`):
/// the title takes the rest of the width, 8 pt before the item, both centred vertically.
private struct HeadingLine<Title: View, Trailing: View>: View {
    let trailing: Trailing?
    let title: Title

    init(trailing: Trailing?, @ViewBuilder title: () -> Title) {
        self.trailing = trailing
        self.title = title()
    }

    var body: some View {
        if let trailing {
            HStack(alignment: .center, spacing: 8) {
                title
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
        } else {
            title
        }
    }
}

// MARK: - MineBannerCard

/// Web `.mine` (Kotlin `MineBannerCard`): "YOU’RE SPEAKING" with a countdown chip (pulsing while
/// the talk is soon or on), my next talk (time, title, "Head to {room} · {building}"), and my
/// later talks that day. Tapping a talk jumps to it in the list and opens it (`onTalk`).
struct MineBannerCard: View {
    let banner: MineBanner
    let onTalk: (Session) -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(banner: MineBanner, onTalk: @escaping (Session) -> Void) {
        self.banner = banner
        self.onTalk = onTalk
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(Dimens.bannerRadius), style: .circular)
        let white: Color = colors.onYou
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                CapsText(ScheduleHeaderLogic.BANNER_LABEL, style: type.bannerLabel, color: white, lineLimit: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                BannerCountdown(text: banner.countdown, pulse: banner.soon)
            }
            nextTalk(white: white)
            if !banner.later.isEmpty {
                HairlineDivider(color: white.opacity(0.3))
                ForEach(0..<banner.later.count, id: \.self) { i in
                    if i > 0 {
                        HairlineDivider(color: white.opacity(0.18))
                    }
                    laterTalk(banner.later[i], white: white)
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.top, 11)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { shape.fill(colors.you) }
        .clipShape(shape)
        .mineShadow(colors.you)
        .padding(.top, 12)
    }

    private func nextTalk(white: Color) -> some View {
        let next: Session = banner.next
        let soon: Bool = banner.soon
        let whereWeight: AppFontWeight = soon ? .bold : .regular
        let whereStyle: AppTextStyle = type.small.copy(size: 14.5, weight: whereWeight)
        return Button {
            onTalk(next)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                CapsText(banner.nextTime, style: type.bannerTime, color: white.opacity(0.9))
                Text(verbatim: next.title)
                    .appTextStyle(type.bannerTitle)
                    .foregroundStyle(white)
                    .padding(.top, 2)
                Text(verbatim: banner.nextWhere)
                    .appTextStyle(whereStyle)
                    .foregroundStyle(soon ? white : white.opacity(0.92))
                    .padding(.top, 3)
            }
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(verbatim: ScheduleCardsLogic.OPEN_DETAILS))
    }

    private func laterTalk(_ x: LaterTalk, white: Color) -> some View {
        let text = ScheduleHeaderLogic.bannerLaterText(x)
        let style: AppTextStyle = type.small.copy(size: 14.5, lineHeight: 19)
        let timeStyle: AppTextStyle = type.bannerTime.copy(letterSpacing: type.bannerCountdown.letterSpacing)
        let session: Session = x.session
        return Button {
            onTalk(session)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                CapsText(x.time, style: timeStyle, color: white, lineLimit: 1)
                (Text(verbatim: text.title) + Text(verbatim: text.room).foregroundStyle(white.opacity(0.8)))
                    .appTextStyle(style)
                    .foregroundStyle(white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: CGFloat(Dimens.touchTarget), alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(verbatim: ScheduleCardsLogic.OPEN_DETAILS))
    }
}

/// Web `.mine-h .cd` (Kotlin `Countdown`): white chip with pink text; pulses (1 -> 1.08, 800 ms
/// FastOutSlowIn, reversing) while the talk is soon or on. Still with Reduce Motion.
private struct BannerCountdown: View {
    let text: String
    let pulse: Bool

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let chip = CapsText(text, style: type.bannerCountdown, color: colors.you, lineLimit: 1)
            .padding(.leading, 7)
            .padding(.trailing, 7)
            .padding(.top, 4)
            .padding(.bottom, 3)
            .background { RoundedRectangle(cornerRadius: 6, style: .circular).fill(colors.onYou) }
        if pulse && !reduceMotion {
            chip.phaseAnimator([false, true]) { content, up in
                content.scaleEffect(up ? 1.08 : 1)
            } animation: { _ in
                .timingCurve(0.4, 0, 0.2, 1, duration: 0.8)
            }
        } else {
            chip
        }
    }
}
