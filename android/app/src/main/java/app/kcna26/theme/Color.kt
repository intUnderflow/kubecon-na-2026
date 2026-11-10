package app.kcna26.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import app.kcna26.data.Category

/**
 * Named colours from the web version's CSS (`:root` and the dark media query).
 * Read them with `AppTheme.colors` inside [KcnaTheme].
 *
 * CSS name → token: --bg → [bg], --surface → [surface], --ink → [ink],
 * --muted → [muted], --line → [line], --brine → [you] (pink: you / now / live),
 * --ant → [anthropic] (clay: Anthropic colleagues), --c-<key> → [category].
 */
@Immutable
data class AppColors(
    val isDark: Boolean,
    /** Page background (#F1F2EE / #0D141A). */
    val bg: Color,
    /** Cards, sheets, inputs (#FFFFFF / #15202A). */
    val surface: Color,
    /** Main text (#13202A / #E6EBEE). */
    val ink: Color,
    /** Secondary text (#58646E / #93A1AA). */
    val muted: Color,
    /** Hairlines and borders (#D9DDD8 / #24313B). */
    val line: Color,
    /** "You / now / live" pink (#C2255B / #E2457A). Text on it is [onYou]. */
    val you: Color,
    /** Anthropic clay (#B9572F / #E08A62). Text on it is [onAnthropic]. */
    val anthropic: Color,
    /** Category colours by key (key, talk, mnt, hands, show, com, soc, colo, log). */
    val categories: Map<String, Color>,
) {
    /** Text/icons on [you] (white in both themes). */
    val onYou: Color get() = Color.White

    /** Text/icons on [anthropic]. */
    val onAnthropic: Color get() = Color.White

    /** Alias of [you] (the CSS calls it --brine). */
    val pink: Color get() = you

    /** Alias of [anthropic]. */
    val clay: Color get() = anthropic

    /** Category colour by key; [muted] for unknown keys. */
    fun category(key: String): Color = categories[key] ?: muted

    /** `.card.live` border: color-mix(you 55%, line). */
    val liveBorder: Color get() = mix(you, line, 0.55f)

    /** `.card.ant` background: color-mix(anthropic 9%, surface). */
    val anthropicCardBg: Color get() = mix(anthropic, surface, 0.09f)

    /** `.card.ant` border: color-mix(anthropic 45%, line). */
    val anthropicCardBorder: Color get() = mix(anthropic, line, 0.45f)

    /** `.kid.ant` row background: anthropic at 10% over transparent. */
    val anthropicRowBg: Color get() = anthropic.copy(alpha = 0.10f)

    /** Pressed-row overlay: ink at 6%. */
    val pressed: Color get() = ink.copy(alpha = 0.06f)

    /** Sheet scrim: rgba(8,14,20,.45). */
    val scrim: Color get() = Color(0x73080E14)

    /** Map "me" dot / accuracy circle colour (the CSS uses --c-talk). */
    val mapMe: Color get() = category("talk")

    /** Hyatt building fill on the map: color-mix(talk 14%, surface). */
    val mapHyatt: Color get() = mix(category("talk"), surface, 0.14f)

    /** Note text (e.g. "Sold out") in `.where .note` uses the hands-on colour. */
    val note: Color get() = category("hands")
}

/** CSS `color-mix(in srgb, a p, b)`: [fractionA] of [a] mixed with the rest of [b], per sRGB channel. */
fun mix(a: Color, b: Color, fractionA: Float): Color {
    val f = fractionA.coerceIn(0f, 1f)
    val g = 1f - f
    return Color(
        red = a.red * f + b.red * g,
        green = a.green * f + b.green * g,
        blue = a.blue * f + b.blue * g,
        alpha = a.alpha * f + b.alpha * g,
    )
}

/** Category colours, identical to schedule.json "categories" (a unit test checks this). */
internal val CategoryLight: Map<String, Color> = linkedMapOf(
    "key" to Color(0xFFC2255B),
    "talk" to Color(0xFF2E64A6),
    "mnt" to Color(0xFF0E7C66),
    "hands" to Color(0xFF9F6410),
    "show" to Color(0xFF6B4BBE),
    "com" to Color(0xFF4A7612),
    "soc" to Color(0xFF8A5A12),
    "colo" to Color(0xFF0A6E86),
    "log" to Color(0xFF8A949B),
)

internal val CategoryDark: Map<String, Color> = linkedMapOf(
    "key" to Color(0xFFFF6A97),
    "talk" to Color(0xFF77AAEC),
    "mnt" to Color(0xFF45C6A3),
    "hands" to Color(0xFFE4AC4A),
    "show" to Color(0xFFA98DF2),
    "com" to Color(0xFF9CCA50),
    "soc" to Color(0xFFD9B061),
    "colo" to Color(0xFF4DC2DB),
    "log" to Color(0xFF6F7C86),
)

val LightAppColors = AppColors(
    isDark = false,
    bg = Color(0xFFF1F2EE),
    surface = Color(0xFFFFFFFF),
    ink = Color(0xFF13202A),
    muted = Color(0xFF58646E),
    line = Color(0xFFD9DDD8),
    you = Color(0xFFC2255B),
    anthropic = Color(0xFFB9572F),
    categories = CategoryLight,
)

val DarkAppColors = AppColors(
    isDark = true,
    bg = Color(0xFF0D141A),
    surface = Color(0xFF15202A),
    ink = Color(0xFFE6EBEE),
    muted = Color(0xFF93A1AA),
    line = Color(0xFF24313B),
    you = Color(0xFFE2457A),
    anthropic = Color(0xFFE08A62),
    categories = CategoryDark,
)

val LocalAppColors = staticCompositionLocalOf { LightAppColors }

/** A schedule.json category's colour for the given theme. */
fun Category.color(dark: Boolean): Color = Color(if (dark) darkArgb else lightArgb)

/** Category colour by key in the current theme. */
@Composable
fun categoryColor(key: String): Color = LocalAppColors.current.category(key)

/** True when the dark palette is active. */
@Composable
fun isDarkTheme(): Boolean = LocalAppColors.current.isDark
