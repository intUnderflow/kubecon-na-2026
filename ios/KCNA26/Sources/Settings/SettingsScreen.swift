import SwiftUI

/// Kotlin ui/settings/SettingsScreen.kt `SettingsScreen`: pushed on the navigation stack.
///
/// The RSVP reminder choice (``GoingReminderSetting``), where the schedule data came from
/// (``DataSourceRow``), then "I’m speaking as" (default None; any speaker in the schedule,
/// searchable, the search field pinned while the list scrolls). Choosing a speaker updates
/// everything "mine" at once: the banner, highlights, "You" labels and day-tab badges follow
/// `settings.speakingAs`, and the app re-plans the reminders whenever it changes (AppGraph). The
/// theme follows the system, so there is no control for it. iOS adds the credits, the bundled
/// font licences and the app version at the end (``SettingsScreenLogic`` "+UI"; Android has
/// them only in its assets and README).
///
/// One centred column of at most `Dimens.maxTextWidth` on wide windows. Header: the system
/// navigation bar (its back button and edge swipe pop) with "SETTINGS" as its title, in place of
/// Kotlin's own top bar.
///
/// - Parameter onBack: leave Settings (``NavModel/pop()``). The system back button and the edge
///   swipe pop the stack themselves, so the screen has no back control of its own.
struct SettingsScreen: View {
    let onBack: () -> Void

    @Environment(AppGraph.self) private var graph
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    @State private var search = ""
    @State private var memo = SpeakerOptionsMemo()
    @State private var openLicense: LicenseItem?
    @FocusState private var searchFocused: Bool

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
    }

    var body: some View {
        let settings: SettingsStore = graph.settings
        let me: String? = settings.speakingAs
        let options: [SpeakerOption] = memo.options(graph.repository)
        let terms: [String] = SpeakerPicker.terms(search)
        let shown: [SpeakerOption] = SettingsScreenLogic.shown(options, search)
        let current: SpeakerOption? = SettingsScreenLogic.current(options, me)
        let title: String = SettingsScreenLogic.TITLE
        GeometryReader { geo in
            let side: CGFloat = PageLayout.sidePadding(forWidth: geo.size.width, maxContent: CGFloat(Dimens.maxTextWidth))
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // "Remind me before sessions I’ve RSVP’d to": Off / 5 / 10 / 15 min.
                    VStack(alignment: .leading, spacing: 0) {
                        GoingReminderSetting()
                        HairlineDivider()
                            .padding(.top, 18)
                    }
                    .padding(.top, 18)
                    DataSourceRow()
                        .padding(.top, 18)
                    SpeakingAsIntro(me: me, current: current)
                        .padding(.top, 18)
                    Section {
                        OptionRow(
                            title: SettingsScreenLogic.NONE,
                            subtitle: SettingsScreenLogic.NONE_SUBTITLE,
                            selected: me == nil,
                            onClick: { choose(nil, me, settings) }
                        )
                        ForEach(shown, id: \.name) { o in
                            OptionRow(
                                title: o.name,
                                subtitle: o.summary,
                                selected: me.map { kotlinEquals($0, o.name) } ?? false,
                                onClick: { choose(o.name, me, settings) }
                            )
                        }
                        if SettingsScreenLogic.showsNoMatch(shown, terms) {
                            Text(verbatim: SettingsScreenLogic.noMatchText(search))
                                .appTextStyle(type.body)
                                .foregroundStyle(colors.muted)
                                .padding(.vertical, 16)
                        }
                        Text(verbatim: SettingsScreenLogic.THEME_NOTE)
                            .appTextStyle(type.small)
                            .foregroundStyle(colors.muted)
                            .padding(.top, 24)
                        CreditsSection(onLicense: { openLicense = LicenseItem(license: $0) })
                    } header: {
                        SearchField(
                            text: $search,
                            placeholder: SettingsScreenLogic.SEARCH_PLACEHOLDER,
                            autocapitalization: .words,
                            focus: $searchFocused
                        )
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                        .background(colors.bg)
                    }
                }
                .padding(.leading, side)
                .padding(.trailing, side)
                .padding(.bottom, 24)
            }
        }
        .background(colors.bg)
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                CapsText(title, style: type.dayHeading.copy(size: 26, lineHeight: 28), color: colors.ink, lineLimit: 1)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .toolbarBackground(colors.bg, for: .navigationBar)
        .sheet(item: $openLicense) { item in
            LicenseSheet(license: item.license)
        }
    }

    /// Kotlin `choose`: drop the keyboard; set "I’m speaking as" only when it changes.
    private func choose(_ name: String?, _ me: String?, _ settings: SettingsStore) {
        searchFocused = false
        if SettingsScreenLogic.shouldChoose(name, me) {
            settings.setSpeakingAs(name)
        }
    }
}

/// "I’M SPEAKING AS", the current choice in big type (the name in pink, or "None" in ink), the
/// line under it (sessions and days, "Not on the schedule.", or no reminders), and what being a
/// speaker does.
private struct SpeakingAsIntro: View {
    let me: String?
    let current: SpeakerOption?

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(SettingsScreenLogic.SPEAKING_AS)
            Text(verbatim: SettingsScreenLogic.speakingAsName(me))
                .appTextStyle(type.sheetTitle)
                .foregroundStyle(me != nil ? colors.you : colors.ink)
                .padding(.top, 8)
            Text(verbatim: SettingsScreenLogic.speakingAsSummary(me, current))
                .appTextStyle(type.small)
                .foregroundStyle(colors.muted)
                .padding(.top, 2)
            Text(verbatim: SettingsScreenLogic.INTRO)
                .appTextStyle(type.body)
                .foregroundStyle(colors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A radio-style row (Kotlin `OptionRow`): the name (bold pink when selected), a muted summary
/// line, a pink check when selected; at least 56 pt, a hairline under it. VoiceOver: a button,
/// "Selected" when it is the current choice (iOS has no radio-button trait).
struct OptionRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let onClick: () -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(title: String, subtitle: String, selected: Bool, onClick: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        self.onClick = onClick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onClick) {
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: title)
                            .appTextStyle(selected ? type.body.bold : type.body)
                            .foregroundStyle(selected ? colors.you : colors.ink)
                        if !subtitle.isEmpty {
                            Text(verbatim: subtitle)
                                .appTextStyle(type.tiny)
                                .foregroundStyle(colors.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if selected {
                        AppIconImage(.check, size: 24)
                            .foregroundStyle(colors.you)
                            .padding(.leading, 12)
                    }
                }
                .padding(.vertical, 8)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            HairlineDivider()
        }
    }
}

// MARK: - Credits (iOS)

/// The end of the list on iOS (no Kotlin counterpart, see ``SettingsScreenLogic`` "+UI"): a
/// hairline, "CREDITS", where the data comes from, one row per bundled font (tap: its licence),
/// "unofficial community app", the app version.
private struct CreditsSection: View {
    let onLicense: (SettingsScreenLogic.FontLicense) -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        let version: String? = SettingsScreenLogic.appVersion(from: Bundle.main)
        let pick: (SettingsScreenLogic.FontLicense) -> Void = onLicense
        VStack(alignment: .leading, spacing: 0) {
            HairlineDivider()
                .padding(.top, 24)
            SectionLabel(SettingsScreenLogic.CREDITS)
                .padding(.top, 18)
            Text(verbatim: SettingsScreenLogic.DATA_CREDIT)
                .appTextStyle(type.small)
                .foregroundStyle(colors.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(SettingsScreenLogic.FONT_LICENSES, id: \.file) { license in
                PickRow(
                    title: license.name,
                    subtitle: SettingsScreenLogic.FONT_LICENSE_NAME,
                    accessibilityText: SettingsScreenLogic.licenseRowLabel(license),
                    onClick: { pick(license) }
                )
            }
            Text(verbatim: SettingsScreenLogic.UNOFFICIAL)
                .appTextStyle(type.small)
                .foregroundStyle(colors.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            if let version {
                Text(verbatim: version)
                    .appTextStyle(type.tiny)
                    .foregroundStyle(colors.muted)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The licence sheet's item (`.sheet(item:)` needs an `Identifiable`).
private struct LicenseItem: Identifiable {
    let license: SettingsScreenLogic.FontLicense
    var id: String { license.file }
}

/// A bundled font licence in full (`Licenses/<file>` in the app bundle): the font's name and
/// licence over the scrolling text; × closes it.
private struct LicenseSheet: View {
    let license: SettingsScreenLogic.FontLicense

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let text: String = SettingsScreenLogic.licenseText(license) ?? ""
        let pad = CGFloat(Dimens.pagePadding)
        let close: DismissAction = dismiss
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: license.name)
                        .appTextStyle(type.sheetTitle)
                        .foregroundStyle(colors.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: SettingsScreenLogic.FONT_LICENSE_NAME)
                        .appTextStyle(type.small)
                        .foregroundStyle(colors.muted)
                        .padding(.top, 2)
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                CloseButton(onClick: { close() })
            }
            .padding(.leading, pad)
            .padding(.trailing, pad - 10)
            .padding(.top, 20)
            .padding(.bottom, 8)
            HairlineDivider()
            ScrollView(.vertical) {
                Text(verbatim: text)
                    .appTextStyle(type.tiny)
                    .foregroundStyle(colors.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(pad)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(colors.bg)
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Speaker options

/// ``SpeakerPicker/options(_:)`` once per data set (Kotlin `remember(repo)`): a plain class in
/// `@State`, so the search field's keystrokes don't rebuild the list of every speaker.
@MainActor
final class SpeakerOptionsMemo {
    private var repo: Repository?
    private var cached: [SpeakerOption] = []

    init() {}

    func options(_ repo: Repository) -> [SpeakerOption] {
        if let held = self.repo, held === repo {
            return cached
        }
        cached = SpeakerPicker.options(repo)
        self.repo = repo
        return cached
    }
}

#Preview("Option rows") {
    ThemePreview {
        OptionRow(title: "None", subtitle: "Don’t mark any talks as mine", selected: false, onClick: {})
        OptionRow(title: "Lucy Sweet", subtitle: "3 sessions · Wed", selected: true, onClick: {})
    }
}
