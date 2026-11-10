package app.kcna26.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** Theme accessors, like MaterialTheme: `AppTheme.colors.you`, `AppTheme.type.cardTitle`. */
object AppTheme {
    val colors: AppColors
        @Composable @ReadOnlyComposable get() = LocalAppColors.current
    val type: AppType
        @Composable @ReadOnlyComposable get() = LocalAppType.current
}

/** Layout conventions. */
object Dimens {
    /** Minimum touch target for anything tappable. */
    val touchTarget = 48.dp
    /** Horizontal page padding on phones (.wrap). */
    val pagePadding = 16.dp
    /** Gap between cards (.list gap). */
    val cardGap = 8.dp
    /** Card corner radius (.card). */
    val cardRadius = 10.dp
    /** Banner / big panel radius (.mine). */
    val bannerRadius = 14.dp
    /** Sheet top corner radius (.panel). */
    val sheetRadius = 18.dp
    /** Left category stripe on cards (.card border-left). */
    val categoryStripe = 4.dp
    /** Max width of a single content column (.wrap max-width 760px). */
    val maxContentWidth = 760.dp
    /** Max width for running text (~65ch). */
    val maxTextWidth = 620.dp
    /** Width-class breakpoints (see WidthClass). */
    val mediumBreakpoint = 600.dp
    val expandedBreakpoint = 840.dp
}

/**
 * Light/dark theme following the system. Provides [AppTheme.colors],
 * [AppTheme.type] and a Material 3 scheme mapped from the web palette:
 *
 * - colorScheme.background = colorScheme.surface = AppColors.bg (pages, top bars)
 * - surfaceContainer* (cards, sheets, dialogs, menus) = AppColors.surface
 * - primary = you (pink), secondary = ink, tertiary = anthropic (clay)
 * - onSurface = ink, onSurfaceVariant = muted, outline/outlineVariant = line
 */
@Composable
fun KcnaTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (darkTheme) DarkAppColors else LightAppColors
    CompositionLocalProvider(
        LocalAppColors provides colors,
        LocalAppType provides AppType(),
    ) {
        MaterialTheme(
            colorScheme = colors.toColorScheme(),
            typography = KcnaTypography,
            content = content,
        )
    }
}

internal fun AppColors.toColorScheme(): ColorScheme {
    val base = if (isDark) darkColorScheme() else lightColorScheme()
    return base.copy(
        primary = you,
        onPrimary = onYou,
        primaryContainer = mix(you, surface, 0.14f),
        onPrimaryContainer = ink,
        inversePrimary = you,
        secondary = ink,
        onSecondary = bg,
        secondaryContainer = mix(ink, surface, 0.10f),
        onSecondaryContainer = ink,
        tertiary = anthropic,
        onTertiary = onAnthropic,
        tertiaryContainer = mix(anthropic, surface, 0.12f),
        onTertiaryContainer = ink,
        background = bg,
        onBackground = ink,
        surface = bg,
        onSurface = ink,
        surfaceVariant = mix(ink, surface, 0.06f),
        onSurfaceVariant = muted,
        surfaceTint = Color.Transparent,
        inverseSurface = ink,
        inverseOnSurface = bg,
        outline = line,
        outlineVariant = line,
        scrim = scrim,
        surfaceBright = surface,
        surfaceDim = bg,
        surfaceContainerLowest = surface,
        surfaceContainerLow = surface,
        surfaceContainer = surface,
        surfaceContainerHigh = surface,
        surfaceContainerHighest = surface,
    )
}
