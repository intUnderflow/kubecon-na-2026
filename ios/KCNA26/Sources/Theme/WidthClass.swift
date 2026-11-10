import SwiftUI

// The environment part of Kotlin ui/adaptive/WidthClass.kt (`LocalWidthClass`,
// `currentWindowWidth()`). The pure `WidthClass` enum (thresholds, `isWide`, `fromWidth`) is
// Core's: ios/Core/Sources/KCNA26Core/UILogic/Adaptive/WidthClassRule.swift (one module, so it
// must not be declared here as well).

private struct WidthClassKey: EnvironmentKey {
    static var defaultValue: WidthClass { WidthClass.compact }
}

private struct WindowWidthKey: EnvironmentKey {
    static var defaultValue: CGFloat { 0 }
}

extension EnvironmentValues {
    /// The width class of the whole window (Kotlin `LocalWidthClass.current`). Set at the root by
    /// `.readsWindowWidth()`; `.compact` until then.
    var widthClass: WidthClass {
        get { self[WidthClassKey.self] }
        set { self[WidthClassKey.self] = newValue }
    }

    /// The window width in points (Kotlin `currentWindowWidth()`); 0 until `.readsWindowWidth()`.
    var windowWidth: CGFloat {
        get { self[WindowWidthKey.self] }
        set { self[WindowWidthKey.self] = newValue }
    }
}

/// Measures the window (the root view's full size, safe-area insets included, like Android's
/// window size) and provides ``WidthClass`` and the width to everything inside. Recomputed on
/// rotation, Split View and Stage Manager resizes.
struct WindowWidthReader: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let insets: EdgeInsets = proxy.safeAreaInsets
            let width: CGFloat = proxy.size.width + insets.leading + insets.trailing
            content
                .environment(\.windowWidth, width)
                .environment(\.widthClass, WidthClass.fromWidth(Double(width)))
        }
    }
}

extension View {
    /// Apply once at the root, around the whole UI (Kotlin MainActivity's
    /// `LocalWidthClass provides currentWidthClass()`). The content fills the window.
    func readsWindowWidth() -> some View {
        modifier(WindowWidthReader())
    }
}
