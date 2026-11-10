import SwiftUI

/// Preview helper: the content twice, on the page background, in the light and the dark theme
/// (each pane has its own `.kcnaTheme()` under a fixed colour scheme). Use in `#Preview`:
///
///     #Preview("Pill") { ThemePreview { Pill("Live", tone: .you) } }
///
/// Not `#if DEBUG`: previews compile in every configuration.
struct ThemePreview<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ThemePreviewPane(content: content)
                    .kcnaTheme()
                    .environment(\.colorScheme, .light)
                ThemePreviewPane(content: content)
                    .kcnaTheme()
                    .environment(\.colorScheme, .dark)
            }
        }
    }
}

private struct ThemePreviewPane<Content: View>: View {
    let content: () -> Content
    @Environment(\.appColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(CGFloat(Dimens.pagePadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.bg)
    }
}
