import SwiftUI

/// Kotlin ui/settings/FirstRunSheet.kt `FirstRunSpeakerSheet`: "Speaking at KubeCon? Pick your
/// name", the content of the shell's first-run `.sheet` (``RootView``). The shell presents it
/// while ``AppGraph/showsFirstRunSheet`` (data loaded, `settings.firstRunPending`) with
/// `.presentationDetents([.large])`, and turns a swipe-down into
/// `settings.dismissFirstRunForNow()` (Kotlin `onDismissRequest`: only hidden until the next cold
/// start, since that is easy to do by accident). This view sets its own background
/// (`.presentationBackground(colors.bg)`) and the drag indicator (Kotlin's default sheet drag
/// handle), and finishes with `graph.settings.finishFirstRun(name)`: a picked name sets "I'm
/// speaking as" (and so the reminders), Skip (nil) leaves it at None; either way it never shows
/// again and the sheet closes by itself. It never calls `dismiss()` (that counts as a swipe-down).
///
/// The same searchable speaker list as Settings. One-handed: the search field and Skip sit at
/// the bottom, under the list; VoiceOver reads the title, the text, search and Skip first, then
/// the list. While the search field has the focus (the keyboard is up) the title and text are
/// hidden, so the list keeps its room with large text or in landscape.
struct FirstRunSpeakerSheet: View {
    @Environment(AppGraph.self) private var graph
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    @State private var search = ""
    @State private var memo = SpeakerOptionsMemo()
    @FocusState private var searchFocused: Bool

    init() {}

    var body: some View {
        let settings: SettingsStore = graph.settings
        let options: [SpeakerOption] = memo.options(graph.repository)
        // Kotlin SpeakerPicker.filter(options, terms, null): the Settings list.
        let shown: [SpeakerOption] = SettingsScreenLogic.shown(options, search)
        VStack(alignment: .leading, spacing: 0) {
            if !searchFocused {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: FirstRunSheetLogic.TITLE)
                        .appTextStyle(type.sheetTitle)
                        .foregroundStyle(colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: FirstRunSheetLogic.TEXT)
                        .appTextStyle(type.small)
                        .foregroundStyle(colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(2)
            }
            HairlineDivider()
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown, id: \.name) { o in
                        PickRow(title: o.name, subtitle: o.summary) {
                            finish(o.name, settings)
                        }
                    }
                    if FirstRunSheetLogic.showsNoMatch(shown) {
                        Text(verbatim: SettingsScreenLogic.noMatchText(search))
                            .appTextStyle(type.body)
                            .foregroundStyle(colors.muted)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)
            // After search and Skip in VoiceOver's order (they are below it on screen).
            .accessibilitySortPriority(0)
            VStack(alignment: .leading, spacing: 0) {
                SearchField(
                    text: $search,
                    placeholder: SettingsScreenLogic.SEARCH_PLACEHOLDER,
                    autocapitalization: .words,
                    focus: $searchFocused
                )
                // Kotlin OutlinedButton (Material's pill shape) with the button style, as written: "Skip".
                Button {
                    finish(nil, settings)
                } label: {
                    Text(verbatim: FirstRunSheetLogic.SKIP)
                        .appTextStyle(type.button)
                }
                .buttonStyle(OutlineButtonStyle(fillsWidth: true, shape: .capsule))
                .padding(.top, 10)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(1)
        }
        .padding(.horizontal, CGFloat(Dimens.pagePadding))
        // Room for the drag indicator (Material's drag handle sits above Kotlin's content).
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .presentationBackground(colors.bg)
        .presentationDragIndicator(.visible)
    }

    /// Kotlin `finish`: drop the keyboard, then answer (the sheet closes as `firstRunPending` clears).
    private func finish(_ name: String?, _ settings: SettingsStore) {
        searchFocused = false
        settings.finishFirstRun(name)
    }
}

/// A speaker row that picks the name and closes the sheet (Kotlin `PickRow`): a button, not a
/// radio button. The name over a muted summary, at least 56 pt, a hairline under it. Also the
/// licence rows at the end of Settings.
struct PickRow: View {
    let title: String
    let subtitle: String
    let accessibilityText: String?
    let onClick: () -> Void

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    /// - Parameter accessibilityText: VoiceOver's label instead of the title and subtitle.
    init(title: String, subtitle: String, accessibilityText: String? = nil, onClick: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.accessibilityText = accessibilityText
        self.onClick = onClick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onClick) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: title)
                        .appTextStyle(type.body)
                        .foregroundStyle(colors.ink)
                    if !subtitle.isEmpty {
                        Text(verbatim: subtitle)
                            .appTextStyle(type.tiny)
                            .foregroundStyle(colors.muted)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(OptionalAccessibilityLabel(text: accessibilityText))
            HairlineDivider()
        }
    }
}

/// `.accessibilityLabel` when a text is given; else the view's own.
private struct OptionalAccessibilityLabel: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.accessibilityLabel(Text(verbatim: text))
        } else {
            content
        }
    }
}

#Preview("Pick rows") {
    ThemePreview {
        PickRow(title: "Lucy Sweet", subtitle: "3 sessions · Wed", onClick: {})
        PickRow(title: "Ada Lovelace", subtitle: "1 session · Sun, Tue", onClick: {})
    }
}
