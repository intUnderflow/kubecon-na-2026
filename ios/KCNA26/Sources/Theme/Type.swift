import SwiftUI

// Kotlin theme/Type.kt: the two bundled families, the named text styles (`AppType`), the
// Material typography (`KcnaTypography`) and `CapsText`.
//
// Sizes are Android sp = iOS points. Every style scales with Dynamic Type (`Font.custom(_:size:
// relativeTo:)`, the curve of the iOS text style closest in size). Letter spacing (em) and line
// height (points; the spacing of wrapped lines, as Compose applies it) are applied by
// `.appTextStyle(_:)`, which scales them the same way.

// MARK: - Fonts

/// The four bundled font files (Resources/Fonts, registered by Info.plist `UIAppFonts`), by
/// PostScript name (read from each file's `name` table, ID 6).
enum AppFontFace: String, CaseIterable, Sendable {
    /// barlow_condensed_semibold.ttf (weight 600).
    case barlowSemiBold = "BarlowCondensed-SemiBold"
    /// barlow_condensed_bold.ttf (weight 700).
    case barlowBold = "BarlowCondensed-Bold"
    /// atkinson_hyperlegible_regular.ttf (weight 400).
    case atkinsonRegular = "AtkinsonHyperlegible-Regular"
    /// atkinson_hyperlegible_bold.ttf (weight 700).
    case atkinsonBold = "AtkinsonHyperlegible-Bold"

    /// The name `Font.custom` takes.
    var postScriptName: String { rawValue }
}

/// Font weights the styles use (Kotlin `FontWeight.Normal`, `SemiBold`, `Bold`).
enum AppFontWeight: Sendable, Equatable {
    case regular
    case semibold
    case bold
}

/// Kotlin `Barlow` / `Atkinson` font families.
enum AppFontFamily: Sendable, Equatable {
    /// Barlow Condensed SemiBold (600) + Bold (700): headings, times, labels. Always UPPERCASE
    /// (`caps()` / ``CapsText``).
    case barlow
    /// Atkinson Hyperlegible Regular (400) + Bold (700): body text and titles.
    case atkinson

    /// The face for a weight, with Android's fallback when the family lacks it (CSS font
    /// matching: 600 in Atkinson -> Bold; 400 in Barlow -> SemiBold).
    func face(_ weight: AppFontWeight) -> AppFontFace {
        switch self {
        case .barlow:
            return weight == .bold ? .barlowBold : .barlowSemiBold
        case .atkinson:
            return weight == .regular ? .atkinsonRegular : .atkinsonBold
        }
    }

    /// Ascent in em (hhea = OS/2 typo, USE_TYPO_METRICS set; the same on Android and iOS).
    var ascent: CGFloat {
        switch self {
        case .barlow: return 1.0
        case .atkinson: return 0.95
        }
    }

    /// Descent in em (positive).
    var descent: CGFloat {
        switch self {
        case .barlow: return 0.2
        case .atkinson: return 0.29
        }
    }
}

// MARK: - Text style

/// A Compose `TextStyle` of this app: family, weight, size, letter spacing and line height.
/// Colours are not part of it (use `@Environment(\.appColors)`). Barlow styles must be shown
/// uppercased (``CapsText`` or `caps()`).
///
/// Apply to any view with `.appTextStyle(style)`; inside `Text` concatenations use
/// `Text(...).appFont(style)` (font and tracking only).
struct AppTextStyle: Equatable, Sendable {
    var family: AppFontFamily
    var weight: AppFontWeight
    /// Font size in points (Android sp).
    var size: CGFloat
    /// Letter spacing in em (Kotlin `letterSpacing = x.em`).
    var letterSpacing: CGFloat
    /// Line height in points (absolute, like Compose's `lineHeight` in sp: `copy(size:)` keeps it).
    var lineHeight: CGFloat
    /// Tabular figures (Kotlin `fontFeatureSettings = "tnum"`, on every Barlow style).
    var tabularNumbers: Bool

    /// Kotlin `barlow(size, weight = Bold, spacing = 0.05f, lineHeight = 1.15f)`.
    static func barlow(
        _ size: CGFloat,
        _ weight: AppFontWeight = .bold,
        spacing: CGFloat = 0.05,
        lineHeight: CGFloat = 1.15
    ) -> AppTextStyle {
        AppTextStyle(family: .barlow, weight: weight, size: size, letterSpacing: spacing,
                     lineHeight: size * lineHeight, tabularNumbers: true)
    }

    /// Kotlin `atkinson(size, weight = Normal, lineHeight = 1.4f)`.
    static func atkinson(
        _ size: CGFloat,
        _ weight: AppFontWeight = .regular,
        lineHeight: CGFloat = 1.4
    ) -> AppTextStyle {
        AppTextStyle(family: .atkinson, weight: weight, size: size, letterSpacing: 0,
                     lineHeight: size * lineHeight, tabularNumbers: false)
    }

    /// Kotlin `style.copy(fontSize =, lineHeight =, letterSpacing =, fontWeight =)`. Sizes in
    /// points, `letterSpacing` in em. Like Compose, a new size keeps the old absolute line height.
    func copy(
        size: CGFloat? = nil,
        lineHeight: CGFloat? = nil,
        letterSpacing: CGFloat? = nil,
        weight: AppFontWeight? = nil
    ) -> AppTextStyle {
        var s = self
        if let size { s.size = size }
        if let lineHeight { s.lineHeight = lineHeight }
        if let letterSpacing { s.letterSpacing = letterSpacing }
        if let weight { s.weight = weight }
        return s
    }

    /// `copy(fontWeight = FontWeight.Bold)`, e.g. a bold span inside `small` text.
    var bold: AppTextStyle { copy(weight: .bold) }

    /// The bundled face for this family and weight.
    var face: AppFontFace { family.face(weight) }

    /// The Dynamic Type curve this style scales with.
    var textStyle: Font.TextStyle { AppTextStyle.dynamicTypeStyle(forSize: size) }

    /// The SwiftUI font (Dynamic Type aware; tabular figures for Barlow).
    var font: Font {
        let base = Font.custom(face.postScriptName, size: size, relativeTo: textStyle)
        return tabularNumbers ? base.monospacedDigit() : base
    }

    /// Letter spacing in points at the default text size.
    var tracking: CGFloat { letterSpacing * size }

    /// The font's own line height on iOS (and Android): (ascent + descent) x size.
    var naturalLineHeight: CGFloat { (family.ascent + family.descent) * size }

    /// ``lineHeight`` minus ``naturalLineHeight``; negative for the tight Barlow styles.
    var extraLeading: CGFloat { lineHeight - naturalLineHeight }

    /// Space between lines. Compose's default `LineHeightStyle` (Proportional, `Trim.Both`,
    /// `Mode.Fixed`; Compose ui-text 1.12) keeps a single line at the font's natural height and
    /// the first line's top / last line's bottom at the font's ascent / descent, so only the
    /// baseline-to-baseline distance of wrapped lines follows ``lineHeight``: a text of n lines
    /// is `naturalLineHeight + (n - 1) x lineHeight` tall, which is exactly this line spacing.
    /// `lineSpacing` cannot be negative on iOS 17, so the wrapped lines of a style tighter than
    /// the font (Barlow below 1.2 em) keep the font's own spacing (a little taller than Android).
    var lineSpacing: CGFloat { max(0, extraLeading) }

    /// The iOS text style with the nearest default (Large) size; ties go to the smaller one.
    static func dynamicTypeStyle(forSize size: CGFloat) -> Font.TextStyle {
        var best: Font.TextStyle = .body
        var bestDistance: CGFloat = .greatestFiniteMagnitude
        for entry in dynamicTypeSizes {
            let d: CGFloat = abs(entry.size - size)
            if d < bestDistance {
                bestDistance = d
                best = entry.style
            }
        }
        return best
    }

    /// iOS default sizes of the text styles at the Large content size, ascending.
    private static let dynamicTypeSizes: [(size: CGFloat, style: Font.TextStyle)] = [
        (11, .caption2), (12, .caption), (13, .footnote), (15, .subheadline), (16, .callout),
        (17, .body), (20, .title3), (22, .title2), (28, .title), (34, .largeTitle),
    ]
}

/// Applies an ``AppTextStyle``: font, letter spacing and line spacing (the line height of
/// wrapped lines), all scaled with Dynamic Type like the font. No padding: a single line is the
/// font's natural height, as in Compose (see ``AppTextStyle/lineSpacing``).
struct AppTextStyleModifier: ViewModifier {
    let style: AppTextStyle
    @ScaledMetric private var scaledSize: CGFloat

    init(_ style: AppTextStyle) {
        self.style = style
        _scaledSize = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
    }

    func body(content: Content) -> some View {
        let k: CGFloat = style.size > 0 ? scaledSize / style.size : 1
        content
            .font(style.font)
            .tracking(style.tracking * k)
            .lineSpacing(style.lineSpacing * k)
    }
}

extension View {
    /// Kotlin `Text(..., style = t.body)`: font, letter spacing and line height of `style`.
    func appTextStyle(_ style: AppTextStyle) -> some View {
        modifier(AppTextStyleModifier(style))
    }
}

extension Text {
    /// A span's style inside a `Text` concatenation (Kotlin `SpanStyle`): font and letter
    /// spacing only (line height belongs to the whole text: apply `.appTextStyle` to it).
    func appFont(_ style: AppTextStyle) -> Text {
        font(style.font).tracking(style.tracking)
    }
}

// MARK: - Named styles

/// Named text styles matching the web CSS (Kotlin `AppType`). Read with
/// `@Environment(\.appType) private var type`. Barlow styles must be shown uppercased
/// (``CapsText``); colours are not set (use `@Environment(\.appColors)`).
struct AppType: Equatable, Sendable {
    /// Header brand "KUBECON NA 2026" (.brand h1): Barlow 700 21.
    var brand: AppTextStyle = .barlow(21, spacing: 0.03, lineHeight: 1)
    /// Header clock (.clock): Barlow 600 16, muted.
    var clock: AppTextStyle = .barlow(16, .semibold, spacing: 0.05, lineHeight: 1)
    /// Day tab weekday (.day small): Barlow 600 12.5.
    var dayTabLabel: AppTextStyle = .barlow(12.5, .semibold, spacing: 0.08, lineHeight: 1)
    /// Day tab number (.day b): Barlow 700 22.
    var dayTabNumber: AppTextStyle = .barlow(22, spacing: 0, lineHeight: 1)
    /// Small badge on a day tab ("YOU"): Barlow 700 11.
    var badge: AppTextStyle = .barlow(11, spacing: 0.08, lineHeight: 1)
    /// Day heading (.dayhead h2): Barlow 700 30 (36 on wide screens).
    var dayHeading: AppTextStyle = .barlow(30, spacing: 0.01, lineHeight: 1.02)
    /// "3 on now · Next at 10:15 AM" (.status): Barlow 600 17.
    var status: AppTextStyle = .barlow(17, .semibold, spacing: 0.04, lineHeight: 1.2)
    /// Half-hour block / section heading (.slot>h3): Barlow 700 18.
    var slotHeading: AppTextStyle = .barlow(18, spacing: 0.05, lineHeight: 1)
    /// "UP NEXT" line (.nowline): Barlow 700 15, pink.
    var nowLine: AppTextStyle = .barlow(15, spacing: 0.1, lineHeight: 1)
    /// Card meta row: category, time, duration (.meta): Barlow 600 14.
    var meta: AppTextStyle = .barlow(14, .semibold, spacing: 0.05, lineHeight: 1.2)
    /// Pills / tags ("LIVE · 12 MIN LEFT", "ANTHROPIC"): Barlow 700 12.5.
    var pill: AppTextStyle = .barlow(12.5, spacing: 0.06, lineHeight: 1)
    /// Session title on a card (.card h4): Atkinson 700 16.5.
    var cardTitle: AppTextStyle = .atkinson(16.5, .bold, lineHeight: 1.28)
    /// Session title on one of my cards (.card.me h4): Atkinson 700 19.
    var cardTitleMine: AppTextStyle = .atkinson(19, .bold, lineHeight: 1.25)
    /// Speakers line (.who) and where line (.where): Atkinson 14.
    var small: AppTextStyle = .atkinson(14, lineHeight: 1.35)
    /// Very small secondary text (.kid .s, notes): Atkinson 13.
    var tiny: AppTextStyle = .atkinson(13, lineHeight: 1.35)
    /// Group child time (.kid time): Barlow 600 14.5.
    var kidTime: AppTextStyle = .barlow(14.5, .semibold, spacing: 0.03, lineHeight: 1.35)
    /// Group child title (.kid .t): Atkinson 700 14.5.
    var kidTitle: AppTextStyle = .atkinson(14.5, .bold, lineHeight: 1.3)
    /// Body text: Atkinson 16 / 1.4.
    var body: AppTextStyle = .atkinson(16)
    /// Long-form description (.desc): Atkinson 16 / 1.55. Cap the width (Dimens.maxTextWidth).
    var description: AppTextStyle = .atkinson(16, lineHeight: 1.55)
    /// Sheet / screen title (.panel h2): Atkinson 700 22.
    var sheetTitle: AppTextStyle = .atkinson(22, .bold, lineHeight: 1.22)
    /// Section label in sheets ("SPEAKERS", "ABOUT"; .panel h3): Barlow 700 14, muted.
    var sectionLabel: AppTextStyle = .barlow(14, spacing: 0.1, lineHeight: 1)
    /// Buttons and link buttons (.links a): Barlow 700 15.
    var button: AppTextStyle = .barlow(15, spacing: 0.06, lineHeight: 1)
    /// Banner header "YOU'RE SPEAKING" (.mine-h): Barlow 700 14.
    var bannerLabel: AppTextStyle = .barlow(14, spacing: 0.1, lineHeight: 1)
    /// Banner countdown chip (.mine-h .cd): Barlow 700 16.
    var bannerCountdown: AppTextStyle = .barlow(16, spacing: 0.04, lineHeight: 1)
    /// Banner time (.mine-next time): Barlow 700 15.
    var bannerTime: AppTextStyle = .barlow(15, spacing: 0.06, lineHeight: 1.2)
    /// Banner talk title (.mine-next .t): Atkinson 700 19.
    var bannerTitle: AppTextStyle = .atkinson(19, .bold, lineHeight: 1.22)
    /// Directions route summary "ABOUT 250 M · 4 MIN · UP 1 LEVEL" (.wf .sum): Barlow 700 17.
    var routeSummary: AppTextStyle = .barlow(17, spacing: 0.04, lineHeight: 1.2)
    /// Walking step text (.steps li): Atkinson 16 / 1.4.
    var step: AppTextStyle = .atkinson(16)
    /// Level badge "LEVEL 2" (.wf .lv): Barlow 700 14. Scale up with copy() for Directions.
    var levelBadge: AppTextStyle = .barlow(14, spacing: 0.06, lineHeight: 1)
    /// Big glanceable figures (Directions distance, "LEVEL 2 · SALT PALACE"): Barlow 700 34.
    var display: AppTextStyle = .barlow(34, spacing: 0.02, lineHeight: 1.05)
    /// Biggest figure: Barlow 700 48.
    var displayLarge: AppTextStyle = .barlow(48, spacing: 0.01, lineHeight: 1)

    /// The Material roles (Kotlin `KcnaTypography`), for controls that want them.
    var material: KcnaTypography = KcnaTypography()

    /// Kotlin `AppType()`.
    static let standard = AppType()
}

/// Kotlin `KcnaTypography` (the Material 3 typography of `KcnaTheme`): Barlow for
/// display/headline/label, Atkinson for title/body. Compose Material components used these
/// implicitly; on iOS nothing does, so views pick them explicitly if at all.
struct KcnaTypography: Equatable, Sendable {
    var displayLarge: AppTextStyle = .barlow(57, spacing: 0, lineHeight: 1.1)
    var displayMedium: AppTextStyle = .barlow(45, spacing: 0, lineHeight: 1.1)
    var displaySmall: AppTextStyle = .barlow(36, spacing: 0.01, lineHeight: 1.1)
    var headlineLarge: AppTextStyle = .barlow(32, spacing: 0.01, lineHeight: 1.05)
    var headlineMedium: AppTextStyle = .barlow(28, spacing: 0.01, lineHeight: 1.05)
    var headlineSmall: AppTextStyle = .barlow(24, spacing: 0.02, lineHeight: 1.1)
    var titleLarge: AppTextStyle = .atkinson(22, .bold, lineHeight: 1.22)
    var titleMedium: AppTextStyle = .atkinson(16.5, .bold, lineHeight: 1.28)
    var titleSmall: AppTextStyle = .atkinson(14, .bold, lineHeight: 1.3)
    var bodyLarge: AppTextStyle = .atkinson(16)
    var bodyMedium: AppTextStyle = .atkinson(14, lineHeight: 1.35)
    var bodySmall: AppTextStyle = .atkinson(13, lineHeight: 1.35)
    var labelLarge: AppTextStyle = .barlow(15, spacing: 0.06, lineHeight: 1)
    var labelMedium: AppTextStyle = .barlow(14, .semibold, spacing: 0.05, lineHeight: 1.1)
    var labelSmall: AppTextStyle = .barlow(12.5, spacing: 0.06, lineHeight: 1)
}

// MARK: - CapsText

/// Text that is always uppercased (Core's `caps()`, Kotlin `CapsText`): use for every Barlow
/// (display) style. `lineLimit` is Kotlin `maxLines` (iOS truncates with "…" where Compose
/// clipped). VoiceOver reads the original text, so "UP NEXT" is spoken as words.
struct CapsText: View {
    let text: String
    let style: AppTextStyle
    var color: Color?
    var lineLimit: Int?

    init(_ text: String, style: AppTextStyle, color: Color? = nil, lineLimit: Int? = nil) {
        self.text = text
        self.style = style
        self.color = color
        self.lineLimit = lineLimit
    }

    var body: some View {
        if let color {
            label.foregroundStyle(color)
        } else {
            label
        }
    }

    private var label: some View {
        Text(verbatim: text.caps())
            .appTextStyle(style)
            .lineLimit(lineLimit)
            .accessibilityLabel(Text(verbatim: text))
    }
}

#Preview("Type") {
    ThemePreview {
        TypeSpecimen()
    }
}

/// A few of the named styles, for the preview.
private struct TypeSpecimen: View {
    @Environment(\.appType) private var type
    @Environment(\.appColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CapsText("KubeCon NA 2026", style: type.brand, color: colors.ink)
            CapsText("Wednesday", style: type.dayHeading, color: colors.ink)
            CapsText("Talk · 10:15–10:45 AM · 30 min", style: type.meta, color: colors.muted)
            Text(verbatim: "Scaling Kubernetes Controllers Without Losing Your Mind")
                .appTextStyle(type.cardTitle)
                .foregroundStyle(colors.ink)
            Text(verbatim: "Body text in Atkinson Hyperlegible, which wraps onto a second line at this width.")
                .appTextStyle(type.body)
                .foregroundStyle(colors.muted)
        }
    }
}
