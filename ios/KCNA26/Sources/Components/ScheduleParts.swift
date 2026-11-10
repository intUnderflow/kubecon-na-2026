import SwiftUI

// Kotlin ui/schedule/ScheduleParts.kt: Pill, RuledHeading, UpNextLine, EmptyState,
// ScheduleFooter and speakersLine. The card Modifier helpers (cardSurface, dashedOutline) are in
// CardSurface.swift.

// MARK: - Pill

/// The pill metrics of the Kotlin screens.
enum PillSize: Sendable, Equatable {
    /// ScheduleParts `Pill`: `type.pill` (12.5), padding 6 / 2 / 1 (cards, group and co-located heads).
    case regular
    /// The details' `Pill`: `type.pill` at 13, padding 7 / 4 / 3 ("You’re speaking", "Live · …").
    case large
    /// The details' `Pill(small = true)` and the day tab's "YOU" badge: `type.badge` (11), padding 5 / 3 / 2.
    case badge
    /// A group card kid row's inline pill (`KidPillStyle`): `type.pill` bold 11.5, 0.08 em, padding 5 / 3 / 2.
    case kid

    func style(_ type: AppType) -> AppTextStyle {
        switch self {
        case .regular: return type.pill
        case .large: return type.pill.copy(size: 13)
        case .badge: return type.badge
        case .kid: return type.pill.copy(size: 11.5, letterSpacing: 0.08, weight: .bold)
        }
    }

    var padding: EdgeInsets {
        switch self {
        case .regular: return EdgeInsets(top: 2, leading: 6, bottom: 1, trailing: 6)
        case .large: return EdgeInsets(top: 4, leading: 7, bottom: 3, trailing: 7)
        case .badge, .kid: return EdgeInsets(top: 3, leading: 5, bottom: 2, trailing: 5)
        }
    }
}

/// The colour pairs the Kotlin pills use, resolved from the theme.
enum PillTone: Sendable, Equatable {
    /// `you` on `onYou`: "Live", "You", "Live · 12 min left", kid "Live".
    case you
    /// `onYou` with `you` text: pills on my own (pink) cards and rows: "You’re speaking", kid "You".
    case onYou
    /// `anthropic` with `onAnthropic` text: "Anthropic".
    case anthropic
    /// `clash` with `surface` text: "Clash" (Kotlin `ClashTag`; on my cards use ``onYou``).
    case clash

    func colors(_ c: AppColors) -> (background: Color, content: Color) {
        switch self {
        case .you: return (c.you, c.onYou)
        case .onYou: return (c.onYou, c.you)
        case .anthropic: return (c.anthropic, c.onAnthropic)
        case .clash: return (c.clash, c.surface)
        }
    }
}

/// Web `.pill` / `.tag`: a small uppercase label on a 5 pt rounded fill. With `border` it is an
/// outline instead of a fill (`.tag`; the background is then not drawn, as in Kotlin).
struct Pill: View {
    private let text: String
    private let background: Color?
    private let content: Color?
    private let border: Color?
    private let tone: PillTone?
    private let size: PillSize
    private let style: AppTextStyle?

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    /// Kotlin `Pill(text, background, content, border = null, style = type.pill)`.
    init(_ text: String, background: Color, content: Color, border: Color? = nil,
         size: PillSize = .regular, style: AppTextStyle? = nil) {
        self.text = text
        self.background = background
        self.content = content
        self.border = border
        self.tone = nil
        self.size = size
        self.style = style
    }

    /// A pill in one of the theme's colour pairs, e.g. `Pill("Anthropic", tone: .anthropic)`.
    init(_ text: String, tone: PillTone, size: PillSize = .regular, style: AppTextStyle? = nil) {
        self.text = text
        self.background = nil
        self.content = nil
        self.border = nil
        self.tone = tone
        self.size = size
        self.style = style
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .circular)
        let resolved = resolvedColors
        CapsText(text, style: style ?? size.style(type), color: resolved.content, lineLimit: 1)
            .padding(size.padding)
            .background {
                if border == nil {
                    shape.fill(resolved.background)
                }
            }
            .overlay {
                if let border {
                    shape.stroke(border, lineWidth: 1)
                }
            }
    }

    private var resolvedColors: (background: Color, content: Color) {
        if let tone {
            return tone.colors(colors)
        }
        return (background ?? Color.clear, content ?? colors.ink)
    }
}

// MARK: - Headings

/// Web `.slot>h3` / `.sect>h3`: uppercase heading with a hairline running to the right edge, on
/// the page background (sticky in the list: use it as a pinned `Section` header of a
/// `LazyVStack(pinnedViews: .sectionHeaders)`). Kotlin `RuledHeading(text, topPadding = 10.dp)`.
struct RuledHeading: View {
    let text: String
    var topPadding: CGFloat

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(_ text: String, topPadding: CGFloat = 10) {
        self.text = text
        self.topPadding = topPadding
    }

    var body: some View {
        HStack(spacing: 10) {
            CapsText(text, style: type.slotHeading, color: colors.ink, lineLimit: 1)
                .layoutPriority(1)
            Rectangle()
                .fill(colors.line)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .padding(.top, topPadding)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity)
        .background(colors.bg)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Web `.nowline`: pink "UP NEXT" with a 2 pt rule.
struct UpNextLine: View {
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        HStack(spacing: 8) {
            CapsText("Up next", style: type.nowLine, color: colors.you)
                .layoutPriority(1)
            Rectangle()
                .fill(colors.you)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .padding(.top, 14)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty state and footer

/// Web `.empty`: "That’s a wrap for today" / "No matches" (texts from Core: `ScheduleRows`,
/// `GoingLogic.emptyText`) in a dashed box.
struct EmptyState: View {
    let title: String
    let text: String

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    var body: some View {
        let titleStyle = type.slotHeading.copy(size: 20, lineHeight: 22, letterSpacing: type.brand.letterSpacing)
        VStack(spacing: 4) {
            CapsText(title, style: titleStyle, color: colors.ink)
                .multilineTextAlignment(.center)
            Text(verbatim: text)
                .appTextStyle(type.body)
                .foregroundStyle(colors.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .dashedOutline(colors.line, radius: 12)
        .padding(.vertical, 28)
    }
}

/// Web footer under the list.
struct ScheduleFooter: View {
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    /// The footer text, verbatim from Kotlin.
    static let text = "Times are MST. Finished sessions disappear on their own. Schedule copied from the " +
        "official KubeCon and Maintainer Summit agendas on Nov 8 at 9:20 AM; “~” durations are estimates."

    var body: some View {
        Text(verbatim: ScheduleFooter.text)
            .appTextStyle(type.small.copy(size: 13.5))
            .foregroundStyle(colors.muted)
            .widthIn(max: CGFloat(Dimens.maxTextWidth))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 36)
            .padding(.bottom, 24)
    }
}

// MARK: - Speakers line

/// Web `who(x)`: speakers joined by ", ", with me shown as bold "You" and Anthropic colleagues
/// in bold clay. On my own (pink) cards every bold name is white (`onMine`). `style` is the
/// line's text style (`type.small` on cards, `type.tiny` in kid rows): its bold face draws the
/// highlighted names. Show it with `.appTextStyle(style)` and the muted (or `onYou`) colour:
///
///     speakersLine(s.speakers, me: me, anthropic: index.anthropicSpeakers, colors: colors,
///                  onMine: mine, style: type.small)
///         .appTextStyle(type.small)
///         .foregroundStyle(mine ? colors.onYou : colors.muted)
func speakersLine(
    _ speakers: [String],
    me: String?,
    anthropic: Set<String>,
    colors: AppColors,
    onMine: Bool,
    style: AppTextStyle
) -> Text {
    let boldFont: Font = style.bold.font
    var line = Text(verbatim: "")
    for (i, name) in speakers.enumerated() {
        if i > 0 {
            line = line + Text(verbatim: ", ")
        }
        if let me, name == me {
            var you = Text(verbatim: speakerLabel(name, me)).font(boldFont)
            if onMine {
                you = you.foregroundStyle(colors.onYou)
            }
            line = line + you
        } else if anthropic.contains(name) {
            let tint: Color = onMine ? colors.onYou : colors.anthropic
            line = line + Text(verbatim: name).font(boldFont).foregroundStyle(tint)
        } else {
            line = line + Text(verbatim: name)
        }
    }
    return line
}

// MARK: - Previews

#Preview("Pills") {
    ThemePreview {
        PillSpecimen()
    }
}

#Preview("Headings, empty state, footer") {
    ThemePreview {
        RuledHeading("10:00 AM")
        UpNextLine()
        RuledHeading("Co-located + off-site", topPadding: 16)
        EmptyState(title: "That’s a wrap for today", text: "Pick the next day above.")
        ScheduleFooter()
    }
}

#Preview("Speakers line") {
    ThemePreview {
        SpeakersSpecimen()
    }
}

private struct PillSpecimen: View {
    @Environment(\.appColors) private var colors

    var body: some View {
        FlowRow(horizontalSpacing: 10, verticalSpacing: 4, itemAlignment: .center) {
            Pill("Live · 12 min left", tone: .you)
            Pill("Anthropic", tone: .anthropic)
            Pill("Clash", tone: .clash)
            Pill("Lightning", background: Color.clear, content: colors.muted, border: colors.line)
            Pill("You’re speaking", tone: .you, size: .large)
            Pill("Anthropic", tone: .anthropic, size: .badge)
            Pill("Live", tone: .you, size: .kid)
        }
        HStack(spacing: 10) {
            Pill("You’re speaking", tone: .onYou)
            Pill("Live", tone: .onYou)
        }
        .padding(10)
        .background(colors.you)
    }
}

private struct SpeakersSpecimen: View {
    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    var body: some View {
        let speakers: [String] = ["Lucy Sweet", "Ada Lovelace", "Grace Hopper"]
        let anthropic: Set<String> = ["Lucy Sweet", "Grace Hopper"]
        speakersLine(speakers, me: "Lucy Sweet", anthropic: anthropic, colors: colors, onMine: false, style: type.small)
            .appTextStyle(type.small)
            .foregroundStyle(colors.muted)
        speakersLine(speakers, me: nil, anthropic: anthropic, colors: colors, onMine: false, style: type.small)
            .appTextStyle(type.small)
            .foregroundStyle(colors.muted)
        speakersLine(speakers, me: "Lucy Sweet", anthropic: anthropic, colors: colors, onMine: true, style: type.small)
            .appTextStyle(type.small)
            .foregroundStyle(colors.onYou)
            .padding(10)
            .background(colors.you)
    }
}
