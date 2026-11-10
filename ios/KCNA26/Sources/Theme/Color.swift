import SwiftUI

// Kotlin theme/Color.kt. The colour VALUES live in Core (Theme/Palette.swift: `AppPalette`,
// `CategoryLight`, `CategoryDark`, `mixARGB`, `argbWithAlpha`), where they are unit-tested; this
// file only turns them into SwiftUI `Color`s. Never hard-code a hex value in a view: read
// `@Environment(\.appColors)` (installed by `.kcnaTheme()`, see Theme.swift).

extension Color {
    /// A colour from a 0xAARRGGBB value (Core's palette encoding), in sRGB like Compose's `Color(Int)`.
    init(argb: UInt32) {
        let c = argbComponents(argb)
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }
}

/// Named colours from the web version's CSS (`:root` and the dark media query), as SwiftUI
/// colours. Kotlin `AppColors` (read there with `AppTheme.colors`); here
/// `@Environment(\.appColors) private var colors`.
///
/// CSS name -> role: --bg -> ``bg``, --surface -> ``surface``, --ink -> ``ink``,
/// --muted -> ``muted``, --line -> ``line``, --brine -> ``you`` (pink: you / now / live),
/// --ant -> ``anthropic`` (clay: Anthropic colleagues), --c-<key> -> ``category(_:)``.
///
/// Kotlin `color.copy(alpha = a)` on these (all opaque except ``anthropicRowBg``, ``pressed``,
/// ``scrim``, ``goingRowBg``) is `color.opacity(a)`. A one-off `mix(a, b, f)` is
/// `Color(argb: mixARGB(colors.palette.a, colors.palette.b, f))`.
struct AppColors: Sendable {
    /// The Core palette these colours come from (0xAARRGGBB values, for `mixARGB`).
    let palette: AppPalette

    /// True for the dark palette (Kotlin `isDark` / `isDarkTheme()`).
    var isDark: Bool { palette.isDark }

    /// Page background (#F1F2EE / #0D141A).
    let bg: Color
    /// Cards, sheets, inputs (#FFFFFF / #15202A).
    let surface: Color
    /// Main text (#13202A / #E6EBEE).
    let ink: Color
    /// Secondary text (#58646E / #93A1AA).
    let muted: Color
    /// Hairlines and borders (#D9DDD8 / #24313B).
    let line: Color
    /// "You / now / live" pink (#C2255B / #E2457A). Text on it is ``onYou``.
    let you: Color
    /// Anthropic clay (#B9572F / #E08A62). Text on it is ``onAnthropic``.
    let anthropic: Color
    /// Category colours by key, in palette order (key, talk, mnt, hands, show, com, soc, colo, log).
    let categories: OrderedMap<String, Color>

    /// Text/icons on ``you`` (white in both themes).
    let onYou: Color
    /// Text/icons on ``anthropic`` (white).
    let onAnthropic: Color
    /// Alias of ``you`` (the CSS calls it --brine).
    var pink: Color { you }
    /// Alias of ``anthropic``.
    var clay: Color { anthropic }

    /// `.card.live` border: color-mix(you 55%, line).
    let liveBorder: Color
    /// `.card.ant` background: color-mix(anthropic 9%, surface).
    let anthropicCardBg: Color
    /// `.card.ant` border: color-mix(anthropic 45%, line).
    let anthropicCardBorder: Color
    /// `.kid.ant` row background: anthropic at 10% over transparent.
    let anthropicRowBg: Color
    /// Pressed-row overlay: ink at 6%.
    let pressed: Color
    /// Sheet scrim: rgba(8,14,20,.45). (iOS sheets dim with the system scrim; kept for custom overlays.)
    let scrim: Color
    /// Map "me" dot / accuracy circle colour (the CSS uses --c-talk).
    let mapMe: Color
    /// Hyatt building fill on the map: color-mix(talk 14%, surface).
    let mapHyatt: Color
    /// Note text (e.g. "Sold out") in `.where .note` uses the hands-on colour.
    let note: Color

    /// Kotlin Material scheme `primaryContainer`: color-mix(you 14%, surface).
    let primaryContainer: Color
    /// Kotlin Material scheme `secondaryContainer`: color-mix(ink 10%, surface).
    let secondaryContainer: Color
    /// Kotlin Material scheme `tertiaryContainer`: color-mix(anthropic 12%, surface).
    let tertiaryContainer: Color
    /// Kotlin Material scheme `surfaceVariant`: color-mix(ink 6%, surface).
    let surfaceVariant: Color

    // "Going" accents (Kotlin ui/going/GoingUi.kt `AppColors.going*` / `clash*` extensions). They
    // live here because the schedule cards, the Going UI and the details all use them.

    /// Starred card fill. Light: the plain surface (an ink tint lands on the page colour and reads
    /// as greyed out), so the border and the filled star carry it. Dark: a faint ink lift.
    let goingCardBg: Color
    /// Starred card border: ink 60% into the hairline in light (the main cue there), 40% in dark.
    let goingCardBorder: Color
    /// Starred kid row inside a group card: a faint ink lift in dark only (in light it would look pressed).
    let goingRowBg: Color
    /// Starred kid row: the ink rule down its left edge, in both themes.
    let goingRule: Color
    /// "Clash" tag and note: the hands-on amber (as "Sold out").
    let clash: Color
    /// "Clash" note background: color-mix(note 8%, surface).
    let clashBg: Color
    /// "Clash" note border: color-mix(note 45%, line).
    let clashBorder: Color

    init(_ p: AppPalette) {
        palette = p
        bg = Color(argb: p.bg)
        surface = Color(argb: p.surface)
        ink = Color(argb: p.ink)
        muted = Color(argb: p.muted)
        line = Color(argb: p.line)
        you = Color(argb: p.you)
        anthropic = Color(argb: p.anthropic)
        categories = p.categories.mapValues { Color(argb: $0) }
        onYou = Color(argb: p.onYou)
        onAnthropic = Color(argb: p.onAnthropic)
        liveBorder = Color(argb: p.liveBorder)
        anthropicCardBg = Color(argb: p.anthropicCardBg)
        anthropicCardBorder = Color(argb: p.anthropicCardBorder)
        anthropicRowBg = Color(argb: p.anthropicRowBg)
        pressed = Color(argb: p.pressed)
        scrim = Color(argb: p.scrim)
        mapMe = Color(argb: p.mapMe)
        mapHyatt = Color(argb: p.mapHyatt)
        note = Color(argb: p.note)
        primaryContainer = Color(argb: p.primaryContainer)
        secondaryContainer = Color(argb: p.secondaryContainer)
        tertiaryContainer = Color(argb: p.tertiaryContainer)
        surfaceVariant = Color(argb: p.surfaceVariant)

        let goingBg: UInt32 = p.isDark ? mixARGB(p.ink, p.surface, 0.045) : p.surface
        let goingBorderFraction: Float = p.isDark ? 0.40 : 0.60
        goingCardBg = Color(argb: goingBg)
        goingCardBorder = Color(argb: mixARGB(p.ink, p.line, goingBorderFraction))
        goingRowBg = p.isDark ? Color(argb: argbWithAlpha(p.ink, 0.055)) : Color.clear
        goingRule = Color(argb: mixARGB(p.ink, p.line, 0.60))
        clash = Color(argb: p.note)
        clashBg = Color(argb: mixARGB(p.note, p.surface, 0.08))
        clashBorder = Color(argb: mixARGB(p.note, p.line, 0.45))
    }

    /// Kotlin `LightAppColors`.
    static let light = AppColors(AppPalette.light)
    /// Kotlin `DarkAppColors`.
    static let dark = AppColors(AppPalette.dark)

    /// The palette for a colour scheme (Kotlin `KcnaTheme(darkTheme = isSystemInDarkTheme())`).
    static func forScheme(_ scheme: ColorScheme) -> AppColors {
        scheme == .dark ? AppColors.dark : AppColors.light
    }

    /// Category colour by key; ``muted`` for unknown keys (Kotlin `AppColors.category(key)` /
    /// `categoryColor(key)`).
    func category(_ key: String) -> Color {
        categories[key] ?? muted
    }

    /// A schedule.json category's own colour for this theme (Kotlin `Category.color(dark)`);
    /// the palette colour for its key if the file's colour is malformed. The two are identical
    /// for the bundled data (a Core unit test checks it).
    func color(of category: Category) -> Color {
        if let argb = try? category.argb(dark: isDark) {
            return Color(argb: argb)
        }
        return self.category(category.key)
    }
}
