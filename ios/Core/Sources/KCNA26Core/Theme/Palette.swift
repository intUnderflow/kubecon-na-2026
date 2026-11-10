import Foundation

// The colour VALUES of the Kotlin theme (theme/Color.kt), as 0xAARRGGBB `UInt32`s, without
// any UI framework, so they are unit-tested here and the SwiftUI theme (app target) builds its
// `Color`s from them:
//
//     extension Color {
//         init(argb: UInt32) {
//             let c = argbComponents(argb)
//             self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
//         }
//     }
//     let palette = colorScheme == .dark ? AppPalette.dark : AppPalette.light
//     Color(argb: palette.you)
//
// Kotlin -> Swift names: `AppColors` -> ``AppPalette`` (the SwiftUI layer may define its own
// `AppColors` of SwiftUI Colors), `LightAppColors` -> ``AppPalette/light``, `DarkAppColors` ->
// ``AppPalette/dark``; every role keeps its Kotlin name. `CategoryLight` / `CategoryDark` keep
// theirs. Derived colours (`liveBorder`, `anthropicCardBg`, ...) are computed exactly as
// Compose does (Float channels, then `x * 255 + 0.5` truncated per channel).

/// Category colours, identical to schedule.json "categories" (a unit test checks this). In
/// order: key, talk, mnt, hands, show, com, soc, colo, log.
let CategoryLight: OrderedMap<String, UInt32> = [
    "key": 0xFFC2_255B,
    "talk": 0xFF2E_64A6,
    "mnt": 0xFF0E_7C66,
    "hands": 0xFF9F_6410,
    "show": 0xFF6B_4BBE,
    "com": 0xFF4A_7612,
    "soc": 0xFF8A_5A12,
    "colo": 0xFF0A_6E86,
    "log": 0xFF8A_949B,
]

let CategoryDark: OrderedMap<String, UInt32> = [
    "key": 0xFFFF_6A97,
    "talk": 0xFF77_AAEC,
    "mnt": 0xFF45_C6A3,
    "hands": 0xFFE4_AC4A,
    "show": 0xFFA9_8DF2,
    "com": 0xFF9C_CA50,
    "soc": 0xFFD9_B061,
    "colo": 0xFF4D_C2DB,
    "log": 0xFF6F_7C86,
]

/// Named colours from the web version's CSS (`:root` and the dark media query), as
/// 0xAARRGGBB. Kotlin `AppColors`.
///
/// CSS name -> role: --bg -> ``bg``, --surface -> ``surface``, --ink -> ``ink``,
/// --muted -> ``muted``, --line -> ``line``, --brine -> ``you`` (pink: you / now / live),
/// --ant -> ``anthropic`` (clay: Anthropic colleagues), --c-<key> -> ``category(_:)``.
struct AppPalette: Sendable, Hashable {
    let isDark: Bool
    /// Page background (#F1F2EE / #0D141A).
    let bg: UInt32
    /// Cards, sheets, inputs (#FFFFFF / #15202A).
    let surface: UInt32
    /// Main text (#13202A / #E6EBEE).
    let ink: UInt32
    /// Secondary text (#58646E / #93A1AA).
    let muted: UInt32
    /// Hairlines and borders (#D9DDD8 / #24313B).
    let line: UInt32
    /// "You / now / live" pink (#C2255B / #E2457A). Text on it is ``onYou``.
    let you: UInt32
    /// Anthropic clay (#B9572F / #E08A62). Text on it is ``onAnthropic``.
    let anthropic: UInt32
    /// Category colours by key (key, talk, mnt, hands, show, com, soc, colo, log).
    let categories: OrderedMap<String, UInt32>

    /// Kotlin `LightAppColors`.
    static let light = AppPalette(
        isDark: false,
        bg: 0xFFF1_F2EE,
        surface: 0xFFFF_FFFF,
        ink: 0xFF13_202A,
        muted: 0xFF58_646E,
        line: 0xFFD9_DDD8,
        you: 0xFFC2_255B,
        anthropic: 0xFFB9_572F,
        categories: CategoryLight
    )

    /// Kotlin `DarkAppColors`.
    static let dark = AppPalette(
        isDark: true,
        bg: 0xFF0D_141A,
        surface: 0xFF15_202A,
        ink: 0xFFE6_EBEE,
        muted: 0xFF93_A1AA,
        line: 0xFF24_313B,
        you: 0xFFE2_457A,
        anthropic: 0xFFE0_8A62,
        categories: CategoryDark
    )

    /// ``dark`` or ``light``.
    static func forDark(_ dark: Bool) -> AppPalette { dark ? .dark : .light }

    /// Text/icons on ``you`` (white in both themes).
    var onYou: UInt32 { 0xFFFF_FFFF }

    /// Text/icons on ``anthropic``.
    var onAnthropic: UInt32 { 0xFFFF_FFFF }

    /// Alias of ``you`` (the CSS calls it --brine).
    var pink: UInt32 { you }

    /// Alias of ``anthropic``.
    var clay: UInt32 { anthropic }

    /// Category colour by key; ``muted`` for unknown keys.
    func category(_ key: String) -> UInt32 { categories[key] ?? muted }

    /// `.card.live` border: color-mix(you 55%, line).
    var liveBorder: UInt32 { mixARGB(you, line, 0.55) }

    /// `.card.ant` background: color-mix(anthropic 9%, surface).
    var anthropicCardBg: UInt32 { mixARGB(anthropic, surface, 0.09) }

    /// `.card.ant` border: color-mix(anthropic 45%, line).
    var anthropicCardBorder: UInt32 { mixARGB(anthropic, line, 0.45) }

    /// `.kid.ant` row background: anthropic at 10% over transparent.
    var anthropicRowBg: UInt32 { argbWithAlpha(anthropic, 0.10) }

    /// Pressed-row overlay: ink at 6%.
    var pressed: UInt32 { argbWithAlpha(ink, 0.06) }

    /// Sheet scrim: rgba(8,14,20,.45).
    var scrim: UInt32 { 0x7308_0E14 }

    /// Map "me" dot / accuracy circle colour (the CSS uses --c-talk).
    var mapMe: UInt32 { category("talk") }

    /// Hyatt building fill on the map: color-mix(talk 14%, surface).
    var mapHyatt: UInt32 { mixARGB(category("talk"), surface, 0.14) }

    /// Note text (e.g. "Sold out") in `.where .note` uses the hands-on colour.
    var note: UInt32 { category("hands") }

    // Container tints of the Kotlin Material scheme (Theme.kt `toColorScheme`), for controls
    // that want the same look.

    /// primaryContainer: color-mix(you 14%, surface).
    var primaryContainer: UInt32 { mixARGB(you, surface, 0.14) }
    /// secondaryContainer: color-mix(ink 10%, surface).
    var secondaryContainer: UInt32 { mixARGB(ink, surface, 0.10) }
    /// tertiaryContainer: color-mix(anthropic 12%, surface).
    var tertiaryContainer: UInt32 { mixARGB(anthropic, surface, 0.12) }
    /// surfaceVariant: color-mix(ink 6%, surface).
    var surfaceVariant: UInt32 { mixARGB(ink, surface, 0.06) }
}

/// The channels of 0xAARRGGBB as 0...1 Doubles (for `Color(.sRGB, red:green:blue:opacity:)`).
func argbComponents(_ argb: UInt32) -> (red: Double, green: Double, blue: Double, alpha: Double) {
    (Double((argb >> 16) & 0xFF) / 255, Double((argb >> 8) & 0xFF) / 255,
     Double(argb & 0xFF) / 255, Double(argb >> 24) / 255)
}

/// Compose `Color(Int)` channel: byte / 255 as a Float.
@inline(__always)
private func channel(_ c: UInt32, _ shift: UInt32) -> Float { Float((c >> shift) & 0xFF) / 255 }

/// Compose sRGB `Color(red, green, blue, alpha)`: `(x * 255 + 0.5).toInt()` per channel.
@inline(__always)
private func quantize(_ v: Float) -> UInt32 { UInt32(Int(v * 255 + 0.5)) & 0xFF }

/// CSS `color-mix(in srgb, a p, b)`: `fractionA` of `a` mixed with the rest of `b`, per sRGB
/// channel including alpha (Kotlin `mix`, with Compose's Float maths and rounding).
func mixARGB(_ a: UInt32, _ b: UInt32, _ fractionA: Float) -> UInt32 {
    let f = Swift.min(Swift.max(fractionA, 0), 1)
    let g: Float = 1 - f
    let r = quantize(channel(a, 16) * f + channel(b, 16) * g)
    let gr = quantize(channel(a, 8) * f + channel(b, 8) * g)
    let bl = quantize(channel(a, 0) * f + channel(b, 0) * g)
    let al = quantize(channel(a, 24) * f + channel(b, 24) * g)
    return al << 24 | r << 16 | gr << 8 | bl
}

/// Compose `color.copy(alpha = alpha)`.
func argbWithAlpha(_ c: UInt32, _ alpha: Float) -> UInt32 {
    quantize(alpha) << 24 | quantize(channel(c, 16)) << 16 | quantize(channel(c, 8)) << 8 | quantize(channel(c, 0))
}
