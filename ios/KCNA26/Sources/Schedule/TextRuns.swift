import SwiftUI

// Turning Core's colour roles and annotated-string runs into SwiftUI (Core's UILogic makes the
// Kotlin composables' colour choices as `PaletteRole`s and their `buildAnnotatedString` lines as
// `[TextRun]`; see Core UILogic/Schedule/StyleRoles.swift). Used by the Schedule, Going and
// details views.

extension AppColors {
    /// The colour of a Core ``PaletteRole`` in this palette (exactly Kotlin's formula:
    /// `role.argb(in: palette)`), e.g. `colors.color(model.colors.border)`.
    func color(_ role: PaletteRole) -> Color {
        Color(argb: role.argb(in: palette))
    }
}

/// Kotlin `Text(buildAnnotatedString { ... }, style = style, color = c)`: one `Text` per run,
/// concatenated. A bold run uses `style`'s bold face (Kotlin `SpanStyle(fontWeight = Bold)`), a
/// run with a role its colour; the rest take the line's font and colour. Apply the line's style
/// and colour to the result:
///
///     runsText(ScheduleHeaderLogic.dayStatusLine(st), style: type.status, colors: colors)
///         .appTextStyle(type.status)
///         .foregroundStyle(colors.muted)
func runsText(_ runs: [TextRun], style: AppTextStyle, colors: AppColors) -> Text {
    let boldFont: Font = style.bold.font
    var line = Text(verbatim: "")
    for run in runs {
        var piece = Text(verbatim: run.text)
        if run.bold {
            piece = piece.font(boldFont)
        }
        if let role = run.role {
            piece = piece.foregroundStyle(colors.color(role))
        }
        line = line + piece
    }
    return line
}
