import SwiftUI

/// The search box of the schedule ("Search talks, speakers, rooms") and of the speaker pickers
/// ("Search speakers"; Settings and the first-run sheet): a 48 pt surface field with a hairline
/// border, a muted magnifying glass, the muted placeholder and a clear button while there is
/// text (Kotlin `ScheduleSearchField` / `SpeakerSearchField`). No autocorrection; the return
/// key says Search and closes the keyboard (Kotlin `ImeAction.Search` + `keyboard.hide()`).
/// Outer padding is the caller's (the schedule adds `top 14`).
struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var autocapitalization: TextInputAutocapitalization
    var focus: FocusState<Bool>.Binding?

    @Environment(\.appColors) private var colors
    @Environment(\.appType) private var type

    /// - Parameters:
    ///   - autocapitalization: `.never` for the schedule (Kotlin `KeyboardCapitalization.None`),
    ///     `.words` for speaker names.
    ///   - focus: bind it to clear the focus from outside (Kotlin `focus.clearFocus()` when a
    ///     session opens or a speaker is picked).
    init(
        text: Binding<String>,
        placeholder: String,
        autocapitalization: TextInputAutocapitalization = .never,
        focus: FocusState<Bool>.Binding? = nil
    ) {
        _text = text
        self.placeholder = placeholder
        self.autocapitalization = autocapitalization
        self.focus = focus
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(Dimens.cardRadius), style: .circular)
        HStack(spacing: 0) {
            AppIconImage(.search, size: 19)
                .foregroundStyle(colors.muted)
                .padding(.trailing, 9)
            field
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
            if text.isEmpty {
                Color.clear.frame(width: 12, height: 1)
            } else {
                Button {
                    text = ""
                } label: {
                    AppIconImage(.clearSearch, size: 20)
                        .foregroundStyle(colors.muted)
                        .frame(width: CGFloat(Dimens.touchTarget), height: CGFloat(Dimens.touchTarget))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "Clear search"))
            }
        }
        .padding(.leading, 12)
        .frame(minHeight: CGFloat(Dimens.touchTarget))
        .background { shape.fill(colors.surface) }
        .overlay { shape.strokeBorder(colors.line, lineWidth: 1) }
    }

    @ViewBuilder
    private var field: some View {
        let prompt: Text = Text(verbatim: placeholder).foregroundStyle(colors.muted)
        let input = TextField(text: $text, prompt: prompt) {
            Text(verbatim: placeholder)
        }
        .appTextStyle(type.body)
        .foregroundStyle(colors.ink)
        .tint(colors.you)
        .textInputAutocapitalization(autocapitalization)
        .autocorrectionDisabled(true)
        .submitLabel(.search)
        if let focus {
            input.focused(focus)
        } else {
            input
        }
    }
}

#Preview("Search field") {
    ThemePreview {
        SearchFieldSpecimen()
    }
}

private struct SearchFieldSpecimen: View {
    @State private var empty = ""
    @State private var query = "argo"

    var body: some View {
        SearchField(text: $empty, placeholder: "Search talks, speakers, rooms")
        SearchField(text: $query, placeholder: "Search speakers", autocapitalization: .words)
    }
}
