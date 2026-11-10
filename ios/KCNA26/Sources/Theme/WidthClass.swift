import SwiftUI

// Kotlin ui/adaptive/WidthClass.kt. The rule is pure, but Core had no UILogic/Adaptive helper
// when this was written, so it lives here (Core-free, the same thresholds via Core's Dimens).
// If Core gains `WidthClass`, delete the enum below and keep the environment part.

/// Window width class.
/// - ``compact`` < 600 pt: every iPhone in portrait (Kotlin: the Pixel 10 Pro Fold cover
///   screen, ~443 dp). Primary design.
/// - ``medium`` 600–839 pt and ``expanded`` ≥ 840 pt: iPad, iPhone landscape, wide Split View /
///   Stage Manager windows (Kotlin: the unfolded inner screen, ~852 × 883 dp).
enum WidthClass: Sendable, Equatable {
    case compact
    case medium
    case expanded

    /// Medium or Expanded: use list–detail / two columns.
    var isWide: Bool { self != .compact }

    /// Kotlin `WidthClass.fromWidth(width)`.
    static func fromWidth(_ width: Double) -> WidthClass {
        if width >= Dimens.expandedBreakpoint { return .expanded }
        if width >= Dimens.mediumBreakpoint { return .medium }
        return .compact
    }
}

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
