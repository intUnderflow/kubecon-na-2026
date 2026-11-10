import SwiftUI

// STUB (shell): replaced by the session agent. Keep this signature.

/// Kotlin ui/session/SessionSheet.kt `SessionSheet`: the compact layout's details, as the
/// content of the shell's `.sheet` (the shell presents it while the session is open and the
/// Schedule is on top, with `.presentationDetents([.medium, .large])` opening at large, keyed by
/// `sessionId`). This view sets the rest of the presentation itself: Kotlin `containerColor =
/// surface` -> `.presentationBackground(colors.surface)`, the corner radius
/// (`.presentationCornerRadius(Dimens.sheetRadius)`), and its own grab bar beside the ×
/// (Kotlin `dragHandle = null` -> `.presentationDragIndicator(.hidden)`).
///
/// - Parameters:
///   - sessionId: the session to show.
///   - onDismiss: close the details (the × button; a swipe down is handled by the shell).
///   - onDirections: open Directions for this session (the shell hides the sheet while
///     Directions is on top and shows it again on back).
struct SessionSheet: View {
    let sessionId: String
    let onDismiss: () -> Void
    let onDirections: (String) -> Void

    init(sessionId: String, onDismiss: @escaping () -> Void, onDirections: @escaping (String) -> Void) {
        self.sessionId = sessionId
        self.onDismiss = onDismiss
        self.onDirections = onDirections
    }

    var body: some View {
        SessionDetails(sessionId: sessionId, onDirections: onDirections, onClose: onDismiss)
    }
}
