import Foundation

/// Which theme colour a piece of the schedule, details or Going UI uses: the colour CHOICES of
/// the Kotlin composables (`if (mine) c.you else c.surface`, ...), made in Core so the SwiftUI
/// views only map a role to a `Color`. Every case is a Kotlin `AppColors` role; the Going
/// accents are the `AppColors.going*` / `clash*` extensions of ui/going/GoingUi.kt.
///
/// App: `Color(argb: role.argb(in: colors.palette))`, or a `switch` onto the matching
/// `AppColors` property (same names). ``argb(in:)`` computes exactly what Kotlin does.
enum PaletteRole: Sendable, Hashable {
    case bg
    case surface
    case ink
    case muted
    case line
    case you
    case onYou
    /// White on my pink cards at 80% (Kotlin `c.onYou.copy(alpha = 0.8f)`: an unselected star there).
    case onYouFaded
    case anthropic
    case onAnthropic
    case liveBorder
    case anthropicCardBg
    case anthropicCardBorder
    case anthropicRowBg
    /// The hands-on amber of notes ("Sold out", "Sponsored", "All-Access pass").
    case note
    /// A category's colour (Kotlin `c.category(key)`; muted for an unknown key).
    case category(String)
    /// Starred card fill (GoingUi.kt `goingCardBg`).
    case goingCardBg
    /// Starred card border (`goingCardBorder`).
    case goingCardBorder
    /// Starred kid row background (`goingRowBg`; transparent in light).
    case goingRowBg
    /// Starred kid row's left rule (`goingRule`).
    case goingRule
    /// "Clash" tag and note (`clash`: the note amber).
    case clash
    /// "Clash" note / notifications-off hint background (`clashBg`).
    case clashBg
    /// "Clash" note border (`clashBorder`).
    case clashBorder
    /// The details' "RSVP’d" button fill when going (Kotlin `mix(c.ink, c.surface, 0.09f)`).
    case goingButtonBg

    /// The role's 0xAARRGGBB value in `p` (Kotlin's formulas, Compose rounding).
    func argb(in p: AppPalette) -> UInt32 {
        switch self {
        case .bg: return p.bg
        case .surface: return p.surface
        case .ink: return p.ink
        case .muted: return p.muted
        case .line: return p.line
        case .you: return p.you
        case .onYou: return p.onYou
        case .onYouFaded: return argbWithAlpha(p.onYou, 0.8)
        case .anthropic: return p.anthropic
        case .onAnthropic: return p.onAnthropic
        case .liveBorder: return p.liveBorder
        case .anthropicCardBg: return p.anthropicCardBg
        case .anthropicCardBorder: return p.anthropicCardBorder
        case .anthropicRowBg: return p.anthropicRowBg
        case .note: return p.note
        case .category(let key): return p.category(key)
        // Light: the plain surface (an ink tint lands on the page colour and reads as greyed
        // out), so the border and the filled star carry it. Dark: a faint ink lift.
        case .goingCardBg: return p.isDark ? mixARGB(p.ink, p.surface, 0.045) : p.surface
        // Ink 60% into the hairline in light (the main cue there), 40% in dark.
        case .goingCardBorder: return mixARGB(p.ink, p.line, p.isDark ? 0.40 : 0.60)
        // A faint ink lift in dark only (in light it would look pressed): Color.Transparent.
        case .goingRowBg: return p.isDark ? argbWithAlpha(p.ink, 0.055) : 0x0000_0000
        case .goingRule: return mixARGB(p.ink, p.line, 0.60)
        case .clash: return p.note
        case .clashBg: return mixARGB(p.note, p.surface, 0.08)
        case .clashBorder: return mixARGB(p.note, p.line, 0.45)
        case .goingButtonBg: return mixARGB(p.ink, p.surface, 0.09)
        }
    }
}

/// One span of a line the Kotlin code builds with `buildAnnotatedString` (bold names, a pink
/// count, a muted room): concatenate one SwiftUI `Text` per run. `role` nil = the line's own
/// colour (Compose `Color.Unspecified`); `bold` = the line's style in bold.
struct TextRun: Sendable, Hashable {
    let text: String
    let bold: Bool
    let role: PaletteRole?

    init(_ text: String, bold: Bool = false, role: PaletteRole? = nil) {
        self.text = text
        self.bold = bold
        self.role = role
    }
}

extension Array where Element == TextRun {
    /// The runs' text, concatenated (what VoiceOver reads; also handy in tests).
    var plainText: String { map(\.text).joined() }
}
