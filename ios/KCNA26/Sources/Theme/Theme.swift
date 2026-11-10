import SwiftUI

// Kotlin theme/Theme.kt: `KcnaTheme` and the `AppTheme.colors` / `AppTheme.type` accessors.
// `Dimens` (the layout constants) is Core's (Theme/Dimens.swift, points).
//
//     @Environment(\.appColors) private var colors   // Kotlin AppTheme.colors
//     @Environment(\.appType) private var type        // Kotlin AppTheme.type
//
// The root view installs them once with `.kcnaTheme()`; previews do the same (ThemePreview).

private struct AppColorsKey: EnvironmentKey {
    static var defaultValue: AppColors { AppColors.light }
}

private struct AppTypeKey: EnvironmentKey {
    static var defaultValue: AppType { AppType.standard }
}

extension EnvironmentValues {
    /// The palette of the current colour scheme (Kotlin `AppTheme.colors` / `LocalAppColors`).
    /// Set by `.kcnaTheme()`; light until then.
    var appColors: AppColors {
        get { self[AppColorsKey.self] }
        set { self[AppColorsKey.self] = newValue }
    }

    /// The named text styles (Kotlin `AppTheme.type` / `LocalAppType`).
    var appType: AppType {
        get { self[AppTypeKey.self] }
        set { self[AppTypeKey.self] = newValue }
    }
}

/// Kotlin `KcnaTheme`: light/dark following the system. Installs ``AppColors`` for the
/// environment's colour scheme and ``AppType``, and maps the Material scheme's roles that iOS
/// controls read: tint (accent: buttons, toggles, text cursors, links) = `you` (Kotlin
/// `primary`), default foreground = `ink` (the root `Surface`'s `contentColor`).
struct KcnaThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let colors = AppColors.forScheme(colorScheme)
        content
            .environment(\.appColors, colors)
            .environment(\.appType, AppType.standard)
            .tint(colors.you)
            .foregroundStyle(colors.ink)
    }
}

extension View {
    /// Installs the app theme (Kotlin `KcnaTheme { ... }`). Apply at the root, inside anything
    /// that sets the colour scheme: `.kcnaTheme()` reads `\.colorScheme` where it is applied.
    func kcnaTheme() -> some View {
        modifier(KcnaThemeModifier())
    }

    /// The page background (`AppColors.bg`) under the whole view, safe areas included (Kotlin
    /// root `Surface(color = bg)` with edge-to-edge drawing). Works before or after
    /// `.kcnaTheme()`: it picks the palette from `\.colorScheme` itself, because a modifier
    /// applied after `.kcnaTheme()` sits outside the theme's environment.
    func kcnaPageBackground() -> some View {
        modifier(PageBackgroundModifier())
    }

    /// Kotlin `Modifier.widthIn(max = ...)`: at most `max` wide (e.g. `Dimens.maxTextWidth` for
    /// running text), placed at `alignment` when the parent offers more.
    func widthIn(max: CGFloat, alignment: Alignment = .leading) -> some View {
        frame(maxWidth: max, alignment: alignment)
    }
}

private struct PageBackgroundModifier: ViewModifier {
    // Not `\.appColors`: in `RootView().kcnaTheme().kcnaPageBackground()` this modifier is outside
    // the environment `.kcnaTheme()` sets (it only reaches RootView), so it would always read the
    // light default and paint a light page under the dark theme.
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(AppColors.forScheme(colorScheme).bg, ignoresSafeAreaEdges: .all)
    }
}

/// The page-width rules the Kotlin screens compute from their `BoxWithConstraints` width.
enum PageLayout {
    /// One centred column at most `maxContent` wide, with at least `Dimens.pagePadding` at each
    /// side (Kotlin `max(Dimens.pagePadding, (maxWidth - Dimens.maxContentWidth) / 2)`; Settings
    /// uses `Dimens.maxTextWidth`).
    static func sidePadding(forWidth width: CGFloat, maxContent: CGFloat = CGFloat(Dimens.maxContentWidth)) -> CGFloat {
        let centred: CGFloat = (width - maxContent) / 2
        return max(CGFloat(Dimens.pagePadding), centred)
    }
}
